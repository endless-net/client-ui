#include <windows.h>
#include <string>

namespace {
constexpr auto kService = L"endlessnet-updater";

bool Digits(const std::wstring& text, size_t maximum) {
  return !text.empty() && text.size() <= maximum && (text.size() == 1 || text.front() != L'0') &&
      text.find_first_not_of(L"0123456789") == std::wstring::npos;
}

DWORD Launch(DWORD argc, wchar_t** argv) {
  if (argc != 3) return ERROR_INVALID_PARAMETER;
  const std::wstring version(argv[1]), operation(argv[2]);
  const auto separator = version.find(L'.', 2);
  if (version.rfind(L"0.", 0) != 0 || separator == std::wstring::npos ||
      !Digits(version.substr(2, separator - 2), 3) || !Digits(version.substr(separator + 1), 5) ||
      operation.size() != 32 || operation.find_first_not_of(L"0123456789abcdef") != std::wstring::npos) {
    return ERROR_INVALID_PARAMETER;
  }
  wchar_t module[32768]{}, system[MAX_PATH]{};
  const auto length = GetModuleFileNameW(nullptr, module, ARRAYSIZE(module));
  const auto systemLength = GetSystemDirectoryW(system, ARRAYSIZE(system));
  if (!length || length == ARRAYSIZE(module) || !systemLength || systemLength >= ARRAYSIZE(system)) {
    return ERROR_BAD_PATHNAME;
  }
  const std::wstring image(module, length);
  const auto worker = image.substr(0, image.find_last_of(L'\\') + 1) + L"update-worker.ps1";
  const auto powershell = std::wstring(system) + L"\\WindowsPowerShell\\v1.0\\powershell.exe";
  auto command = L"\"" + powershell + L"\" -NoLogo -NoProfile -NonInteractive -ExecutionPolicy RemoteSigned -File \""
      + worker + L"\" -Version " + version + L" -Operation " + operation;
  STARTUPINFOW startup{};
  startup.cb = sizeof(startup);
  PROCESS_INFORMATION child{};
  if (!CreateProcessW(powershell.c_str(), command.data(), nullptr, nullptr, FALSE, CREATE_NO_WINDOW,
                      nullptr, system, &startup, &child)) return GetLastError();
  CloseHandle(child.hThread);
  CloseHandle(child.hProcess);
  return ERROR_SUCCESS;
}

DWORD WINAPI Control(DWORD, DWORD, void*, void*) { return ERROR_CALL_NOT_IMPLEMENTED; }

void WINAPI ServiceMain(DWORD argc, wchar_t** argv) {
  const auto handle = RegisterServiceCtrlHandlerExW(kService, Control, nullptr);
  if (!handle) return;
  SERVICE_STATUS state{};
  state.dwServiceType = SERVICE_WIN32_OWN_PROCESS;
  state.dwCurrentState = SERVICE_START_PENDING;
  state.dwCheckPoint = 1;
  state.dwWaitHint = 5000;
  SetServiceStatus(handle, &state);
  const auto error = Launch(argc, argv);
  state.dwCheckPoint = state.dwWaitHint = 0;
  if (!error) {
    state.dwCurrentState = SERVICE_RUNNING;
    SetServiceStatus(handle, &state);
  }
  // The worker owns the transaction and can replace this image during MSI upgrade.
  state.dwCurrentState = SERVICE_STOPPED;
  state.dwWin32ExitCode = error;
  SetServiceStatus(handle, &state);
}
}

int wmain() {
  SERVICE_TABLE_ENTRYW table[] = {{const_cast<wchar_t*>(kService), ServiceMain}, {nullptr, nullptr}};
  return StartServiceCtrlDispatcherW(table) ? 0 : static_cast<int>(GetLastError());
}
