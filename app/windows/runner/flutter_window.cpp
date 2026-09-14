#include "flutter_window.h"

#include <optional>
#include <shobjidl.h>
#include <wrl/client.h>
#include <flutter/standard_method_codec.h>

#include "utils.h"
#include "ui_autostart.h"
#include "ui_notifications.h"
#include "ui_notification_activation.h"

#include "flutter/generated_plugin_registrant.h"

namespace {
// UI-owned chooser; it neither reads runtime state nor writes bundle contents.
void ChooseDiagnosticsDirectory(
    HWND owner,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  Microsoft::WRL::ComPtr<IFileOpenDialog> dialog;
  HRESULT hr = CoCreateInstance(CLSID_FileOpenDialog, nullptr,
                               CLSCTX_INPROC_SERVER, IID_PPV_ARGS(&dialog));
  FILEOPENDIALOGOPTIONS options = 0;
  if (SUCCEEDED(hr)) hr = dialog->GetOptions(&options);
  if (SUCCEEDED(hr)) {
    hr = dialog->SetOptions(options | FOS_PICKFOLDERS | FOS_FORCEFILESYSTEM |
                           FOS_PATHMUSTEXIST | FOS_NOCHANGEDIR | FOS_DONTADDTORECENT);
  }
  if (SUCCEEDED(hr)) hr = dialog->Show(owner);
  if (hr == HRESULT_FROM_WIN32(ERROR_CANCELLED)) {
    result->Success();
    return;
  }
  Microsoft::WRL::ComPtr<IShellItem> selected;
  if (SUCCEEDED(hr)) hr = dialog->GetResult(&selected);
  PWSTR path = nullptr;
  if (SUCCEEDED(hr)) hr = selected->GetDisplayName(SIGDN_FILESYSPATH, &path);
  const std::string encoded = SUCCEEDED(hr) && path ? Utf8FromUtf16(path) : "";
  CoTaskMemFree(path);
  if (FAILED(hr) || encoded.empty()) {
    result->Error("destination_unavailable", "Cannot select diagnostics destination");
    return;
  }
  result->Success(flutter::EncodableValue(encoded));
}
}  // namespace

FlutterWindow::FlutterWindow(const flutter::DartProject& project,
                             bool show_on_first_frame)
    : project_(project), show_on_first_frame_(show_on_first_frame) {}

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
  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  tray_host_.Initialize(RegisterWindowMessageW(L"TaskbarCreated"));
  tray_host_channel_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          flutter_controller_->engine()->messenger(), "endlessnet/ui-tray-host",
          &flutter::StandardMethodCodec::GetInstance());
  tray_host_channel_->SetMethodCallHandler([this](const auto& call, auto result) {
    if (call.method_name() != "isAvailable") {
      result->NotImplemented();
      return;
    }
    if (call.arguments() &&
        !std::holds_alternative<std::monostate>(*call.arguments())) {
      result->Error("invalid_arguments", "Tray host query takes no arguments");
      return;
    }
    result->Success(flutter::EncodableValue(
        tray_host_.Available(GetShellWindow() != nullptr)));
  });

  autostart_channel_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          flutter_controller_->engine()->messenger(), "endlessnet/ui-autostart",
          &flutter::StandardMethodCodec::GetInstance());
  autostart_channel_->SetMethodCallHandler(HandleUiAutostart);

  notification_channel_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          flutter_controller_->engine()->messenger(), "endlessnet/ui-notifications",
          &flutter::StandardMethodCodec::GetInstance());
  notification_channel_->SetMethodCallHandler([this](const auto& call, auto result) {
    if (call.method_name() == "initialize" || call.method_name() == "shutdown") {
      if (call.arguments() &&
          !std::holds_alternative<std::monostate>(*call.arguments())) {
        result->Error("invalid_arguments", "Notification host control takes no arguments");
        return;
      }
      if (call.method_name() == "shutdown") {
        notification_activation_.reset();
        result->Success(flutter::EncodableValue(true));
        return;
      }
      if (!show_on_first_frame_) {
        result->Success(flutter::EncodableValue(false));
        return;
      }
      // Only the Dart entrypoint holding the single-instance lock calls this.
      // Window construction itself must never compete with the primary factory.
      if (!notification_activation_ || !notification_activation_->ready()) {
        try {
          notification_activation_ = std::make_unique<UiNotificationActivationHost>(GetHandle());
        } catch (...) {
          result->Success(flutter::EncodableValue(false));
          return;
        }
      }
      result->Success(flutter::EncodableValue(notification_activation_->ready()));
    } else if (call.method_name() == "deliver") {
      HandleUiNotificationDelivery(call, std::move(result),
          notification_activation_ && notification_activation_->ready());
    } else {
      HandleUiNotificationPermission(call, std::move(result));
    }
  });

  destination_channel_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          flutter_controller_->engine()->messenger(),
          "endlessnet/ui-diagnostics-destination",
          &flutter::StandardMethodCodec::GetInstance());
  destination_channel_->SetMethodCallHandler(
      [this](const auto& call, auto result) {
        if (call.method_name() != "chooseDirectory") {
          result->NotImplemented();
          return;
        }
        if (destination_picker_open_) {
          result->Error("destination_busy", "A destination chooser is already open");
          return;
        }
        destination_picker_open_ = true;
        ChooseDiagnosticsDirectory(GetHandle(), std::move(result));
        destination_picker_open_ = false;
      });

  if (show_on_first_frame_) {
    flutter_controller_->engine()->SetNextFrameCallback([&]() {
      this->Show();
    });
  }

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::OnDestroy() {
  tray_host_channel_.reset();
  notification_activation_.reset();
  notification_channel_.reset();
  autostart_channel_.reset();
  destination_channel_.reset();
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  // Observe the broadcast even if a plugin consumes it below.
  tray_host_.OnMessage(message);
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
    case kUiNotificationActivated:
      if (IsIconic(hwnd)) ShowWindow(hwnd, SW_RESTORE);
      else ShowWindow(hwnd, SW_SHOW);
      SetForegroundWindow(hwnd);
      return 0;
    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
