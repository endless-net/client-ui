#include "security.h"
#include <sddl.h>
#include <shlobj.h>
#include <aclapi.h>
#include <algorithm>
#include <stdexcept>

namespace sd {
namespace {
[[noreturn]] void Fail() { throw std::runtime_error("STORAGE_IO:" + std::to_string(GetLastError())); }
std::vector<uint8_t> TokenData(TOKEN_INFORMATION_CLASS type) {
  HANDLE raw = nullptr;
  if (!OpenProcessToken(GetCurrentProcess(), TOKEN_QUERY, &raw)) Fail();
  Handle token(raw);
  DWORD size = 0;
  GetTokenInformation(raw, type, nullptr, 0, &size);
  std::vector<uint8_t> data(size);
  if (!GetTokenInformation(raw, type, data.data(), size, &size)) Fail();
  return data;
}
std::wstring SidText(PSID sid) {
  LPWSTR text = nullptr;
  if (!ConvertSidToStringSidW(sid, &text)) Fail();
  const std::wstring result(text);
  LocalFree(text);
  return result;
}
PSECURITY_DESCRIPTOR UserDescriptor() {
  const auto sddl = L"D:P(A;OICI;FA;;;" + UserSid() +
                    L")(A;OICI;FA;;;SY)(A;OICI;FA;;;BA)";
  PSECURITY_DESCRIPTOR descriptor = nullptr;
  if (!ConvertStringSecurityDescriptorToSecurityDescriptorW(
        sddl.c_str(), SDDL_REVISION_1, &descriptor, nullptr)) Fail();
  return descriptor;
}
}
std::wstring Wide(const std::string& text) {
  if (text.size() > INT_MAX) Fail();
  int size = MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, text.data(),
                               static_cast<int>(text.size()), nullptr, 0);
  if (!size && !text.empty()) Fail();
  std::wstring result(size, 0);
  if (size) MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, text.data(),
                              static_cast<int>(text.size()), result.data(), size);
  return result;
}
std::string Utf8(const std::wstring& text) {
  if (text.size() > INT_MAX) Fail();
  int size = WideCharToMultiByte(CP_UTF8, WC_ERR_INVALID_CHARS, text.data(),
                               static_cast<int>(text.size()), nullptr, 0, nullptr, nullptr);
  if (!size && !text.empty()) Fail();
  std::string result(size, 0);
  if (size) WideCharToMultiByte(CP_UTF8, WC_ERR_INVALID_CHARS, text.data(),
                              static_cast<int>(text.size()), result.data(), size, nullptr, nullptr);
  return result;
}
std::wstring UserSid() {
  auto data = TokenData(TokenUser);
  return SidText(reinterpret_cast<TOKEN_USER*>(data.data())->User.Sid);
}
std::wstring LogonSid() {
  auto data = TokenData(TokenGroups);
  const auto* groups = reinterpret_cast<TOKEN_GROUPS*>(data.data());
  for (DWORD i = 0; i < groups->GroupCount; ++i) {
    if ((groups->Groups[i].Attributes & SE_GROUP_LOGON_ID) == SE_GROUP_LOGON_ID)
      return SidText(groups->Groups[i].Sid);
  }
  Fail();
}
std::wstring Uuid() {
  GUID id{};
  if (FAILED(CoCreateGuid(&id))) Fail();
  wchar_t text[40]{};
  if (!StringFromGUID2(id, text, 40)) Fail();
  std::wstring result(text + 1, 36);
  std::transform(result.begin(), result.end(), result.begin(), towlower);
  return result;
}
std::filesystem::path ExtendedPath(const std::filesystem::path& path) {
  auto text = std::filesystem::absolute(path).wstring();
  std::replace(text.begin(), text.end(), L'/', L'\\');
  if (text.rfind(L"\\\\?\\", 0) == 0) return text;
  if (text.rfind(L"\\\\", 0) == 0) return L"\\\\?\\UNC\\" + text.substr(2);
  return L"\\\\?\\" + text;
}
void RejectReparse(const std::filesystem::path& path) {
  auto text = std::filesystem::absolute(path).wstring();
  if (text.rfind(L"\\\\?\\UNC\\", 0) == 0) text = L"\\\\" + text.substr(8);
  else if (text.rfind(L"\\\\?\\", 0) == 0) text = text.substr(4);
  auto current = std::filesystem::path(text);
  while (!current.empty()) {
    const auto extended = ExtendedPath(current);
    DWORD attrs = GetFileAttributesW(extended.c_str());
    if (attrs != INVALID_FILE_ATTRIBUTES && (attrs & FILE_ATTRIBUTE_REPARSE_POINT)) Fail();
    if (attrs == INVALID_FILE_ATTRIBUTES && GetLastError() != ERROR_FILE_NOT_FOUND &&
        GetLastError() != ERROR_PATH_NOT_FOUND) Fail();
    const auto parent = current.parent_path();
    if (parent == current) break;
    current = parent;
  }
}
void SecureDirectory(const std::filesystem::path& input) {
  const auto path = ExtendedPath(input);
  RejectReparse(path);
  PSECURITY_DESCRIPTOR descriptor = UserDescriptor();
  SECURITY_ATTRIBUTES attrs{sizeof(SECURITY_ATTRIBUTES), descriptor, FALSE};
  const bool created = CreateDirectoryW(path.c_str(), &attrs) != 0;
  const DWORD error = GetLastError();
  if (!created && error == ERROR_ALREADY_EXISTS) {
    if (!SetFileSecurityW(path.c_str(), DACL_SECURITY_INFORMATION |
                         PROTECTED_DACL_SECURITY_INFORMATION, descriptor)) {
      LocalFree(descriptor); Fail();
    }
  }
  LocalFree(descriptor);
  if (!created && error != ERROR_ALREADY_EXISTS) Fail();
  RejectReparse(path);
}
void SecureFileHandle(HANDLE file) {
  auto* descriptor = UserDescriptor();
  BOOL present = FALSE, defaulted = FALSE;
  PACL acl = nullptr;
  if (!GetSecurityDescriptorDacl(descriptor, &present, &acl, &defaulted) || !present) {
    LocalFree(descriptor); Fail();
  }
  const DWORD result = SetSecurityInfo(file, SE_FILE_OBJECT,
    DACL_SECURITY_INFORMATION | PROTECTED_DACL_SECURITY_INFORMATION, nullptr, nullptr, acl, nullptr);
  LocalFree(descriptor);
  if (result != ERROR_SUCCESS) { SetLastError(result); Fail(); }
}
std::filesystem::path DataRoot() {
  PWSTR folder = nullptr;
  if (FAILED(SHGetKnownFolderPath(FOLDERID_LocalAppData, 0, nullptr, &folder))) Fail();
  auto result = std::filesystem::path(folder) / L"EndlessNet.ClientUi.Mcp";
  CoTaskMemFree(folder);
  SecureDirectory(result);
  result /= LogonSid();
  SecureDirectory(result);
  return result;
}
void AtomicFile(const std::filesystem::path& input, const std::vector<uint8_t>& bytes) {
  const auto path = ExtendedPath(input);
  RejectReparse(path);
  const auto staging = path.wstring() + L"." + Uuid() + L".tmp";
  try {
   {
    Handle file(CreateFileW(staging.c_str(), GENERIC_WRITE, 0, nullptr, CREATE_NEW,
                           FILE_FLAG_OPEN_REPARSE_POINT, nullptr));
    DWORD written = 0;
    if (!file.valid() || bytes.size() > MAXDWORD ||
        !WriteFile(file.get(), bytes.data(), static_cast<DWORD>(bytes.size()), &written, nullptr) ||
        written != bytes.size() || !FlushFileBuffers(file.get())) Fail();
   }
   if (!MoveFileExW(staging.c_str(), path.c_str(),
                    MOVEFILE_REPLACE_EXISTING | MOVEFILE_WRITE_THROUGH)) Fail();
  } catch (...) {
    // This file is uniquely created by this call, never an arbitrary orphan.
    DeleteFileW(staging.c_str());
    throw;
  }
}
}
