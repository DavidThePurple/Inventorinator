#include "flutter_window.h"

#include <optional>
#include <filesystem>
#include <mmsystem.h>

#include <string>

#include "flutter/generated_plugin_registrant.h"

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  RECT frame = GetClientArea();

  // The size here must match the window dimensions to avoid unnecessary surface
  // creation / destruction in the startup path.
  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  // Ensure that basic setup of the controller was successful.
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  RegisterPlugins(flutter_controller_->engine());
  xreal_r1_camera_ = std::make_unique<XrealR1Camera>();
  xreal_r1_channel_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          flutter_controller_->engine()->messenger(), "inventorinator/xreal_r1",
          &flutter::StandardMethodCodec::GetInstance());
  xreal_r1_channel_->SetMethodCallHandler(
      [this](const auto& call, auto result) {
        if (call.method_name() == "start") {
          if (xreal_r1_camera_->Start()) {
            result->Success();
          } else {
            result->Error("xreal_r1_unavailable", xreal_r1_camera_->LastError());
          }
        } else if (call.method_name() == "stop") {
          xreal_r1_camera_->Stop();
          result->Success();
        } else if (call.method_name() == "status") {
          flutter::EncodableMap status;
          status[flutter::EncodableValue("available")] = xreal_r1_camera_->IsAvailable();
          status[flutter::EncodableValue("streaming")] = xreal_r1_camera_->IsStreaming();
          status[flutter::EncodableValue("packets")] =
              static_cast<int64_t>(xreal_r1_camera_->PacketCount());
          status[flutter::EncodableValue("error")] = xreal_r1_camera_->LastError();
          result->Success(status);
        } else if (call.method_name() == "frame") {
          const auto frame = xreal_r1_camera_->LatestFrame();
          result->Success(flutter::EncodableValue(frame));
        } else {
          result->NotImplemented();
        }
      });
  audio_channel_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          flutter_controller_->engine()->messenger(), "inventorinator/audio",
          &flutter::StandardMethodCodec::GetInstance());
  audio_channel_->SetMethodCallHandler(
      [](const auto& call, auto result) {
        std::string file_name;
        if (call.method_name() == "playSyncChime") {
          file_name = "transhuman_sync.wav";
        } else if (call.method_name() == "playDryingCompleteChime") {
          file_name = "drying_complete.wav";
        } else if (call.method_name() == "playMoistureAlertChime") {
          file_name = "moisture_alert.wav";
        } else {
          result->NotImplemented();
          return;
        }
        wchar_t executable_path[MAX_PATH];
        const auto length = GetModuleFileNameW(nullptr, executable_path, MAX_PATH);
        if (length == 0 || length == MAX_PATH) {
          result->Error("audio_path", "Could not locate the executable.");
          return;
        }
        const auto sound_path =
            std::filesystem::path(executable_path).parent_path() / "data" /
            "flutter_assets" / "assets" / "audio" / file_name;
        if (!PlaySoundW(sound_path.c_str(), nullptr,
                        SND_FILENAME | SND_ASYNC | SND_NODEFAULT)) {
          result->Error("audio_playback", "Windows could not play the chime.");
          return;
        }
        result->Success();
      });
  native_theme_channel_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          flutter_controller_->engine()->messenger(), "inventorinator/window_theme",
          &flutter::StandardMethodCodec::GetInstance());
  native_theme_channel_->SetMethodCallHandler(
      [this](const auto& call, auto result) {
        if (call.method_name() != "setTheme" || call.arguments() == nullptr) {
          result->NotImplemented();
          return;
        }
        const auto* arguments = std::get_if<flutter::EncodableMap>(call.arguments());
        if (arguments == nullptr) {
          result->Error("window_theme", "Expected theme colors.");
          return;
        }
        const auto color = [&arguments](const char* key, COLORREF fallback) {
          const auto entry = arguments->find(flutter::EncodableValue(key));
          if (entry == arguments->end()) return fallback;
          const auto* value = std::get_if<std::string>(&entry->second);
          if (value == nullptr || value->size() != 7 || (*value)[0] != '#') {
            return fallback;
          }
          try {
            const unsigned long rgb = std::stoul(value->substr(1), nullptr, 16);
            return RGB((rgb >> 16) & 0xff, (rgb >> 8) & 0xff, rgb & 0xff);
          } catch (...) {
            return fallback;
          }
        };
        bool inventory_craft = false;
        const auto design = arguments->find(flutter::EncodableValue("design"));
        if (design != arguments->end()) {
          if (const auto* value = std::get_if<std::string>(&design->second)) {
            inventory_craft = *value == "inventoryCraft";
          }
        }
        SetCustomFrameColors(
            color("canvas", RGB(18, 13, 28)), color("surface", RGB(27, 23, 38)),
            color("base", RGB(117, 93, 165)), color("container", RGB(73, 57, 112)),
            color("outlineVariant", RGB(70, 57, 85)),
            color("rim", RGB(130, 100, 180)),
            color("foreground", RGB(238, 234, 255)), inventory_craft);
        result->Success();
      });
  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    this->Show();
  });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::OnDestroy() {
  if (flutter_controller_) {
    audio_channel_.reset();
    native_theme_channel_.reset();
    xreal_r1_channel_.reset();
    xreal_r1_camera_.reset();
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  const bool custom_frame_message =
      message == WM_NCHITTEST || message == WM_LBUTTONUP ||
      message == WM_LBUTTONDBLCLK || message == WM_MOUSEMOVE ||
      message == WM_MOUSELEAVE || message == WM_PAINT ||
      message == WM_ERASEBKGND;
  // Give Flutter, including plugins, an opportunity to handle window messages.
  if (flutter_controller_ && !custom_frame_message) {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                      lparam);
    if (result) {
      return *result;
    }
  }

  switch (message) {
    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
