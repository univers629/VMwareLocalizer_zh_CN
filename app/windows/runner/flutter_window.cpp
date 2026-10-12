#include "flutter_window.h"

#include <dwmapi.h>
#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>
#include <optional>
#include <string>
#include <windows.h>

#include "flutter/generated_plugin_registrant.h"
#include "utils.h"

namespace {

constexpr COLORREF kBackgroundLight = RGB(0xF6, 0xF7, 0xFB);
constexpr COLORREF kBackgroundDark = RGB(0x14, 0x16, 0x1C);

constexpr UINT_PTR kRevealTimerId = 1;
constexpr UINT kRevealFallbackMilliseconds = 4000;

void SetTitleBarDark(HWND hwnd, bool dark) {
  const BOOL value = dark ? TRUE : FALSE;
  const DWORD kAttributeCurrent = 20;
  const DWORD kAttributeLegacy = 19;
  if (FAILED(::DwmSetWindowAttribute(hwnd, kAttributeCurrent, &value,
                                     sizeof(value)))) {
    ::DwmSetWindowAttribute(hwnd, kAttributeLegacy, &value, sizeof(value));
  }
}

bool SystemPrefersDark() {
  DWORD apps_use_light_theme = 1;
  DWORD size = sizeof(apps_use_light_theme);
  const LSTATUS status = ::RegGetValueW(
      HKEY_CURRENT_USER,
      L"Software\\Microsoft\\Windows\\CurrentVersion\\Themes\\Personalize",
      L"AppsUseLightTheme", RRF_RT_REG_DWORD, nullptr, &apps_use_light_theme,
      &size);
  if (status != ERROR_SUCCESS) {
    return false;
  }
  return apps_use_light_theme == 0;
}

bool ResolvedPrefersDark() {
  for (const std::string& argument : GetCommandLineArguments()) {
    const std::string prefix = "--theme=";
    if (argument.rfind(prefix, 0) == 0) {
      const std::string value = argument.substr(prefix.size());
      if (value == "dark") return true;
      if (value == "light") return false;
    }
  }

  char buffer[16] = {};
  const DWORD length = ::GetEnvironmentVariableA("VMWL_THEME", buffer,
                                                sizeof(buffer));
  if (length > 0 && length < sizeof(buffer)) {
    const std::string value(buffer, length);
    if (value == "dark") return true;
    if (value == "light") return false;
  }

  return SystemPrefersDark();
}

constexpr char kWindowChannel[] = "vmware_localizer/window";

}  

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  SetBackgroundColor(ResolvedPrefersDark() ? kBackgroundDark : kBackgroundLight);
  Show();

  RECT frame = GetClientArea();

  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  RegisterPlugins(flutter_controller_->engine());

  HWND view = flutter_controller_->view()->GetNativeWindow();
  SetChildContent(view);
  ShowWindow(view, SW_HIDE);

  SetTitleBarDark(GetHandle(), SystemPrefersDark());

  window_channel_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          flutter_controller_->engine()->messenger(), kWindowChannel,
          &flutter::StandardMethodCodec::GetInstance());
  window_channel_->SetMethodCallHandler(
      [this](const flutter::MethodCall<flutter::EncodableValue>& call,
             std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>
                 result) {
        if (call.method_name() == "setDark") {
          const auto* is_dark = std::get_if<bool>(call.arguments());
          if (is_dark != nullptr) {
            SetTitleBarDark(GetHandle(), *is_dark);
          }
          result->Success();
          return;
        }
        if (call.method_name() == "setTitle") {
          const auto* title = std::get_if<std::string>(call.arguments());
          if (title != nullptr) {
            const int wide_length = ::MultiByteToWideChar(
                CP_UTF8, 0, title->c_str(), static_cast<int>(title->size()),
                nullptr, 0);
            if (wide_length > 0) {
              std::wstring wide(static_cast<size_t>(wide_length), L'\0');
              ::MultiByteToWideChar(CP_UTF8, 0, title->c_str(),
                                    static_cast<int>(title->size()),
                                    wide.data(), wide_length);
              ::SetWindowTextW(GetHandle(), wide.c_str());
            }
          }
          result->Success();
          return;
        }

        if (call.method_name() == "minimize") {
          Minimize();
          result->Success();
          return;
        }
        if (call.method_name() == "toggleMaximize") {
          ToggleMaximize();
          result->Success();
          return;
        }
        if (call.method_name() == "close") {
          Close();
          result->Success();
          return;
        }
        if (call.method_name() == "isMaximized") {
          result->Success(flutter::EncodableValue(IsMaximized()));
          return;
        }
        if (call.method_name() == "startDrag") {
          StartDrag();
          result->Success();
          return;
        }
        if (call.method_name() == "setMinimumSize") {
          const auto* args =
              std::get_if<flutter::EncodableMap>(call.arguments());
          if (args != nullptr) {
            auto width = args->find(flutter::EncodableValue("width"));
            auto height = args->find(flutter::EncodableValue("height"));
            if (width != args->end() && height != args->end()) {
              const auto* w = std::get_if<int32_t>(&width->second);
              const auto* h = std::get_if<int32_t>(&height->second);
              if (w != nullptr && h != nullptr) {
                SetMinimumSize(static_cast<unsigned int>(*w),
                               static_cast<unsigned int>(*h));
              }
            }
          }
          result->Success();
          return;
        }
        result->NotImplemented();
      });

  flutter_controller_->ForceRedraw();

  flutter_controller_->engine()->SetNextFrameCallback([this]() { RevealView(); });

  ::SetTimer(GetHandle(), kRevealTimerId, kRevealFallbackMilliseconds, nullptr);

  return true;
}

void FlutterWindow::RevealView() {
  if (view_revealed_) {
    return;
  }
  view_revealed_ = true;

  ::KillTimer(GetHandle(), kRevealTimerId);

  if (flutter_controller_ && flutter_controller_->view()) {
    ShowWindow(flutter_controller_->view()->GetNativeWindow(), SW_SHOW);
  }
}

void FlutterWindow::OnDestroy() {
  ::KillTimer(GetHandle(), kRevealTimerId);
  window_channel_.reset();
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  switch (message) {
    case WM_NCCALCSIZE:
    case WM_NCHITTEST:
    case WM_NCACTIVATE:
    case WM_GETMINMAXINFO:
      return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
    default:
      break;
  }

  if (flutter_controller_) {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                      lparam);
    if (result) {
      return *result;
    }
  }

  switch (message) {
    case WM_TIMER:
      if (wparam == kRevealTimerId) {
        RevealView();
        return 0;
      }
      break;
    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
    case WM_SIZE:
      if (window_channel_ && (wparam == SIZE_MAXIMIZED || wparam == SIZE_RESTORED)) {
        window_channel_->InvokeMethod(
            "maximizedChanged",
            std::make_unique<flutter::EncodableValue>(wparam == SIZE_MAXIMIZED));
      }
      break;
    case WM_SETTINGCHANGE:
      if (wparam == 0 && lparam != 0 &&
          lstrcmpiW(reinterpret_cast<LPCWSTR>(lparam),
                    L"ImmersiveColorSet") == 0) {
        SetTitleBarDark(hwnd, SystemPrefersDark());
      }
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
