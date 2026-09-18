#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>
#include <shlobj.h>
#include <shobjidl.h>

#include <fstream>
#include <string>

#include "flutter_window.h"
#include "utils.h"

// Reads the renderer chosen in Personalization, saved by the app as a
// one-word file beside its database in the path_provider support directory.
// Without a saved choice Windows keeps Flutter's default, Impeller.
static flutter::ImpellerSwitch ChosenImpellerSwitch() {
  PWSTR roaming = nullptr;
  if (FAILED(::SHGetKnownFolderPath(FOLDERID_RoamingAppData, 0, nullptr,
                                    &roaming))) {
    return flutter::ImpellerSwitch::Default;
  }
  std::wstring path(roaming);
  ::CoTaskMemFree(roaming);
  path += L"\\Inventorinator contributors\\Inventorinator\\renderer";
  std::ifstream file(path);
  std::string choice;
  file >> choice;
  if (choice == "skia") return flutter::ImpellerSwitch::Disabled;
  if (choice == "impeller") return flutter::ImpellerSwitch::Enabled;
  return flutter::ImpellerSwitch::Default;
}

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  // Attach to console when present (e.g., 'flutter run') or create a
  // new console when running with a debugger.
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }

  // Initialize COM, so that it is available for use in the library and/or
  // plugins.
  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);
  ::SetCurrentProcessExplicitAppUserModelID(
      L"EverlastingMedia.Inventorinator");

  flutter::DartProject project(L"data");
  project.set_impeller_switch(ChosenImpellerSwitch());

  std::vector<std::string> command_line_arguments =
      GetCommandLineArguments();

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project);
  Win32Window::Point origin(10, 10);
  Win32Window::Size size(1280, 720);
  if (!window.Create(L"Inventorinator", origin, size)) {
    return EXIT_FAILURE;
  }
  window.SetQuitOnClose(true);

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  ::CoUninitialize();
  return EXIT_SUCCESS;
}
