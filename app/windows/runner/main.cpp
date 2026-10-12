#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>

#include <string>

#include "flutter_window.h"
#include "utils.h"
#include "win32_window.h"

namespace {

// Held for the lifetime of the process. A second launch finds it taken, so it
// surfaces the window that already exists instead of starting another copy.
constexpr const wchar_t kInstanceMutexName[] =
    L"Local\\VMwareLocalizer.SingleInstance";

bool CommandLineHasFlag(const wchar_t* flag) {
  const wchar_t* raw = ::GetCommandLineW();
  if (raw == nullptr) return false;
  return std::wstring(raw).find(flag) != std::wstring::npos;
}

void SurfaceExistingWindow() {
  HWND existing = ::FindWindowW(Win32Window::kWindowClassName, nullptr);
  if (existing == nullptr) return;

  if (::IsIconic(existing)) {
    ::ShowWindow(existing, SW_RESTORE);
  }
  ::SetForegroundWindow(existing);
}

}  // namespace

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }

  // A named mutex marks that the application is already on screen. The window
  // class alone cannot do this, because the class is unregistered when the last
  // window is destroyed, which leaves a gap during shutdown.
  //
  // Two launches are deliberately allowed to overlap:
  //   --selftest  is headless and may run alongside the interface;
  //   --elevated  is a hand-off, so it takes over the name rather than deferring
  //               to the instance that requested it and is already closing.
  // Every launch still creates the mutex, so a hand-off leaves the name held and
  // a further launch is again treated as a duplicate.
  const bool is_hand_off = CommandLineHasFlag(L"--elevated");
  HANDLE instance_mutex = nullptr;
  if (!CommandLineHasFlag(L"--selftest")) {
    instance_mutex = ::CreateMutexW(nullptr, FALSE, kInstanceMutexName);
    const bool already_running =
        instance_mutex != nullptr && ::GetLastError() == ERROR_ALREADY_EXISTS;
    if (already_running && !is_hand_off) {
      SurfaceExistingWindow();
      ::CloseHandle(instance_mutex);
      return EXIT_SUCCESS;
    }
  }

  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

  flutter::DartProject project(L"data");

  std::vector<std::string> command_line_arguments =
      GetCommandLineArguments();

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project);
  Win32Window::Point origin(10, 10);
  Win32Window::Size size(600, 452);
  if (!window.Create(L"VMware Workstation Localizer", origin, size)) {
    return EXIT_FAILURE;
  }
  window.SetQuitOnClose(true);

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  ::CoUninitialize();

  if (instance_mutex != nullptr) {
    ::ReleaseMutex(instance_mutex);
    ::CloseHandle(instance_mutex);
  }
  return EXIT_SUCCESS;
}
