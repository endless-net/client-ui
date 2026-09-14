#include "ui_notifications.h"
#include "ui_notification_activation.h"
#include <iostream>
#include <stdexcept>

using Value = flutter::EncodableValue;
void Check(bool value) { if (!value) throw std::runtime_error("assertion failed"); }
struct Output { std::string value; int completions = 0; };
class Result : public flutter::MethodResult<Value> {
 public:
  explicit Result(Output& output) : output_(output) {}
 protected:
  void SuccessInternal(const Value* value) override {
    output_.value = std::get<std::string>(*value); ++output_.completions;
  }
  void ErrorInternal(const std::string& code, const std::string&, const Value*) override {
    output_.value = code; ++output_.completions;
  }
  void NotImplementedInternal() override {
    output_.value = "notImplemented"; ++output_.completions;
  }
 private:
  Output& output_;
};
int main() {
  int reads = 0;
  WindowsNotificationSetting setting = WindowsNotificationSetting::Enabled;
  bool fail = false;
  const auto read = [&]() {
    ++reads;
    if (fail) throw std::runtime_error("private OS details");
    return setting;
  };
  const auto invoke = [&](const std::string& method, Value argument = Value()) {
    Output output;
    flutter::MethodCall<Value> call(method, std::make_unique<Value>(argument));
    HandleUiNotificationPermission(call, std::make_unique<Result>(output), read);
    Check(output.completions == 1);
    return output.value;
  };
  Check(invoke("requestPermission") == "granted");
  for (const auto denied : {WindowsNotificationSetting::DisabledForApplication,
      WindowsNotificationSetting::DisabledForUser}) {
    setting = denied;
    Check(invoke("requestPermission") == "denied");
  }
  setting = WindowsNotificationSetting::DisabledByGroupPolicy;
  Check(invoke("requestPermission") == "managedDenied");
  setting = WindowsNotificationSetting::DisabledByManifest;
  Check(invoke("requestPermission") == "unsupported");
  setting = static_cast<WindowsNotificationSetting>(999);
  Check(invoke("requestPermission") == "unavailable");
  fail = true;
  Check(invoke("requestPermission") == "unavailable");
  Check(reads == 7);
  Check(invoke("requestPermission", Value(true)) == "invalid_arguments");
  Check(invoke("requestPermission", Value("EndlessNet.Other")) == "invalid_arguments");
  Check(invoke("deliver") == "notImplemented");
  Check(invoke("unexpected") == "notImplemented");
  Check(reads == 7);
  std::cout << "Windows notification permission unit checks passed\n";

  int submissions = 0;
  bool delivery_failure = false;
  const auto deliver = [&](const std::string& title, const std::string& body) {
    Check(title == "EndlessNet" && !body.empty());
    ++submissions;
    if (delivery_failure) throw std::runtime_error("private service error");
    return std::string("delivered");
  };
  const auto submit = [&](Value argument, bool ready = true) {
    Output output;
    flutter::MethodCall<Value> call("deliver", std::make_unique<Value>(argument));
    HandleUiNotificationDelivery(call, std::make_unique<Result>(output), ready, deliver);
    Check(output.completions == 1);
    return output.value;
  };
  const auto payload = [](std::string body) {
    return Value(flutter::EncodableMap{{Value("title"), Value("EndlessNet")},
                                     {Value("body"), Value(body)}});
  };
  Check(submit(payload("Review EndlessNet")) == "delivered");
  Check(submit(payload("Review EndlessNet"), false) == "unavailable");
  for (const auto& bad : {std::string(), std::string(2049, 'a'),
      std::string("a\0b", 3), std::string("\xff", 1)}) {
    Check(submit(payload(bad)) == "failed");
  }
  Check(submit(Value(true)) == "failed");
  auto extra = std::get<flutter::EncodableMap>(payload("text"));
  extra[Value("url")] = Value("https://example.invalid");
  Check(submit(Value(extra)) == "failed");
  extra.erase(Value("url")); extra[Value("title")] = Value("Other");
  Check(submit(Value(extra)) == "failed");
  Check(submissions == 1);
  delivery_failure = true;
  Check(submit(payload("text")) == "unavailable");

  // DOM construction is local: it does not submit to the notification service.
  winrt::check_hresult(RoInitialize(RO_INIT_SINGLETHREADED));
  {
    const auto xml = BuildWindowsToastXml("EndlessNet", "<text>& \"private\"");
    Check(xml.GetElementsByTagName(L"text").Length() == 2);
    Check(xml.GetElementsByTagName(L"text").Item(1).InnerText() == L"<text>& \"private\"");
    Check(xml.DocumentElement().GetAttribute(L"launch") == L"open-ui");
  }
  RoUninitialize();

  auto state = std::make_shared<UiNotificationActivationState>();
  int shows = 0;
  state->show = [&]() { ++shows; return true; };
  const auto factory = Microsoft::WRL::Make<UiNotificationFactory>(state);
  Microsoft::WRL::ComPtr<INotificationActivationCallback> callback;
  Check(SUCCEEDED(factory->CreateInstance(nullptr, IID_PPV_ARGS(&callback))));
  Check(callback->Activate(L"EndlessNet.Client", L"open-ui", nullptr, 0) == S_OK);
  Check(callback->Activate(L"Other", L"open-ui", nullptr, 0) == E_INVALIDARG);
  Check(callback->Activate(L"EndlessNet.Client", L"https://example.invalid", nullptr, 0) == E_INVALIDARG);
  Check(callback->Activate(L"EndlessNet.Client", L"open-ui", nullptr, 1) == E_INVALIDARG);
  Check(callback->Activate(nullptr, nullptr, nullptr, 0) == E_INVALIDARG);
  Check(shows == 1);
  state->Close();
  Check(FAILED(callback->Activate(L"EndlessNet.Client", L"open-ui", nullptr, 0)));
  Check(shows == 1);
  Check(factory->CreateInstance(nullptr, __uuidof(IUnknown), nullptr) == E_POINTER);
  std::cout << "Windows delivery boundary, XML and activation unit checks passed\n";
}
