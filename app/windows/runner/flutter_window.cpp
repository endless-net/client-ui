#include "flutter_window.h"

#include <windowsx.h>

#include <optional>

#include "flutter/generated_plugin_registrant.h"
#include "resource.h"
#include "dashboard_metrics.h"

namespace {

constexpr UINT kTrayMessage = WM_APP + 1;
constexpr UINT kTrayIconId = 1;
constexpr UINT kOpen = 1;
constexpr UINT kExit = 2;

}  // namespace

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
  RegisterDashboardMetrics(flutter_controller_->engine()->messenger());
  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    this->Show();
  });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  taskbar_created_message_ = RegisterWindowMessageW(L"TaskbarCreated");
  EnsureTrayIcon(GetHandle());
  return true;
}

void FlutterWindow::OnDestroy() {
  if (tray_icon_.hWnd) {
    Shell_NotifyIconW(NIM_DELETE, &tray_icon_);
    tray_icon_ = {};
  }

  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

bool FlutterWindow::EnsureTrayIcon(HWND window) {
  tray_icon_.cbSize = sizeof(tray_icon_);
  tray_icon_.hWnd = window;
  tray_icon_.uID = kTrayIconId;
  tray_icon_.uFlags = NIF_MESSAGE;
  tray_icon_.uCallbackMessage = kTrayMessage;
  if (Shell_NotifyIconW(NIM_MODIFY, &tray_icon_)) {
    return true;
  }

  tray_icon_.uFlags = NIF_MESSAGE | NIF_ICON | NIF_TIP | NIF_SHOWTIP;
  tray_icon_.hIcon =
      LoadIconW(GetModuleHandleW(nullptr), MAKEINTRESOURCEW(IDI_APP_ICON));
  wcscpy_s(tray_icon_.szTip, L"EndlessNet");
  if (!tray_icon_.hIcon || !Shell_NotifyIconW(NIM_ADD, &tray_icon_)) {
    return false;
  }
  tray_icon_.uVersion = NOTIFYICON_VERSION_4;
  if (Shell_NotifyIconW(NIM_SETVERSION, &tray_icon_)) {
    return true;
  }
  Shell_NotifyIconW(NIM_DELETE, &tray_icon_);
  return false;
}

void FlutterWindow::RestoreFromTray(HWND window) {
  ShowWindow(window, IsIconic(window) ? SW_RESTORE : SW_SHOW);
  SetForegroundWindow(window);
}

void FlutterWindow::ShowTrayMenu(HWND window, POINT position) {
  HMENU menu = CreatePopupMenu();
  if (!menu) {
    return;
  }
  AppendMenuW(menu, MF_STRING, kOpen, L"Открыть");
  AppendMenuW(menu, MF_STRING, kExit, L"Выйти из интерфейса");
  SetMenuDefaultItem(menu, kOpen, FALSE);
  SetForegroundWindow(window);
  const BOOL command = TrackPopupMenu(
      menu, TPM_RETURNCMD | TPM_NONOTIFY | TPM_RIGHTBUTTON,
      position.x, position.y, 0, window, nullptr);
  PostMessageW(window, WM_NULL, 0, 0);
  DestroyMenu(menu);

  switch (command) {
    case kOpen:
      RestoreFromTray(window);
      break;
    case kExit:
      // Flutter handles WM_CLOSE, including its asynchronous cleanup and veto.
      PostMessageW(window, WM_CLOSE, 0, 0);
      break;
    default:
      Shell_NotifyIconW(NIM_SETFOCUS, &tray_icon_);
      break;
  }
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  if (message == WM_SYSCOMMAND && (wparam & 0xfff0) == SC_CLOSE) {
    if (EnsureTrayIcon(hwnd)) {
      ShowWindow(hwnd, SW_HIDE);
    } else if (MessageBoxW(hwnd,
                           L"Системный трей недоступен. Выйти из интерфейса? "
                           L"Служба и соединение продолжат работу.",
                           L"EndlessNet", MB_YESNO | MB_ICONWARNING |
                                              MB_DEFBUTTON2) == IDYES) {
      PostMessageW(hwnd, WM_CLOSE, 0, 0);
    }
    return 0;
  }

  if (taskbar_created_message_ && message == taskbar_created_message_) {
    if (!EnsureTrayIcon(hwnd) && !IsWindowVisible(hwnd)) {
      RestoreFromTray(hwnd);
    }
    return 0;
  }

  if (message == kTrayMessage && HIWORD(lparam) == kTrayIconId) {
    switch (LOWORD(lparam)) {
      case NIN_SELECT:
      case NIN_KEYSELECT:
        RestoreFromTray(hwnd);
        break;
      case WM_CONTEXTMENU:
        ShowTrayMenu(hwnd, POINT{GET_X_LPARAM(wparam), GET_Y_LPARAM(wparam)});
        break;
    }
    return 0;
  }

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
