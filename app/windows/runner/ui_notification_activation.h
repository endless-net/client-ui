#ifndef ENDLESSNET_UI_NOTIFICATION_ACTIVATION_H_
#define ENDLESSNET_UI_NOTIFICATION_ACTIVATION_H_

#include <windows.h>
#include <notificationactivationcallback.h>
#include <wrl/implements.h>
#include <functional>
#include <memory>
#include <mutex>
#include <string>

inline constexpr UINT kUiNotificationActivated = WM_APP + 42;

// No toast payload becomes an executable, URL, profile selector or RPC.
struct UiNotificationActivationState {
  std::mutex mutex;
  std::function<bool()> show;
  HRESULT Activate(LPCWSTR app, LPCWSTR arguments, ULONG inputs) noexcept {
    if (!app || wcscmp(app, L"EndlessNet.Client") != 0 ||
        !arguments || wcscmp(arguments, L"open-ui") != 0 || inputs != 0) {
      return E_INVALIDARG;
    }
    try {
      std::lock_guard<std::mutex> lock(mutex);
      return show && show() ? S_OK : HRESULT_FROM_WIN32(ERROR_NOT_READY);
    } catch (...) {
      return E_FAIL;
    }
  }
  void Close() {
    std::lock_guard<std::mutex> lock(mutex);
    show = nullptr;
  }
};

class __declspec(uuid("9627bf5f-5cfd-4c27-9822-3f86b95e4884"))
UiNotificationActivator final : public Microsoft::WRL::RuntimeClass<
    Microsoft::WRL::RuntimeClassFlags<Microsoft::WRL::ClassicCom>,
    INotificationActivationCallback> {
 public:
  explicit UiNotificationActivator(std::shared_ptr<UiNotificationActivationState> state)
      : state_(std::move(state)) {}
  HRESULT STDMETHODCALLTYPE Activate(LPCWSTR app, LPCWSTR arguments,
      const NOTIFICATION_USER_INPUT_DATA*, ULONG count) noexcept override {
    return state_->Activate(app, arguments, count);
  }
 private:
  std::shared_ptr<UiNotificationActivationState> state_;
};

class UiNotificationFactory final : public Microsoft::WRL::RuntimeClass<
    Microsoft::WRL::RuntimeClassFlags<Microsoft::WRL::ClassicCom>, IClassFactory> {
 public:
  explicit UiNotificationFactory(std::shared_ptr<UiNotificationActivationState> state)
      : state_(std::move(state)) {}
  HRESULT STDMETHODCALLTYPE CreateInstance(IUnknown* outer, REFIID iid, void** object) noexcept override {
    if (!object) return E_POINTER;
    *object = nullptr;
    if (outer) return CLASS_E_NOAGGREGATION;
    const auto activator = Microsoft::WRL::Make<UiNotificationActivator>(state_);
    return activator ? activator->QueryInterface(iid, object) : E_OUTOFMEMORY;
  }
  HRESULT STDMETHODCALLTYPE LockServer(BOOL) noexcept override { return S_OK; }
 private:
  std::shared_ptr<UiNotificationActivationState> state_;
};

class UiNotificationActivationHost {
 public:
  explicit UiNotificationActivationHost(HWND window)
      : state_(std::make_shared<UiNotificationActivationState>()) {
    state_->show = [window]() {
      return PostMessageW(window, kUiNotificationActivated, 0, 0) != FALSE;
    };
    const auto factory = Microsoft::WRL::Make<UiNotificationFactory>(state_);
    if (factory) {
      const auto result = CoRegisterClassObject(__uuidof(UiNotificationActivator),
          factory.Get(), CLSCTX_LOCAL_SERVER, REGCLS_MULTIPLEUSE, &cookie_);
      if (FAILED(result)) cookie_ = 0;
    }
  }
  ~UiNotificationActivationHost() {
    state_->Close();
    if (cookie_) CoRevokeClassObject(cookie_);
  }
  bool ready() const { return cookie_ != 0; }
  UiNotificationActivationHost(const UiNotificationActivationHost&) = delete;
  UiNotificationActivationHost& operator=(const UiNotificationActivationHost&) = delete;
 private:
  std::shared_ptr<UiNotificationActivationState> state_;
  DWORD cookie_ = 0;
};

#endif
