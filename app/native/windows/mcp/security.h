#pragma once
#include <windows.h>
#include <filesystem>
#include <string>
#include <vector>

namespace sd {
class Handle {
 public:
  explicit Handle(HANDLE value = INVALID_HANDLE_VALUE) : value_(value) {}
  ~Handle() { if (value_ && value_ != INVALID_HANDLE_VALUE) CloseHandle(value_); }
  Handle(const Handle&) = delete;
  Handle& operator=(const Handle&) = delete;
  HANDLE get() const { return value_; }
  bool valid() const { return value_ && value_ != INVALID_HANDLE_VALUE; }
 private:
  HANDLE value_;
};
std::wstring Wide(const std::string& text);
std::string Utf8(const std::wstring& text);
std::wstring UserSid();
std::wstring LogonSid();
std::wstring Uuid();
std::filesystem::path DataRoot();
std::filesystem::path ExtendedPath(const std::filesystem::path& path);
void RejectReparse(const std::filesystem::path& path);
void SecureDirectory(const std::filesystem::path& path);
void SecureFileHandle(HANDLE file);
void AtomicFile(const std::filesystem::path& path, const std::vector<uint8_t>& bytes);
}
