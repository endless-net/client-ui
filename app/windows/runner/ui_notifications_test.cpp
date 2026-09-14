#include "ui_notifications.h"
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
}
