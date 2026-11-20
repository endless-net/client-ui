#pragma once
#include "security.h"

namespace sd {
bool PeerIdentity(HANDLE pipe, bool serverPeer, const std::wstring& user,
                  const std::wstring& logon, DWORD expectedPid = 0,
                  uint64_t expectedCreation = 0);
}
