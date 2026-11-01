#include <windows.h>
#include <aclapi.h>
#include <string>
#include <memory>
#include <sddl.h>
#include <shlobj.h>
#include <shellapi.h>

// Capture thread-local GetLastError atomically with its API call. Dart FFI/VM
// transitions may change that slot, so a separate Dart GetLastError is unsafe.
extern "C" __declspec(dllexport) HANDLE en_pipe_open(
    const wchar_t* path, DWORD access, DWORD sharing, DWORD disposition,
    DWORD flags, DWORD* error) {
  HANDLE handle = CreateFileW(path, access, sharing, nullptr, disposition, flags,
                              nullptr);
  *error = handle == INVALID_HANDLE_VALUE ? GetLastError() : ERROR_SUCCESS;
  return handle;
}

extern "C" __declspec(dllexport) BOOL en_pipe_read(
    HANDLE handle, void* buffer, DWORD size, DWORD* transferred,
    OVERLAPPED* overlapped, DWORD* error) {
  BOOL result = ReadFile(handle, buffer, size, transferred, overlapped);
  *error = result ? ERROR_SUCCESS : GetLastError();
  return result;
}

extern "C" __declspec(dllexport) BOOL en_pipe_write(
    HANDLE handle, const void* buffer, DWORD size, DWORD* transferred,
    OVERLAPPED* overlapped, DWORD* error) {
  BOOL result = WriteFile(handle, buffer, size, transferred, overlapped);
  *error = result ? ERROR_SUCCESS : GetLastError();
  return result;
}

extern "C" __declspec(dllexport) BOOL en_pipe_result(
    HANDLE handle, OVERLAPPED* overlapped, DWORD* transferred, DWORD* error) {
  BOOL result = GetOverlappedResult(handle, overlapped, transferred, FALSE);
  *error = result ? ERROR_SUCCESS : GetLastError();
  return result;
}

namespace {
struct Handles {
  HANDLE values[64]{};
  size_t count = 0;
  ~Handles() {
    while (count > 0) CloseHandle(values[--count]);
  }
  bool Add(HANDLE handle) {
    if (handle == INVALID_HANDLE_VALUE) return false;
    if (count == 64) { CloseHandle(handle); return false; }
    values[count++] = handle;
    return true;
  }
};

bool PlainObject(HANDLE handle, bool directory) {
  BY_HANDLE_FILE_INFORMATION info{};
  return GetFileType(handle) == FILE_TYPE_DISK &&
    GetFileInformationByHandle(handle, &info) &&
    (info.dwFileAttributes & FILE_ATTRIBUTE_REPARSE_POINT) == 0 &&
    ((info.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY) != 0) == directory;
}

bool NormalizeLocalPath(const wchar_t* name, std::wstring* path) {
  if (name == nullptr) return false;
  const size_t size = wcsnlen_s(name, 32768);
  if (size < 3 || size >= 32768 || name[1] != L':' ||
      !((name[0] >= L'A' && name[0] <= L'Z') || (name[0] >= L'a' && name[0] <= L'z')) ||
      (name[2] != L'\\' && name[2] != L'/')) return false;
  *path = std::wstring(name, size);
  for (auto& c : *path) if (c == L'/') c = L'\\';
  return GetDriveTypeW(path->substr(0, 3).c_str()) == DRIVE_FIXED;
}

bool PathPart(const std::wstring& part) {
  return !part.empty() && part != L"." && part != L".." &&
    part.find(L':') == std::wstring::npos && part.back() != L'.' && part.back() != L' ';
}

bool PinDirectories(const std::wstring& path, Handles* handles, DWORD* error) {
  // Attribute-only handles do not enforce sharing restrictions. Retain list
  // access so omitting FILE_SHARE_DELETE actually prevents namespace renames.
  HANDLE dir = CreateFileW(path.substr(0, 3).c_str(), FILE_LIST_DIRECTORY | FILE_READ_ATTRIBUTES, FILE_SHARE_READ,
    nullptr, OPEN_EXISTING, FILE_FLAG_BACKUP_SEMANTICS | FILE_FLAG_OPEN_REPARSE_POINT, nullptr);
  if (dir == INVALID_HANDLE_VALUE) { *error = GetLastError(); return false; }
  if (!handles->Add(dir) || !PlainObject(dir, true)) return false;
  size_t start = 3;
  while (start < path.size()) {
    const size_t slash = path.find(L'\\', start);
    const size_t end = slash == std::wstring::npos ? path.size() : slash;
    if (!PathPart(path.substr(start, end - start))) return false;
    dir = CreateFileW(path.substr(0, end).c_str(), FILE_LIST_DIRECTORY | FILE_READ_ATTRIBUTES, FILE_SHARE_READ,
      nullptr, OPEN_EXISTING, FILE_FLAG_BACKUP_SEMANTICS | FILE_FLAG_OPEN_REPARSE_POINT, nullptr);
    if (dir == INVALID_HANDLE_VALUE) { *error = GetLastError(); return false; }
    if (!handles->Add(dir) || !PlainObject(dir, true)) return false;
    start = end + 1;
  }
  return true;
}

bool AdminConfiguration(HANDLE handle) {
  BYTE system[SECURITY_MAX_SID_SIZE]{};
  BYTE admins[SECURITY_MAX_SID_SIZE]{};
  DWORD system_size = sizeof(system), admins_size = sizeof(admins);
  if (!CreateWellKnownSid(WinLocalSystemSid, nullptr, system, &system_size) ||
      !CreateWellKnownSid(WinBuiltinAdministratorsSid, nullptr, admins, &admins_size)) return false;
  PSECURITY_DESCRIPTOR descriptor = nullptr;
  PSID owner = nullptr;
  PACL dacl = nullptr;
  const DWORD result = GetSecurityInfo(handle, SE_FILE_OBJECT,
    OWNER_SECURITY_INFORMATION | DACL_SECURITY_INFORMATION,
    &owner, nullptr, &dacl, nullptr, &descriptor);
  bool valid = result == ERROR_SUCCESS && owner != nullptr && dacl != nullptr &&
    (EqualSid(owner, system) || EqualSid(owner, admins));
  ACL_SIZE_INFORMATION size{};
  if (valid) valid = GetAclInformation(dacl, &size, sizeof(size), AclSizeInformation) != 0;
  for (DWORD i = 0; valid && i < size.AceCount; ++i) {
    void* raw = nullptr;
    if (!GetAce(dacl, i, &raw)) { valid = false; break; }
    const auto header = static_cast<ACE_HEADER*>(raw);
    if (header->AceType == ACCESS_DENIED_ACE_TYPE) continue;
    if (header->AceType != ACCESS_ALLOWED_ACE_TYPE) { valid = false; break; }
    const auto ace = static_cast<ACCESS_ALLOWED_ACE*>(raw);
    const PSID subject = &ace->SidStart;
    constexpr DWORD writes = FILE_WRITE_DATA | FILE_APPEND_DATA | FILE_WRITE_EA |
      FILE_WRITE_ATTRIBUTES | DELETE | WRITE_DAC | WRITE_OWNER | GENERIC_ALL |
      GENERIC_WRITE | ACCESS_SYSTEM_SECURITY | MAXIMUM_ALLOWED;
    if ((ace->Mask & writes) != 0 && !EqualSid(subject, system) && !EqualSid(subject, admins)) {
      valid = false;
    }
  }
  if (descriptor != nullptr) LocalFree(descriptor);
  return valid;
}
}  // namespace

// UI-owned administrator launch config. Pin each directory handle without
// write/delete sharing while walking; no reparse/UNC/device traversal or
// check-then-reopen race. This reads only; it never provisions ACLs or services.
extern "C" __declspec(dllexport) BOOL en_ui_read_admin_config(
    const wchar_t* name, BYTE* buffer, DWORD capacity, DWORD* length, DWORD* error) {
  *error = ERROR_ACCESS_DENIED;
  *length = 0;
  if (capacity == 0 || capacity > 65536) return FALSE;
  std::wstring path;
  if (!NormalizeLocalPath(name, &path) || path.size() <= 3) return FALSE;
  const size_t slash = path.rfind(L'\\');
  if (!PathPart(path.substr(slash + 1))) return FALSE;
  Handles handles;
  if (!PinDirectories(path.substr(0, slash == 2 ? 3 : slash), &handles, error)) return FALSE;
  const HANDLE file = CreateFileW(path.c_str(), FILE_READ_DATA | READ_CONTROL | FILE_READ_ATTRIBUTES,
    FILE_SHARE_READ, nullptr, OPEN_EXISTING, FILE_FLAG_OPEN_REPARSE_POINT, nullptr);
  if (file == INVALID_HANDLE_VALUE) { *error = GetLastError(); return FALSE; }
  if (!handles.Add(file) || !PlainObject(file, false) || !AdminConfiguration(file)) return FALSE;
  LARGE_INTEGER bytes{};
  if (!GetFileSizeEx(file, &bytes) || bytes.QuadPart <= 0 || bytes.QuadPart > capacity) return FALSE;
  while (*length < bytes.QuadPart) {
    DWORD read = 0;
    if (!ReadFile(file, buffer + *length, static_cast<DWORD>(bytes.QuadPart) - *length, &read, nullptr)) {
      *error = GetLastError();
      return FALSE;
    }
    if (read == 0) return FALSE;
    *length += read;
  }
  *error = ERROR_SUCCESS;
  return TRUE;
}

namespace {
bool PrivateObject(HANDLE handle, PSID user, bool directory) {
  BYTE system[SECURITY_MAX_SID_SIZE]{}, admins[SECURITY_MAX_SID_SIZE]{};
  DWORD system_size = sizeof(system), admins_size = sizeof(admins);
  if (!CreateWellKnownSid(WinLocalSystemSid, nullptr, system, &system_size) ||
      !CreateWellKnownSid(WinBuiltinAdministratorsSid, nullptr, admins, &admins_size)) return false;
  PSECURITY_DESCRIPTOR descriptor = nullptr;
  PSID owner = nullptr;
  PACL dacl = nullptr;
  const DWORD result = GetSecurityInfo(handle, SE_FILE_OBJECT,
    OWNER_SECURITY_INFORMATION | DACL_SECURITY_INFORMATION, &owner, nullptr, &dacl, nullptr, &descriptor);
  bool valid = result == ERROR_SUCCESS && owner != nullptr && dacl != nullptr &&
    (EqualSid(owner, user) || (!directory && (EqualSid(owner, system) || EqualSid(owner, admins))));
  SECURITY_DESCRIPTOR_CONTROL control = 0;
  DWORD revision = 0;
  if (valid && directory) valid = GetSecurityDescriptorControl(descriptor, &control, &revision) &&
    (control & SE_DACL_PROTECTED) != 0;
  ACL_SIZE_INFORMATION info{};
  if (valid) valid = GetAclInformation(dacl, &info, sizeof(info), AclSizeInformation) != 0;
  for (DWORD i = 0; valid && i < info.AceCount; ++i) {
    void* raw = nullptr;
    if (!GetAce(dacl, i, &raw)) { valid = false; break; }
    const auto header = static_cast<ACE_HEADER*>(raw);
    if (header->AceType == ACCESS_DENIED_ACE_TYPE) continue;
    if (header->AceType != ACCESS_ALLOWED_ACE_TYPE) { valid = false; break; }
    const auto ace = static_cast<ACCESS_ALLOWED_ACE*>(raw);
    const PSID subject = &ace->SidStart;
    if (ace->Mask != 0 && !EqualSid(subject, user) && !EqualSid(subject, system) && !EqualSid(subject, admins)) valid = false;
  }
  if (descriptor != nullptr) LocalFree(descriptor);
  return valid;
}
}  // namespace

namespace {
BOOL OpenPrivateState(const wchar_t* folder, wchar_t* output, DWORD capacity, void** guard, BOOL* created, DWORD* error) {
  *guard = nullptr;
  *created = FALSE;
  *error = ERROR_ACCESS_DENIED;
  std::wstring base;
  if (!NormalizeLocalPath(folder, &base)) return FALSE;
  auto handles = std::make_unique<Handles>();
  if (!PinDirectories(base, handles.get(), error)) return FALSE;
  HANDLE token = nullptr;
  if (!OpenProcessToken(GetCurrentProcess(), TOKEN_QUERY, &token)) { *error = GetLastError(); return FALSE; }
  alignas(TOKEN_USER) BYTE token_data[sizeof(TOKEN_USER) + SECURITY_MAX_SID_SIZE]{};
  DWORD size = 0;
  const BOOL token_ok = GetTokenInformation(token, TokenUser, token_data, sizeof(token_data), &size);
  CloseHandle(token);
  if (!token_ok) return FALSE;
  const auto user = reinterpret_cast<TOKEN_USER*>(token_data)->User.Sid;
  LPWSTR sid_text = nullptr;
  if (!ConvertSidToStringSidW(user, &sid_text)) return FALSE;
  const std::wstring sddl = std::wstring(L"O:") + sid_text +
    L"D:P(A;OICI;FA;;;SY)(A;OICI;FA;;;BA)(A;OICI;FA;;;" + sid_text + L")";
  LocalFree(sid_text);
  PSECURITY_DESCRIPTOR descriptor = nullptr;
  if (!ConvertStringSecurityDescriptorToSecurityDescriptorW(sddl.c_str(), SDDL_REVISION_1, &descriptor, nullptr)) return FALSE;
  SECURITY_ATTRIBUTES attributes{sizeof(SECURITY_ATTRIBUTES), descriptor, FALSE};
  bool valid = true;
  for (const auto child : {L"EndlessNet", L"ClientUI"}) {
    base += L"\\";
    base += child;
    if (!CreateDirectoryW(base.c_str(), &attributes) && GetLastError() != ERROR_ALREADY_EXISTS) { valid = false; break; }
    const HANDLE dir = CreateFileW(base.c_str(), FILE_LIST_DIRECTORY | READ_CONTROL | FILE_READ_ATTRIBUTES, FILE_SHARE_READ,
      nullptr, OPEN_EXISTING, FILE_FLAG_BACKUP_SEMANTICS | FILE_FLAG_OPEN_REPARSE_POINT, nullptr);
    if (!handles->Add(dir) || !PlainObject(dir, true) || !PrivateObject(dir, user, true)) { valid = false; break; }
  }
  LocalFree(descriptor);
  if (!valid) return FALSE;
  base += L"\\correlation.bin";
  // Pin even a newly created file before Dart opens it. The created flag only
  // authorizes first initialization; an already empty file is never repaired.
  const HANDLE existing = CreateFileW(base.c_str(), FILE_READ_DATA | READ_CONTROL | FILE_READ_ATTRIBUTES,
    FILE_SHARE_READ | FILE_SHARE_WRITE, nullptr, OPEN_ALWAYS, FILE_FLAG_OPEN_REPARSE_POINT, nullptr);
  const DWORD opened = GetLastError();
  if (existing == INVALID_HANDLE_VALUE) { *error = opened; return FALSE; }
  if (!handles->Add(existing) || !PlainObject(existing, false) || !PrivateObject(existing, user, false)) return FALSE;
  if (base.size() + 1 > capacity) return FALSE;
  if (wcscpy_s(output, capacity, base.c_str()) != 0) return FALSE;
  *guard = handles.release();
  *created = opened != ERROR_ALREADY_EXISTS;
  *error = ERROR_SUCCESS;
  return TRUE;
}

}  // namespace

extern "C" __declspec(dllexport) BOOL en_ui_open_private_state(
    wchar_t* output, DWORD capacity, void** guard, BOOL* created, DWORD* error) {
  PWSTR folder = nullptr;
  const HRESULT known = SHGetKnownFolderPath(FOLDERID_LocalAppData, 0, nullptr, &folder);
  BOOL result = FALSE;
  *guard = nullptr;
  *created = FALSE;
  *error = ERROR_ACCESS_DENIED;
  if (SUCCEEDED(known)) result = OpenPrivateState(folder, output, capacity, guard, created, error);
  CoTaskMemFree(folder);
  return result;
}

#ifdef ENDLESSNET_NATIVE_FIXTURE
// Fixture-only export is absent from the installed production DLL.
extern "C" __declspec(dllexport) BOOL en_ui_open_private_state_fixture(
    const wchar_t* root, wchar_t* output, DWORD capacity, void** guard, BOOL* created, DWORD* error) {
  return OpenPrivateState(root, output, capacity, guard, created, error);
}
#endif

extern "C" __declspec(dllexport) void en_ui_close_private_state(void* guard) {
  delete static_cast<Handles*>(guard);
}

extern "C" __declspec(dllexport) BOOL en_ui_open_browser(const wchar_t* url, DWORD* error) {
  *error = ERROR_INVALID_PARAMETER;
  if (url == nullptr || wcsnlen_s(url, 8193) > 8192 || wcsncmp(url, L"https://", 8) != 0) return FALSE;
  for (const wchar_t* p = url; *p; ++p) if (*p < L' ' || *p == L'\x7f') return FALSE;
  const HRESULT initialized = CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED | COINIT_DISABLE_OLE1DDE);
  if (FAILED(initialized)) return FALSE;
  SHELLEXECUTEINFOW action{};
  action.cbSize = sizeof(action);
  action.fMask = SEE_MASK_NOCLOSEPROCESS | SEE_MASK_FLAG_NO_UI | SEE_MASK_NOASYNC;
  action.lpVerb = L"open";
  action.lpFile = url;
  action.nShow = SW_SHOWNORMAL;
  const BOOL result = ShellExecuteExW(&action);
  *error = result ? ERROR_SUCCESS : GetLastError();
  if (action.hProcess != nullptr) CloseHandle(action.hProcess);
  CoUninitialize();
  return result;
}
