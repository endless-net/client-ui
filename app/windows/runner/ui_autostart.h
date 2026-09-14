#ifndef ENDLESSNET_UI_AUTOSTART_H_
#define ENDLESSNET_UI_AUTOSTART_H_

#include <windows.h>
#include <flutter/method_call.h>
#include <flutter/method_result.h>
#include <flutter/encodable_value.h>
#include <string>
#include <vector>

// UI-owned HKCU entry only. StartupApproved is OS-owned and never inspected or
// changed: registration is not evidence that Windows permits startup.
inline void HandleUiAutostart(
    const flutter::MethodCall<flutter::EncodableValue>& call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  const bool write = call.method_name() == "setEnabled";
  if (!write && call.method_name() != "read") {
    result->NotImplemented();
    return;
  }
  const bool* enabled = call.arguments()
      ? std::get_if<bool>(call.arguments()) : nullptr;
  if ((write && !enabled) || (!write && call.arguments() &&
      !std::holds_alternative<std::monostate>(*call.arguments()))) {
    result->Error("invalid_arguments", "Invalid autostart request");
    return;
  }
  auto fail = [&]() {
    result->Error("autostart_unavailable", "Cannot read or change UI autostart");
  };
  std::vector<wchar_t> path(32768);
  const DWORD length = GetModuleFileNameW(nullptr, path.data(),
                                            static_cast<DWORD>(path.size()));
  if (!length || length >= path.size()) { fail(); return; }
  const std::wstring command = L"\"" + std::wstring(path.data(), length) + L"\"";
  // The Windows Run contract limits the command line to 260 characters.
  if (command.size() > 260) { fail(); return; }
  constexpr auto key_name = L"Software\\Microsoft\\Windows\\CurrentVersion\\Run";
  HKEY key = nullptr;
  LSTATUS status = RegOpenKeyExW(HKEY_CURRENT_USER, key_name, 0,
      KEY_QUERY_VALUE | (write ? KEY_SET_VALUE : 0), &key);
  if (status == ERROR_FILE_NOT_FOUND && write && *enabled) {
    status = RegCreateKeyExW(HKEY_CURRENT_USER, key_name, 0, nullptr, 0,
                            KEY_QUERY_VALUE | KEY_SET_VALUE, nullptr, &key, nullptr);
  }
  if (status == ERROR_FILE_NOT_FOUND) {
    result->Success(flutter::EncodableValue("notConfigured"));
    return;
  }
  if (status != ERROR_SUCCESS) { fail(); return; }
  struct CloseKey { HKEY key; ~CloseKey() { RegCloseKey(key); } } close{key};
  DWORD type = 0;
  wchar_t value[262] = {};
  DWORD bytes = sizeof(value);
  status = RegQueryValueExW(key, L"EndlessNet", nullptr, &type,
                           reinterpret_cast<BYTE*>(value), &bytes);
  const bool missing = status == ERROR_FILE_NOT_FOUND;
  if (!missing && (status != ERROR_SUCCESS || type != REG_SZ ||
      bytes < sizeof(wchar_t) || bytes % sizeof(wchar_t) != 0 ||
      bytes > sizeof(value) || value[bytes / sizeof(wchar_t) - 1] != L'\0' ||
      std::wstring(value, bytes / sizeof(wchar_t) - 1) != command)) {
    // Refuse stale paths, arbitrary commands and obsolete installer entries.
    fail(); return;
  }
  if (write) {
    if (*enabled) {
      status = RegSetValueExW(key, L"EndlessNet", 0, REG_SZ,
          reinterpret_cast<const BYTE*>(command.c_str()),
          static_cast<DWORD>((command.size() + 1) * sizeof(wchar_t)));
    } else {
      status = missing ? ERROR_SUCCESS : RegDeleteValueW(key, L"EndlessNet");
    }
    if (status != ERROR_SUCCESS) { fail(); return; }
  }
  result->Success(flutter::EncodableValue(
      (write ? *enabled : !missing) ? "registered" : "notConfigured"));
}

#endif
