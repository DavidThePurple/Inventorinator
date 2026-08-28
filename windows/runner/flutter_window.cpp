#include "flutter_window.h"

#include <optional>
#include <filesystem>
#include <mmsystem.h>

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
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  // Give Flutter, including plugins, an opportunity to handle window messages.
  if (flutter_controller_) {
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
