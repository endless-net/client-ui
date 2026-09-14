#include <windows.h>
#include <flutter/encodable_value.h>
#include <flutter/method_call.h>
#include <flutter/method_result.h>
#include <cstring>
#include <iostream>
#include <stdexcept>
#include <string>

namespace {
void Check(bool value) { if (!value) throw std::runtime_error("assertion failed"); }
std::wstring exe = L"C:\\Program Files\\EndlessNet\\endlessnet.exe";
std::wstring entry;
LSTATUS open_status = ERROR_SUCCESS, query_status = ERROR_FILE_NOT_FOUND;
LSTATUS mutation_status = ERROR_SUCCESS;
DWORD entry_type = REG_SZ;
int writes = 0, deletes = 0, opens = 0, closes = 0;
DWORD FakePath(HMODULE, LPWSTR out, DWORD size) {
  if (exe.size() >= size) return size;
  std::memcpy(out, exe.c_str(), (exe.size() + 1) * sizeof(wchar_t));
  return static_cast<DWORD>(exe.size());
}
LSTATUS FakeOpen(HKEY root, LPCWSTR key, DWORD, REGSAM, PHKEY out) {
  Check(root == HKEY_CURRENT_USER);
  Check(std::wstring(key) == L"Software\\Microsoft\\Windows\\CurrentVersion\\Run");
  ++opens; *out = reinterpret_cast<HKEY>(1); return open_status;
}
LSTATUS FakeCreate(HKEY root, LPCWSTR key, DWORD, LPWSTR, DWORD,
    REGSAM access, const LPSECURITY_ATTRIBUTES, PHKEY out, LPDWORD) {
  open_status = ERROR_SUCCESS;
  return FakeOpen(root, key, 0, access, out);
}
LSTATUS FakeQuery(HKEY, LPCWSTR name, LPDWORD, LPDWORD type, LPBYTE out, LPDWORD bytes) {
  Check(std::wstring(name) == L"EndlessNet");
  if (query_status != ERROR_SUCCESS) return query_status;
  const auto required = (entry.size() + 1) * sizeof(wchar_t);
  if (required > *bytes) return ERROR_MORE_DATA;
  *bytes = static_cast<DWORD>(required); *type = entry_type;
  std::memcpy(out, entry.c_str(), required); return ERROR_SUCCESS;
}
LSTATUS FakeSet(HKEY, LPCWSTR name, DWORD, DWORD type, const BYTE* data, DWORD bytes) {
  Check(std::wstring(name) == L"EndlessNet" && type == REG_SZ);
  ++writes;
  entry.assign(reinterpret_cast<const wchar_t*>(data), bytes / sizeof(wchar_t) - 1);
  return mutation_status;
}
LSTATUS FakeDelete(HKEY, LPCWSTR name) {
  Check(std::wstring(name) == L"EndlessNet"); ++deletes; return mutation_status;
}
LSTATUS FakeClose(HKEY) { ++closes; return ERROR_SUCCESS; }
}  // namespace

// Compile the production handler against an in-memory Win32 boundary. No user's
// registry, startup permission or session is touched by this unit executable.
#define GetModuleFileNameW FakePath
#define RegOpenKeyExW FakeOpen
#define RegCreateKeyExW FakeCreate
#define RegQueryValueExW FakeQuery
#define RegSetValueExW FakeSet
#define RegDeleteValueW FakeDelete
#define RegCloseKey FakeClose
#include "ui_autostart.h"

using Value = flutter::EncodableValue;
class Result : public flutter::MethodResult<Value> {
 public:
  explicit Result(std::string& output) : output_(output) {}
 protected:
  void SuccessInternal(const Value* value) override { output_ = std::get<std::string>(*value); }
  void ErrorInternal(const std::string& code, const std::string&, const Value*) override { output_ = code; }
  void NotImplementedInternal() override { output_ = "notImplemented"; }
 private:
  std::string& output_;
};
std::string Invoke(const std::string& method, Value argument = Value()) {
  std::string output;
  flutter::MethodCall<Value> call(method, std::make_unique<Value>(argument));
  HandleUiAutostart(call, std::make_unique<Result>(output));
  return output;
}
int main() {
  Check(Invoke("read") == "notConfigured" && writes == 0 && deletes == 0);
  Check(Invoke("setEnabled", Value(true)) == "registered" && writes == 1);
  Check(entry == L"\"" + exe + L"\"");
  query_status = ERROR_SUCCESS;
  Check(Invoke("read") == "registered" && writes == 1);
  Check(Invoke("setEnabled", Value(false)) == "notConfigured" && deletes == 1);
  for (const auto& bad : {L"other.exe", L"\"old.exe\"", L"\"endlessnet.exe\" --debug"}) {
    entry = bad;
    Check(Invoke("setEnabled", Value(true)) == "autostart_unavailable");
    Check(Invoke("setEnabled", Value(false)) == "autostart_unavailable");
  }
  Check(writes == 1 && deletes == 1);
  entry = L"\"" + exe + L"\"";
  entry_type = REG_EXPAND_SZ;
  Check(Invoke("read") == "autostart_unavailable");
  entry_type = REG_SZ;
  entry += std::wstring(L"\0extra", 6);
  Check(Invoke("read") == "autostart_unavailable");
  entry = L"\"" + exe + L"\"";
  mutation_status = ERROR_ACCESS_DENIED;
  Check(Invoke("setEnabled", Value(true)) == "autostart_unavailable");
  Check(Invoke("setEnabled", Value(false)) == "autostart_unavailable");
  open_status = ERROR_ACCESS_DENIED;
  Check(Invoke("read") == "autostart_unavailable");
  open_status = ERROR_FILE_NOT_FOUND;
  Check(Invoke("read") == "notConfigured");
  Check(Invoke("setEnabled", Value(false)) == "notConfigured");
  query_status = ERROR_FILE_NOT_FOUND; mutation_status = ERROR_SUCCESS;
  Check(Invoke("setEnabled", Value(true)) == "registered");
  const int before = opens;
  Check(Invoke("setEnabled", Value("true")) == "invalid_arguments");
  Check(Invoke("read", Value(true)) == "invalid_arguments");
  Check(Invoke("unexpected") == "notImplemented");
  exe = std::wstring(259, L'a');
  Check(Invoke("setEnabled", Value(true)) == "autostart_unavailable");
  Check(opens == before);
  Check(closes > 0);
  std::cout << "Windows UI autostart unit checks passed\n";
}
