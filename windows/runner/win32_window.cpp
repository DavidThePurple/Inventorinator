#include "win32_window.h"

#include <dwmapi.h>
#include <flutter_windows.h>

#include <algorithm>

#include "resource.h"

namespace {

/// Window attribute that enables dark mode window decorations.
///
/// Redefined in case the developer's machine has a Windows SDK older than
/// version 10.0.22000.0.
/// See: https://docs.microsoft.com/windows/win32/api/dwmapi/ne-dwmapi-dwmwindowattribute
#ifndef DWMWA_USE_IMMERSIVE_DARK_MODE
#define DWMWA_USE_IMMERSIVE_DARK_MODE 20
#endif

constexpr const wchar_t kWindowClassName[] = L"FLUTTER_RUNNER_WIN32_WINDOW";

/// Registry key for app theme preference.
///
/// A value of 0 indicates apps should use dark mode. A non-zero or missing
/// value indicates apps should use light mode.
constexpr const wchar_t kGetPreferredBrightnessRegKey[] =
  L"Software\\Microsoft\\Windows\\CurrentVersion\\Themes\\Personalize";
constexpr const wchar_t kGetPreferredBrightnessRegValue[] = L"AppsUseLightTheme";
constexpr int kTitleBarLogicalHeight = 40;
constexpr int kTitleBarLogicalControlWidth = 40;
constexpr int kTitleBarLogicalMargin = 4;
constexpr int kTitleBarControlMinimize = 1;
constexpr int kTitleBarControlMaximize = 2;
constexpr int kTitleBarControlClose = 3;

// The number of Win32Window objects that currently exist.
static int g_active_window_count = 0;

using EnableNonClientDpiScaling = BOOL __stdcall(HWND hwnd);

// Scale helper to convert logical scaler values to physical using passed in
// scale factor
int Scale(int source, double scale_factor) {
  return static_cast<int>(source * scale_factor);
}

// Dynamically loads the |EnableNonClientDpiScaling| from the User32 module.
// This API is only needed for PerMonitor V1 awareness mode.
void EnableFullDpiSupportIfAvailable(HWND hwnd) {
  HMODULE user32_module = LoadLibraryA("User32.dll");
  if (!user32_module) {
    return;
  }
  auto enable_non_client_dpi_scaling =
      reinterpret_cast<EnableNonClientDpiScaling*>(
          GetProcAddress(user32_module, "EnableNonClientDpiScaling"));
  if (enable_non_client_dpi_scaling != nullptr) {
    enable_non_client_dpi_scaling(hwnd);
  }
  FreeLibrary(user32_module);
}

}  // namespace

// Manages the Win32Window's window class registration.
class WindowClassRegistrar {
 public:
  ~WindowClassRegistrar() = default;

  // Returns the singleton registrar instance.
  static WindowClassRegistrar* GetInstance() {
    if (!instance_) {
      instance_ = new WindowClassRegistrar();
    }
    return instance_;
  }

  // Returns the name of the window class, registering the class if it hasn't
  // previously been registered.
  const wchar_t* GetWindowClass();

  // Unregisters the window class. Should only be called if there are no
  // instances of the window.
  void UnregisterWindowClass();

 private:
  WindowClassRegistrar() = default;

  static WindowClassRegistrar* instance_;

  bool class_registered_ = false;
};

WindowClassRegistrar* WindowClassRegistrar::instance_ = nullptr;

const wchar_t* WindowClassRegistrar::GetWindowClass() {
  if (!class_registered_) {
    WNDCLASS window_class{};
    window_class.hCursor = LoadCursor(nullptr, IDC_ARROW);
    window_class.lpszClassName = kWindowClassName;
    window_class.style = CS_HREDRAW | CS_VREDRAW;
    window_class.cbClsExtra = 0;
    window_class.cbWndExtra = 0;
    window_class.hInstance = GetModuleHandle(nullptr);
    window_class.hIcon =
        LoadIcon(window_class.hInstance, MAKEINTRESOURCE(IDI_APP_ICON));
    window_class.hbrBackground = 0;
    window_class.lpszMenuName = nullptr;
    window_class.lpfnWndProc = Win32Window::WndProc;
    RegisterClass(&window_class);
    class_registered_ = true;
  }
  return kWindowClassName;
}

void WindowClassRegistrar::UnregisterWindowClass() {
  UnregisterClass(kWindowClassName, nullptr);
  class_registered_ = false;
}

Win32Window::Win32Window() {
  ++g_active_window_count;
}

Win32Window::~Win32Window() {
  --g_active_window_count;
  Destroy();
}

bool Win32Window::Create(const std::wstring& title,
                         const Point& origin,
                         const Size& size) {
  Destroy();

  const wchar_t* window_class =
      WindowClassRegistrar::GetInstance()->GetWindowClass();

  const POINT target_point = {static_cast<LONG>(origin.x),
                              static_cast<LONG>(origin.y)};
  HMONITOR monitor = MonitorFromPoint(target_point, MONITOR_DEFAULTTONEAREST);
  UINT dpi = FlutterDesktopGetDpiForMonitor(monitor);
  double scale_factor = dpi / 96.0;

  HWND window = CreateWindow(
      window_class, title.c_str(),
      WS_POPUP | WS_THICKFRAME | WS_MINIMIZEBOX | WS_MAXIMIZEBOX,
      Scale(origin.x, scale_factor), Scale(origin.y, scale_factor),
      Scale(size.width, scale_factor), Scale(size.height, scale_factor),
      nullptr, nullptr, GetModuleHandle(nullptr), this);

  if (!window) {
    return false;
  }

  UpdateTheme(window);

  return OnCreate();
}

bool Win32Window::Show() {
  return ShowWindow(window_handle_, SW_SHOWNORMAL);
}

// static
LRESULT CALLBACK Win32Window::WndProc(HWND const window,
                                      UINT const message,
                                      WPARAM const wparam,
                                      LPARAM const lparam) noexcept {
  if (message == WM_NCCREATE) {
    auto window_struct = reinterpret_cast<CREATESTRUCT*>(lparam);
    SetWindowLongPtr(window, GWLP_USERDATA,
                     reinterpret_cast<LONG_PTR>(window_struct->lpCreateParams));

    auto that = static_cast<Win32Window*>(window_struct->lpCreateParams);
    EnableFullDpiSupportIfAvailable(window);
    that->window_handle_ = window;
  } else if (Win32Window* that = GetThisFromHandle(window)) {
    return that->MessageHandler(window, message, wparam, lparam);
  }

  return DefWindowProc(window, message, wparam, lparam);
}

LRESULT
Win32Window::MessageHandler(HWND hwnd,
                            UINT const message,
                            WPARAM const wparam,
                            LPARAM const lparam) noexcept {
  switch (message) {
    case WM_NCHITTEST: {
      POINT point = {GET_X_LPARAM(lparam), GET_Y_LPARAM(lparam)};
      ScreenToClient(hwnd, &point);
      RECT frame;
      GetClientRect(hwnd, &frame);
      const int border = ResizeBorderWidth();
      if (!IsZoomed(hwnd)) {
        const bool left = point.x < border;
        const bool right = point.x >= frame.right - border;
        const bool top = point.y < border;
        const bool bottom = point.y >= frame.bottom - border;
        if (top && left) return HTTOPLEFT;
        if (top && right) return HTTOPRIGHT;
        if (bottom && left) return HTBOTTOMLEFT;
        if (bottom && right) return HTBOTTOMRIGHT;
        if (left) return HTLEFT;
        if (right) return HTRIGHT;
        if (top) return HTTOP;
        if (bottom) return HTBOTTOM;
      }
      if (TitleBarControlAt(point) != 0) return HTCLIENT;
      return point.y < TitleBarHeight() ? HTCAPTION : HTCLIENT;
    }
    case WM_LBUTTONUP: {
      POINT point = {GET_X_LPARAM(lparam), GET_Y_LPARAM(lparam)};
      switch (TitleBarControlAt(point)) {
        case kTitleBarControlMinimize:
          ShowWindow(hwnd, SW_MINIMIZE);
          return 0;
        case kTitleBarControlMaximize:
          ShowWindow(hwnd, IsZoomed(hwnd) ? SW_RESTORE : SW_MAXIMIZE);
          return 0;
        case kTitleBarControlClose:
          PostMessage(hwnd, WM_CLOSE, 0, 0);
          return 0;
      }
      break;
    }
    case WM_LBUTTONDBLCLK: {
      POINT point = {GET_X_LPARAM(lparam), GET_Y_LPARAM(lparam)};
      if (point.y < TitleBarHeight() && TitleBarControlAt(point) == 0) {
        ShowWindow(hwnd, IsZoomed(hwnd) ? SW_RESTORE : SW_MAXIMIZE);
        return 0;
      }
      break;
    }
    case WM_MOUSEMOVE: {
      POINT point = {GET_X_LPARAM(lparam), GET_Y_LPARAM(lparam)};
      const int control = TitleBarControlAt(point);
      if (hovered_titlebar_control_ != control) {
        hovered_titlebar_control_ = control;
        InvalidateRect(hwnd, nullptr, FALSE);
      }
      TrackTitleBarMouse();
      break;
    }
    case WM_MOUSELEAVE:
      tracking_titlebar_mouse_ = false;
      if (hovered_titlebar_control_ != 0) {
        hovered_titlebar_control_ = 0;
        InvalidateRect(hwnd, nullptr, FALSE);
      }
      break;
    case WM_PAINT: {
      PAINTSTRUCT paint;
      HDC dc = BeginPaint(hwnd, &paint);
      PaintCustomTitleBar(dc);
      EndPaint(hwnd, &paint);
      return 0;
    }
    case WM_ERASEBKGND:
      return 1;
    case WM_DESTROY:
      window_handle_ = nullptr;
      Destroy();
      if (quit_on_close_) {
        PostQuitMessage(0);
      }
      return 0;

    case WM_DPICHANGED: {
      auto newRectSize = reinterpret_cast<RECT*>(lparam);
      LONG newWidth = newRectSize->right - newRectSize->left;
      LONG newHeight = newRectSize->bottom - newRectSize->top;

      SetWindowPos(hwnd, nullptr, newRectSize->left, newRectSize->top, newWidth,
                   newHeight, SWP_NOZORDER | SWP_NOACTIVATE);

      return 0;
    }
    case WM_SIZE: {
      RECT rect = GetClientArea();
      if (child_content_ != nullptr) {
        // Size and position the child window.
        MoveWindow(child_content_, rect.left, rect.top, rect.right - rect.left,
                   rect.bottom - rect.top, TRUE);
      }
      InvalidateRect(hwnd, nullptr, FALSE);
      return 0;
    }

    case WM_ACTIVATE:
      if (child_content_ != nullptr) {
        SetFocus(child_content_);
      }
      return 0;

    case WM_DWMCOLORIZATIONCOLORCHANGED:
      UpdateTheme(hwnd);
      return 0;
  }

  return DefWindowProc(window_handle_, message, wparam, lparam);
}

void Win32Window::Destroy() {
  OnDestroy();

  if (window_handle_) {
    DestroyWindow(window_handle_);
    window_handle_ = nullptr;
  }
  if (g_active_window_count == 0) {
    WindowClassRegistrar::GetInstance()->UnregisterWindowClass();
  }
}

Win32Window* Win32Window::GetThisFromHandle(HWND const window) noexcept {
  return reinterpret_cast<Win32Window*>(
      GetWindowLongPtr(window, GWLP_USERDATA));
}

void Win32Window::SetChildContent(HWND content) {
  child_content_ = content;
  SetParent(content, window_handle_);
  RECT frame = GetClientArea();

  MoveWindow(content, frame.left, frame.top, frame.right - frame.left,
             frame.bottom - frame.top, true);

  SetFocus(child_content_);
}

RECT Win32Window::GetClientArea() {
  RECT frame;
  GetClientRect(window_handle_, &frame);
  frame.top = std::min(frame.bottom, TitleBarHeight());
  return frame;
}

void Win32Window::SetCustomFrameColors(COLORREF canvas, COLORREF surface,
                                       COLORREF base, COLORREF container,
                                       COLORREF outline, COLORREF rim,
                                       COLORREF foreground,
                                       bool inventory_craft) {
  frame_canvas_ = canvas;
  frame_surface_ = surface;
  frame_base_ = base;
  frame_container_ = container;
  frame_outline_ = outline;
  frame_rim_ = rim;
  frame_foreground_ = foreground;
  frame_inventory_craft_ = inventory_craft;
  if (window_handle_ != nullptr) InvalidateRect(window_handle_, nullptr, FALSE);
}

int Win32Window::TitleBarHeight() const {
  return MulDiv(kTitleBarLogicalHeight, GetDpiForWindow(window_handle_), 96);
}

int Win32Window::ResizeBorderWidth() const {
  return std::max(6, MulDiv(6, GetDpiForWindow(window_handle_), 96));
}

int Win32Window::TitleBarControlAt(POINT point) const {
  if (point.y < 0 || point.y >= TitleBarHeight()) return 0;
  RECT frame;
  GetClientRect(window_handle_, &frame);
  const int width = MulDiv(kTitleBarLogicalControlWidth,
                           GetDpiForWindow(window_handle_), 96);
  const int margin = MulDiv(kTitleBarLogicalMargin,
                            GetDpiForWindow(window_handle_), 96);
  const int close_left = frame.right - margin - width;
  if (point.x >= close_left && point.x < close_left + width) {
    return kTitleBarControlClose;
  }
  if (point.x >= close_left - width && point.x < close_left) {
    return kTitleBarControlMaximize;
  }
  if (point.x >= close_left - 2 * width && point.x < close_left - width) {
    return kTitleBarControlMinimize;
  }
  return 0;
}

void Win32Window::TrackTitleBarMouse() {
  if (tracking_titlebar_mouse_) return;
  TRACKMOUSEEVENT event = {sizeof(TRACKMOUSEEVENT), TME_LEAVE, window_handle_, 0};
  if (TrackMouseEvent(&event)) tracking_titlebar_mouse_ = true;
}

void Win32Window::PaintCustomTitleBar(HDC dc) {
  RECT frame;
  GetClientRect(window_handle_, &frame);
  const int height = TitleBarHeight();
  RECT title = {0, 0, frame.right, height};
  HBRUSH canvas = CreateSolidBrush(frame_canvas_);
  FillRect(dc, &title, canvas);
  DeleteObject(canvas);

  const int width = MulDiv(kTitleBarLogicalControlWidth,
                           GetDpiForWindow(window_handle_), 96);
  const int margin = MulDiv(kTitleBarLogicalMargin,
                            GetDpiForWindow(window_handle_), 96);
  const int inset = MulDiv(5, GetDpiForWindow(window_handle_), 96);
  const int close_left = frame.right - margin - width;
  const int lefts[] = {close_left - 2 * width, close_left - width, close_left};
  const int controls[] = {kTitleBarControlMinimize, kTitleBarControlMaximize,
                          kTitleBarControlClose};
  HPEN outline = CreatePen(PS_SOLID, 1, frame_outline_);
  HPEN icon = CreatePen(PS_SOLID,
                        std::max(1, MulDiv(2, GetDpiForWindow(window_handle_), 96)),
                        frame_foreground_);
  HGDIOBJ previous_pen = SelectObject(dc, outline);
  HGDIOBJ previous_brush = SelectObject(dc, GetStockObject(NULL_BRUSH));
  for (int index = 0; index < 3; ++index) {
    const bool hovered = controls[index] == hovered_titlebar_control_;
    HBRUSH fill = CreateSolidBrush(hovered ? frame_base_ : frame_surface_);
    HGDIOBJ previous_fill = SelectObject(dc, fill);
    const int radius = MulDiv(frame_inventory_craft_ ? 2 : 10,
                              GetDpiForWindow(window_handle_), 96);
    RoundRect(dc, lefts[index] + inset / 2, inset,
              lefts[index] + width - inset / 2, height - inset,
              radius, radius);
    SelectObject(dc, previous_fill);
    DeleteObject(fill);
    SelectObject(dc, icon);
    const int center_x = lefts[index] + width / 2;
    const int center_y = height / 2;
    const int half = MulDiv(5, GetDpiForWindow(window_handle_), 96);
    if (controls[index] == kTitleBarControlMinimize) {
      MoveToEx(dc, center_x - half, center_y + half / 2, nullptr);
      LineTo(dc, center_x + half, center_y + half / 2);
    } else if (controls[index] == kTitleBarControlMaximize) {
      Rectangle(dc, center_x - half, center_y - half, center_x + half,
                center_y + half);
    } else {
      MoveToEx(dc, center_x - half, center_y - half, nullptr);
      LineTo(dc, center_x + half, center_y + half);
      MoveToEx(dc, center_x + half, center_y - half, nullptr);
      LineTo(dc, center_x - half, center_y + half);
    }
    SelectObject(dc, outline);
  }
  SelectObject(dc, previous_brush);
  SelectObject(dc, previous_pen);
  DeleteObject(icon);
  DeleteObject(outline);
}

HWND Win32Window::GetHandle() {
  return window_handle_;
}

void Win32Window::SetQuitOnClose(bool quit_on_close) {
  quit_on_close_ = quit_on_close;
}

bool Win32Window::OnCreate() {
  // No-op; provided for subclasses.
  return true;
}

void Win32Window::OnDestroy() {
  // No-op; provided for subclasses.
}

void Win32Window::UpdateTheme(HWND const window) {
  DWORD light_mode;
  DWORD light_mode_size = sizeof(light_mode);
  LSTATUS result = RegGetValue(HKEY_CURRENT_USER, kGetPreferredBrightnessRegKey,
                               kGetPreferredBrightnessRegValue,
                               RRF_RT_REG_DWORD, nullptr, &light_mode,
                               &light_mode_size);

  if (result == ERROR_SUCCESS) {
    BOOL enable_dark_mode = light_mode == 0;
    DwmSetWindowAttribute(window, DWMWA_USE_IMMERSIVE_DARK_MODE,
                          &enable_dark_mode, sizeof(enable_dark_mode));
  }
}
