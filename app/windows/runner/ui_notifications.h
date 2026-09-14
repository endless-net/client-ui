#ifndef ENDLESSNET_UI_NOTIFICATIONS_H_
#define ENDLESSNET_UI_NOTIFICATIONS_H_

#include <roapi.h>
#include <winrt/Windows.UI.Notifications.h>
#include <flutter/encodable_value.h>
#include <flutter/method_call.h>
#include <flutter/method_result.h>
#include <functional>

using WindowsNotificationSetting =
    winrt::Windows::UI::Notifications::NotificationSetting;

inline WindowsNotificationSetting ReadWindowsNotificationSetting() {
  // Balanced even when COM was already initialized by the Flutter runner.
  winrt::check_hresult(RoInitialize(RO_INIT_SINGLETHREADED));
  struct Apartment { ~Apartment() { RoUninitialize(); } } apartment;
  const auto notifier = winrt::Windows::UI::Notifications::ToastNotificationManager::
      CreateToastNotifier(L"EndlessNet.Client");
  return notifier.Setting();
}

inline void HandleUiNotificationPermission(
    const flutter::MethodCall<flutter::EncodableValue>& call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result,
    const std::function<WindowsNotificationSetting()>& read = ReadWindowsNotificationSetting) {
  // Delivery is a separate host capability. Do not acknowledge a toast that
  // has not been submitted, or substitute permission success for delivery.
  if (call.method_name() != "requestPermission") {
    result->NotImplemented();
    return;
  }
  if (call.arguments() &&
      !std::holds_alternative<std::monostate>(*call.arguments())) {
    result->Error("invalid_arguments", "Notification permission takes no arguments");
    return;
  }
  const char* response = "unavailable";
  try {
    // Windows exposes current policy, not an application-controlled grant dialog.
    // Never write notification settings or report that permission was changed.
    switch (read()) {
      case WindowsNotificationSetting::Enabled:
        response = "granted";
        break;
      case WindowsNotificationSetting::DisabledForApplication:
      case WindowsNotificationSetting::DisabledForUser:
        response = "denied";
        break;
      case WindowsNotificationSetting::DisabledByGroupPolicy:
        response = "managedDenied";
        break;
      case WindowsNotificationSetting::DisabledByManifest:
        response = "unsupported";
        break;
      default:
        break;
    }
  } catch (...) {
    // HRESULT, installation paths and OS diagnostics stay out of presentation.
  }
  result->Success(flutter::EncodableValue(response));
}

#endif
