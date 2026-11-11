#include <windows.h>
#include <msiquery.h>
#include <shlobj.h>
#include <algorithm>
#include <cwctype>
#include <string>

namespace {
std::wstring CanonicalGuid(const GUID& guid) {
  wchar_t text[39]{};
  if (!StringFromGUID2(guid, text, 39)) return {};
  std::wstring result(text + 1, 36);
  std::transform(result.begin(), result.end(), result.begin(), towlower);
  return result;
}
bool TargetIs(MSIHANDLE session, const wchar_t* directory, REFKNOWNFOLDERID folder,
              const wchar_t* suffix) {
  wchar_t target[32768]{}; DWORD length = 32768;
  PWSTR known = nullptr;
  if (MsiGetTargetPathW(session, directory, target, &length) != ERROR_SUCCESS ||
      FAILED(SHGetKnownFolderPath(folder, KF_FLAG_DONT_VERIFY, nullptr, &known))) return false;
  const auto expected = std::wstring(known) + suffix;
  CoTaskMemFree(known);
  return _wcsicmp(target, expected.c_str()) == 0;
}
}

// Immediate, read-only preflight. Only MSI properties are changed; Windows
// Installer owns the later registry, directory, service and file transactions.
extern "C" __declspec(dllexport) UINT __stdcall PrepareMachine(MSIHANDLE session) {
  SYSTEM_INFO system{}; GetNativeSystemInfo(&system);
  using Version = LONG(WINAPI*)(OSVERSIONINFOEXW*);
  auto version = reinterpret_cast<Version>(GetProcAddress(GetModuleHandleW(L"ntdll.dll"), "RtlGetVersion"));
  OSVERSIONINFOEXW os{}; os.dwOSVersionInfoSize = sizeof(os);
  if (system.wProcessorArchitecture != PROCESSOR_ARCHITECTURE_AMD64 || !version ||
      version(&os) != 0 || os.dwMajorVersion < 10 || os.dwBuildNumber < 22000 ||
      os.wProductType != VER_NT_WORKSTATION) return ERROR_INSTALL_PLATFORM_UNSUPPORTED;
  if (!TargetIs(session, L"AppRoot", FOLDERID_ProgramFilesX64, L"\\EndlessNet\\") ||
      !TargetIs(session, L"ClientData", FOLDERID_ProgramData, L"\\EndlessNet\\Client\\") ||
      !TargetIs(session, L"ClientState", FOLDERID_ProgramData, L"\\EndlessNet\\Client\\state\\"))
    return ERROR_INSTALL_FAILURE;

  wchar_t previous[37]{}; DWORD length = sizeof(previous);
  const auto status = RegGetValueW(HKEY_LOCAL_MACHINE, L"SOFTWARE\\EndlessNet\\Client",
      L"InstallationId", RRF_RT_REG_SZ | RRF_SUBKEY_WOW6464KEY, nullptr, previous, &length);
  GUID id{}; bool existing = false;
  if (status == ERROR_SUCCESS) {
    if (length != sizeof(previous) || previous[36] != 0) return ERROR_INSTALL_FAILURE;
    const auto wrapped = L"{" + std::wstring(previous) + L"}";
    if (FAILED(IIDFromString(wrapped.c_str(), &id)) || IsEqualGUID(id, GUID_NULL) ||
        CanonicalGuid(id) != previous) return ERROR_INSTALL_FAILURE;
    existing = true;
  } else if (status == ERROR_FILE_NOT_FOUND || status == ERROR_PATH_NOT_FOUND) {
    if (FAILED(CoCreateGuid(&id))) return ERROR_INSTALL_FAILURE;
  } else return ERROR_INSTALL_FAILURE;
  if (MsiSetPropertyW(session, L"ENDLESSNET_INSTALLATION_ID", CanonicalGuid(id).c_str()) != ERROR_SUCCESS ||
      MsiSetPropertyW(session, L"ENDLESSNET_EXISTING_INSTALLATION", existing ? L"1" : L"") != ERROR_SUCCESS)
    return ERROR_INSTALL_FAILURE;
  return ERROR_SUCCESS;
}
