#include "peer_identity.h"
#include <sddl.h>
namespace sd {
namespace {
uint64_t Creation(HANDLE process) {
  FILETIME created{}, exited{}, kernel{}, user{};
  if (!GetProcessTimes(process, &created, &exited, &kernel, &user)) return 0;
  return (static_cast<uint64_t>(created.dwHighDateTime) << 32) | created.dwLowDateTime;
}
std::wstring ProcessSid(HANDLE process, bool logon) {
  HANDLE raw = nullptr;
  if (!OpenProcessToken(process, TOKEN_QUERY, &raw)) return L"";
  Handle token(raw);
  const auto type = logon ? TokenGroups : TokenUser;
  DWORD size = 0;
  GetTokenInformation(raw, type, nullptr, 0, &size);
  std::vector<uint8_t> bytes(size);
  if (!GetTokenInformation(raw, type, bytes.data(), size, &size)) return L"";
  PSID sid = nullptr;
  if (!logon) sid = reinterpret_cast<TOKEN_USER*>(bytes.data())->User.Sid;
  else {
    const auto* groups = reinterpret_cast<TOKEN_GROUPS*>(bytes.data());
    for (DWORD i = 0; i < groups->GroupCount; ++i)
      if ((groups->Groups[i].Attributes & SE_GROUP_LOGON_ID) == SE_GROUP_LOGON_ID)
        sid = groups->Groups[i].Sid;
  }
  LPWSTR text = nullptr;
  if (!sid || !ConvertSidToStringSidW(sid, &text)) return L"";
  const std::wstring result(text); LocalFree(text); return result;
}
}
bool PeerIdentity(HANDLE pipe, bool serverPeer, const std::wstring& user,
                  const std::wstring& logon, DWORD expectedPid, uint64_t expectedCreation) {
  ULONG pid = 0;
  if (!(serverPeer ? GetNamedPipeServerProcessId(pipe, &pid) : GetNamedPipeClientProcessId(pipe, &pid))) return false;
  if (expectedPid && pid != expectedPid) return false;
  Handle process(OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, FALSE, pid));
  return process.valid() && (!expectedCreation || Creation(process.get()) == expectedCreation) &&
    ProcessSid(process.get(), false) == user && ProcessSid(process.get(), true) == logon;
}
}
