#ifndef ENDLESSNET_UI_NOTIFICATIONS_H_
#define ENDLESSNET_UI_NOTIFICATIONS_H_

#include <roapi.h>
#include <winrt/Windows.UI.Notifications.h>
#include <winrt/Windows.Data.Xml.Dom.h>
#include <flutter/encodable_value.h>
#include <flutter/method_call.h>
#include <flutter/method_result.h>
#include <functional>

using WindowsNotificationSetting =
    winrt::Windows::UI::Notifications::NotificationSetting;

inline winrt::Windows::Data::Xml::Dom::XmlDocument BuildWindowsToastXml(
    const std::string& title, const std::string& body) {
  winrt::Windows::Data::Xml::Dom::XmlDocument document;
  document.LoadXml(L"<toast launch=\"open-ui\"><visual><binding template=\"ToastGeneric\">"
      L"<text/><text/></binding></visual></toast>");
  const auto texts = document.GetElementsByTagName(L"text");
  texts.Item(0).AppendChild(document.CreateTextNode(winrt::to_hstring(title)));
  texts.Item(1).AppendChild(document.CreateTextNode(winrt::to_hstring(body)));
  return document;
}

inline std::string DeliverWindowsToast(const std::string& title, const std::string& body) {
  winrt::check_hresult(RoInitialize(RO_INIT_SINGLETHREADED));
  struct Apartment { ~Apartment() { RoUninitialize(); } } apartment;
  using namespace winrt::Windows::UI::Notifications;
  const auto notifier = ToastNotificationManager::CreateToastNotifier(L"EndlessNet.Client");
  switch (notifier.Setting()) {
    case NotificationSetting::DisabledForApplication:
    case NotificationSetting::DisabledForUser:
    case NotificationSetting::DisabledByGroupPolicy:
      return "permissionDenied";
    case NotificationSetting::DisabledByManifest:
      return "unsupported";
    case NotificationSetting::Enabled:
      break;
    default:
      return "unavailable";
  }
  notifier.Show(ToastNotification(BuildWindowsToastXml(title, body)));
  // Show acceptance is not proof of a visible banner or user interaction.
  return "delivered";
}

inline void HandleUiNotificationDelivery(
    const flutter::MethodCall<flutter::EncodableValue>& call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result,
    bool activation_ready,
    const std::function<std::string(const std::string&, const std::string&)>& deliver = DeliverWindowsToast) {
  using Value = flutter::EncodableValue;
  const auto map = call.arguments() ? std::get_if<flutter::EncodableMap>(call.arguments()) : nullptr;
  const std::string* title = nullptr;
  const std::string* body = nullptr;
  if (map && map->size() == 2) {
    const auto t = map->find(Value("title"));
    const auto b = map->find(Value("body"));
    if (t != map->end()) title = std::get_if<std::string>(&t->second);
    if (b != map->end()) body = std::get_if<std::string>(&b->second);
  }
  if (call.method_name() != "deliver" || !title || *title != "EndlessNet" ||
      !body || body->empty() || body->size() > 2048 || body->find('\0') != std::string::npos) {
    result->Success(Value("failed"));
    return;
  }
  if (!activation_ready) {
    result->Success(Value("unavailable"));
    return;
  }
  try {
    // Validate UTF-8 before handing native text to the platform boundary.
    if (MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, body->data(),
                           static_cast<int>(body->size()), nullptr, 0) == 0) {
      result->Success(Value("failed"));
      return;
    }
    result->Success(Value(deliver(*title, *body)));
  } catch (...) {
    result->Success(Value("unavailable"));
  }
}

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
