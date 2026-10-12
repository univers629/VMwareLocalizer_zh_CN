#include "win32_window.h"

#include <dwmapi.h>
#include <flutter_windows.h>

#include "resource.h"

namespace {

#ifndef DWMWA_USE_IMMERSIVE_DARK_MODE
#define DWMWA_USE_IMMERSIVE_DARK_MODE 20
#endif

#ifndef DWMWA_WINDOW_CORNER_PREFERENCE
#define DWMWA_WINDOW_CORNER_PREFERENCE 33
#endif
#ifndef DWMWCP_DEFAULT
#define DWMWCP_DEFAULT 0
#endif
#ifndef DWMWCP_DONOTROUND
#define DWMWCP_DONOTROUND 1
#endif
#ifndef DWMWCP_ROUND
#define DWMWCP_ROUND 2
#endif

constexpr int kCornerRadius = 8;

#ifndef DWMWA_BORDER_COLOR
#define DWMWA_BORDER_COLOR 34
#endif
#ifndef DWMWA_COLOR_NONE
#define DWMWA_COLOR_NONE 0xFFFFFFFE
#endif

constexpr const wchar_t kWindowClassName[] = L"FLUTTER_RUNNER_WIN32_WINDOW";

constexpr const wchar_t kGetPreferredBrightnessRegKey[] =
  L"Software\\Microsoft\\Windows\\CurrentVersion\\Themes\\Personalize";
constexpr const wchar_t kGetPreferredBrightnessRegValue[] = L"AppsUseLightTheme";

static int g_active_window_count = 0;

constexpr int kResizeBorderWidth = 6;

constexpr int kResizeCornerSize = 16;

using EnableNonClientDpiScaling = BOOL __stdcall(HWND hwnd);

int Scale(int source, double scale_factor) {
  return static_cast<int>(source * scale_factor);
}

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

int SignedLowWord(LPARAM value) {
  return static_cast<int>(static_cast<short>(LOWORD(value)));
}

int SignedHighWord(LPARAM value) {
  return static_cast<int>(static_cast<short>(HIWORD(value)));
}

}  

class WindowClassRegistrar {
 public:
  ~WindowClassRegistrar() = default;

  static WindowClassRegistrar* GetInstance() {
    if (!instance_) {
      instance_ = new WindowClassRegistrar();
    }
    return instance_;
  }

  const wchar_t* GetWindowClass();

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
      window_class, title.c_str(), WS_OVERLAPPEDWINDOW,
      Scale(origin.x, scale_factor), Scale(origin.y, scale_factor),
      Scale(size.width, scale_factor), Scale(size.height, scale_factor),
      nullptr, nullptr, GetModuleHandle(nullptr), this);

  if (!window) {
    return false;
  }

  {
    LONG_PTR style = ::GetWindowLongPtrW(window, GWL_STYLE);
    style &= ~(WS_CAPTION | WS_SYSMENU);
    ::SetWindowLongPtrW(window, GWL_STYLE, style);

    ::SetWindowPos(window, nullptr, 0, 0, 0, 0,
                   SWP_NOMOVE | SWP_NOSIZE | SWP_NOZORDER | SWP_NOACTIVATE |
                       SWP_FRAMECHANGED | SWP_DRAWFRAME);
  }

  UpdateTheme(window);
  UpdateCorners(window);

  return OnCreate();
}

bool Win32Window::Show() {
  return ShowWindow(window_handle_, SW_SHOWNORMAL);
}

void Win32Window::SetMinimumSize(unsigned int width, unsigned int height) {
  min_width_ = width;
  min_height_ = height;

  if (window_handle_ != nullptr) {
    RECT rect;
    if (GetWindowRect(window_handle_, &rect)) {
      SetWindowPos(window_handle_, nullptr, 0, 0, 0, 0,
                   SWP_NOMOVE | SWP_NOSIZE | SWP_NOZORDER | SWP_NOACTIVATE);
    }
  }
}

void Win32Window::Minimize() {
  if (window_handle_ != nullptr) {
    ShowWindow(window_handle_, SW_MINIMIZE);
  }
}

void Win32Window::ToggleMaximize() {
  if (window_handle_ == nullptr) {
    return;
  }
  ShowWindow(window_handle_, IsMaximized() ? SW_RESTORE : SW_MAXIMIZE);
}

void Win32Window::Close() {
  if (window_handle_ != nullptr) {
    PostMessage(window_handle_, WM_CLOSE, 0, 0);
  }
}

bool Win32Window::IsMaximized() const {
  return window_handle_ != nullptr && IsZoomed(window_handle_) != 0;
}

void Win32Window::StartDrag() {
  if (window_handle_ == nullptr) {
    return;
  }
  ReleaseCapture();
  SendMessage(window_handle_, WM_NCLBUTTONDOWN, HTCAPTION, 0);
}

LRESULT Win32Window::HitTestResizeBorder(HWND window, POINT screen_point) const {
  if (IsZoomed(window) != 0) {
    return HTCLIENT;
  }

  RECT rect;
  if (!GetWindowRect(window, &rect)) {
    return HTCLIENT;
  }

  const UINT dpi = GetDpiForWindow(window);
  const int border = Scale(kResizeBorderWidth, dpi / 96.0);
  const int corner = Scale(kResizeCornerSize, dpi / 96.0);

  const bool left = screen_point.x < rect.left + border;
  const bool right = screen_point.x >= rect.right - border;
  const bool top = screen_point.y < rect.top + border;
  const bool bottom = screen_point.y >= rect.bottom - border;

  const bool near_left = screen_point.x < rect.left + corner;
  const bool near_right = screen_point.x >= rect.right - corner;
  const bool near_top = screen_point.y < rect.top + corner;
  const bool near_bottom = screen_point.y >= rect.bottom - corner;

  if (near_top && near_left) return HTTOPLEFT;
  if (near_top && near_right) return HTTOPRIGHT;
  if (near_bottom && near_left) return HTBOTTOMLEFT;
  if (near_bottom && near_right) return HTBOTTOMRIGHT;
  if (left) return HTLEFT;
  if (right) return HTRIGHT;
  if (top) return HTTOP;
  if (bottom) return HTBOTTOM;

  return HTCLIENT;
}

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
    case WM_NCCALCSIZE:
      if (wparam == TRUE) {
        return 0;
      }
      break;

    case WM_NCHITTEST: {
      POINT cursor{};
      cursor.x = SignedLowWord(lparam);
      cursor.y = SignedHighWord(lparam);
      return HitTestResizeBorder(hwnd, cursor);
    }

    case WM_NCACTIVATE:
      return TRUE;

    case WM_GETMINMAXINFO: {
      auto* info = reinterpret_cast<MINMAXINFO*>(lparam);

      const UINT dpi = GetDpiForWindow(hwnd);
      const double scale = dpi / 96.0;
      if (min_width_ > 0) {
        info->ptMinTrackSize.x = Scale(static_cast<int>(min_width_), scale);
      }
      if (min_height_ > 0) {
        info->ptMinTrackSize.y = Scale(static_cast<int>(min_height_), scale);
      }

      MONITORINFO monitor_info{};
      monitor_info.cbSize = sizeof(monitor_info);
      if (GetMonitorInfo(MonitorFromWindow(hwnd, MONITOR_DEFAULTTONEAREST),
                         &monitor_info)) {
        const RECT work = monitor_info.rcWork;
        const RECT monitor = monitor_info.rcMonitor;

        info->ptMaxPosition.x = work.left - monitor.left;
        info->ptMaxPosition.y = work.top - monitor.top;
        info->ptMaxSize.x = work.right - work.left;
        info->ptMaxSize.y = work.bottom - work.top;
        info->ptMaxTrackSize.x = info->ptMaxSize.x;
        info->ptMaxTrackSize.y = info->ptMaxSize.y;
      }
      return 0;
    }

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

      UpdateCorners(hwnd);

      return 0;
    }
    case WM_SIZE: {
      RECT rect = GetClientArea();
      if (child_content_ != nullptr) {
        MoveWindow(child_content_, rect.left, rect.top, rect.right - rect.left,
                   rect.bottom - rect.top, TRUE);
      }
      UpdateCorners(hwnd);
      return 0;
    }

    case WM_ACTIVATE:
      if (child_content_ != nullptr) {
        SetFocus(child_content_);
      }
      return 0;

    case WM_ERASEBKGND: {
      HDC dc = reinterpret_cast<HDC>(wparam);
      RECT rect;
      if (dc != nullptr && GetClientRect(hwnd, &rect)) {
        FillRect(dc, &rect, background_brush_);
        return 1;
      }
      break;
    }

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
  if (background_brush_ != nullptr) {
    DeleteObject(background_brush_);
    background_brush_ = nullptr;
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
  return frame;
}

HWND Win32Window::GetHandle() {
  return window_handle_;
}

void Win32Window::SetQuitOnClose(bool quit_on_close) {
  quit_on_close_ = quit_on_close;
}

void Win32Window::SetBackgroundColor(COLORREF color) {
  if (background_brush_ != nullptr) {
    DeleteObject(background_brush_);
  }
  background_brush_ = CreateSolidBrush(color);

  if (window_handle_ != nullptr) {
    RedrawWindow(window_handle_, nullptr, nullptr,
                 RDW_INVALIDATE | RDW_ERASE | RDW_UPDATENOW);
  }
}

bool Win32Window::OnCreate() {
  return true;
}

void Win32Window::OnDestroy() {
}
void Win32Window::UpdateTheme(HWND const window) {
  DWORD light_mode;
  DWORD light_mode_size = sizeof(light_mode);
  LSTATUS result = RegGetValue(HKEY_CURRENT_USER, kGetPreferredBrightnessRegKey,
                               kGetPreferredBrightnessRegValue,
                               RRF_RT_REG_DWORD, nullptr, &light_mode,
                               &light_mode_size);

  const BOOL enable_dark_mode =
      (result == ERROR_SUCCESS && light_mode == 0) ? TRUE : FALSE;
  DwmSetWindowAttribute(window, DWMWA_USE_IMMERSIVE_DARK_MODE,
                        &enable_dark_mode, sizeof(enable_dark_mode));

  DWORD border_color = DWMWA_COLOR_NONE;
  DwmSetWindowAttribute(window, DWMWA_BORDER_COLOR, &border_color,
                        sizeof(border_color));
}

void Win32Window::UpdateCorners(HWND window) {
  if (window == nullptr) {
    return;
  }

  const bool maximized = IsZoomed(window) != 0;

  const DWORD preference = maximized ? DWMWCP_DONOTROUND : DWMWCP_ROUND;
  const HRESULT hr =
      DwmSetWindowAttribute(window, DWMWA_WINDOW_CORNER_PREFERENCE, &preference,
                            sizeof(preference));

  if (SUCCEEDED(hr)) {
    SetWindowRgn(window, nullptr, TRUE);
    return;
  }

  if (maximized) {
    SetWindowRgn(window, nullptr, TRUE);
    return;
  }

  RECT rect;
  if (!GetWindowRect(window, &rect)) {
    return;
  }

  const int width = rect.right - rect.left;
  const int height = rect.bottom - rect.top;
  if (width <= 0 || height <= 0) {
    return;
  }

  const int ellipse = Scale(kCornerRadius, GetDpiForWindow(window) / 96.0) * 2;
  HRGN region = CreateRoundRectRgn(0, 0, width + 1, height + 1, ellipse, ellipse);
  if (region == nullptr) {
    return;
  }

  if (SetWindowRgn(window, region, TRUE) == 0) {
    DeleteObject(region);
  }
}
