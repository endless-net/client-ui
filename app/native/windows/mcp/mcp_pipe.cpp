#include "mcp_pipe.h"
#include "mcp_boundary.h"
#include "mcp_idle_bridge.h"
#include <chrono>
#include "peer_identity.h"
#include <aclapi.h>
#include <sddl.h>
#include <wincrypt.h>
#include <algorithm>
#include <atomic>
#include <condition_variable>
#include <deque>
#include <mutex>
#include <thread>
#include <cstring>

namespace sd::mcp {
namespace {
[[noreturn]] void Fail() { throw std::runtime_error("MCP_UNAVAILABLE"); }
uint64_t Creation() {
  FILETIME created{}, exit{}, kernel{}, user{};
  if (!GetProcessTimes(GetCurrentProcess(), &created, &exit, &kernel, &user)) Fail();
  return (static_cast<uint64_t>(created.dwHighDateTime) << 32) | created.dwLowDateTime;
}
// Overlapped pipe I/O is interrupted by the owner's stop event. No detached work.
DWORD Io(HANDLE pipe, HANDLE stop, bool writing, void* bytes, DWORD count, DWORD timeout = INFINITE) {
  if (WaitForSingleObject(stop, 0) == WAIT_OBJECT_0) Fail();
  Handle event(CreateEventW(nullptr, TRUE, FALSE, nullptr)); if (!event.valid()) Fail();
  OVERLAPPED operation{}; operation.hEvent = event.get(); DWORD transferred = 0;
  const BOOL immediate = writing ? WriteFile(pipe, bytes, count, &transferred, &operation) : ReadFile(pipe, bytes, count, &transferred, &operation);
  if (immediate) return transferred;
  const auto error = GetLastError();
  if (error == ERROR_BROKEN_PIPE || error == ERROR_PIPE_NOT_CONNECTED || error == ERROR_NO_DATA) throw EndOfStream{};
  if (error != ERROR_IO_PENDING) Fail();
  HANDLE waits[]{stop, event.get()};
  if (WaitForMultipleObjects(2, waits, FALSE, timeout) != WAIT_OBJECT_0 + 1) {
    CancelIoEx(pipe, &operation); GetOverlappedResult(pipe, &operation, &transferred, TRUE); Fail();
  }
  if (!GetOverlappedResult(pipe, &operation, &transferred, FALSE)) {
    const auto ended = GetLastError();if (ended == ERROR_BROKEN_PIPE || ended == ERROR_PIPE_NOT_CONNECTED || ended == ERROR_NO_DATA) throw EndOfStream{};
    Fail();
  } return transferred;
}
void WriteLine(HANDLE pipe, HANDLE stop, const std::string& text) {
  WriteFrame(text, [&](const char* bytes, size_t count) {
    return static_cast<size_t>(Io(pipe, stop, true, const_cast<char*>(bytes), static_cast<DWORD>(count), 5000));
  });
}
class Lines {
 public:
  Lines() : reader_([] { return GetTickCount64(); }) {}
  bool HasFrame() const { return reader_.HasFrame(); }
  std::string Read(HANDLE pipe, HANDLE stop, DWORD timeout = INFINITE) {
    return reader_.Read([&](char* bytes, size_t count, uint32_t remaining) {
      return static_cast<size_t>(Io(pipe, stop, false, bytes, static_cast<DWORD>(count), remaining));
    }, timeout);
  }
 private:
  FrameReader reader_;
};
std::string TokenSid(HANDLE token, TOKEN_INFORMATION_CLASS kind) {
  DWORD length = 0; GetTokenInformation(token, kind, nullptr, 0, &length); if (!length || length > 65536) Fail();
  std::vector<uint8_t> bytes(length); if (!GetTokenInformation(token, kind, bytes.data(), length, &length)) Fail();
  PSID sid = nullptr;
  if (kind == TokenUser) sid = reinterpret_cast<TOKEN_USER*>(bytes.data())->User.Sid;
  else { const auto* groups = reinterpret_cast<TOKEN_GROUPS*>(bytes.data()); for (DWORD i = 0; i < groups->GroupCount; ++i)
    if ((groups->Groups[i].Attributes & SE_GROUP_LOGON_ID) == SE_GROUP_LOGON_ID) { sid = groups->Groups[i].Sid; break; } }
  LPWSTR text = nullptr; if (!sid || !ConvertSidToStringSidW(sid, &text)) Fail(); const auto result = Utf8(text); LocalFree(text); return result;
}
bool ClientIdentity(HANDLE pipe, const std::wstring& user, const std::wstring& logon) {
  ClientPeerPorts ports;
  ports.processIdentity = [&] { return PeerIdentity(pipe, false, user, logon); };
  ports.impersonate = [&] { return ImpersonateNamedPipeClient(pipe) != FALSE; };
  ports.tokenIdentity = [] {
    HANDLE raw = nullptr; if (!OpenThreadToken(GetCurrentThread(), TOKEN_QUERY, TRUE, &raw)) Fail(); Handle token(raw);
    return std::make_pair(TokenSid(raw, TokenUser), TokenSid(raw, TokenGroups));
  };
  ports.revert = [] { return RevertToSelf() != FALSE; };
  const auto result = VerifyClientPeer(ports, Utf8(user), Utf8(logon));
  if (result == ClientPeerResult::revertFailed) std::terminate();
  return result == ClientPeerResult::allowed;
}
void AtomicJson(const std::filesystem::path& path, const Json& value) {
  const auto text = Encode(value); AtomicFile(path, std::vector<uint8_t>(text.begin(), text.end()));
}
}
struct Broker::Impl {
  struct Channel {
    Channel(std::string value, std::unique_ptr<Handle> handle) : id(std::move(value)), pipe(std::move(handle)), stop(CreateEventW(nullptr, TRUE, FALSE, nullptr)),
      workers([this] { Stop(); }, [this] { std::lock_guard<std::mutex> lock(closeMutex); pipe.reset(); }) { if (!stop.valid()) Fail(); }
    std::string id; std::unique_ptr<Handle> pipe; Handle stop; bool authorized = false;
    std::atomic<bool> closed{false}; FrameReservations frames;
    std::mutex outputMutex, closeMutex; std::condition_variable outputReady; std::deque<std::string> output;
    AuthDenialDelivery denial;
    OwnedIoWorkers workers;
    void Stop() {
      std::lock_guard<std::mutex> lock(closeMutex); closed = true; denial.Fail(); SetEvent(stop.get());
      if (pipe) { CancelIoEx(pipe->get(), nullptr); DisconnectNamedPipe(pipe->get()); } outputReady.notify_all();
    }
    void Join() { workers.Close(); }
    ~Channel() { Join(); }
  };
  std::filesystem::path root; std::string epoch, user, logon, name;
  std::function<void()> notify; Handle stop;
  std::mutex mutex; std::map<std::string, std::shared_ptr<Channel>> channels; std::deque<Event> events;
  std::thread listener; bool published = false;
  uint64_t channelSequence = 0;
  Impl(std::filesystem::path r, std::string e, std::function<void()> n) : root(std::move(r)), epoch(std::move(e)),
    user(Utf8(UserSid())), logon(Utf8(LogonSid())), notify(std::move(n)), stop(CreateEventW(nullptr, TRUE, FALSE, nullptr)) {
    if (!CanonicalUuid(epoch) || !stop.valid()) Fail();
  }
  HANDLE Pipe(bool first) {
    const auto sddl = L"D:P(A;;GA;;;" + Wide(logon) + L")"; PSECURITY_DESCRIPTOR descriptor = nullptr;
    if (!ConvertStringSecurityDescriptorToSecurityDescriptorW(sddl.c_str(), SDDL_REVISION_1, &descriptor, nullptr)) Fail();
    SECURITY_ATTRIBUTES attributes{sizeof(attributes), descriptor, FALSE};
    const auto pipe = CreateNamedPipeW(Wide(name).c_str(), PIPE_ACCESS_DUPLEX | FILE_FLAG_OVERLAPPED | (first ? FILE_FLAG_FIRST_PIPE_INSTANCE : 0),
      PIPE_TYPE_BYTE | PIPE_READMODE_BYTE | PIPE_WAIT | PIPE_REJECT_REMOTE_CLIENTS, 9, 65536, 65536, 0, &attributes);
    LocalFree(descriptor); return pipe;
  }
  std::string ChannelId() {
    if (channelSequence >= 0xffffffffffffULL) Fail();
    char digits[12]{}; char buffer[16]{}; const auto result = std::to_chars(buffer, buffer + sizeof(buffer), ++channelSequence, 16);
    if (result.ec != std::errc()) Fail(); const auto length = static_cast<size_t>(result.ptr - buffer);
    std::fill(std::begin(digits), std::end(digits), '0'); std::copy(buffer, result.ptr, digits + 12 - length);
    auto id = epoch; id.replace(24, 12, digits, 12); return id;
  }
  void Push(Event event, const std::shared_ptr<Channel>& channel = {}) {
    { std::lock_guard<std::mutex> lock(mutex);
      if (channel && channel->closed && event.type != "_mcpStopped") return;
      if (events.size() >= 256) {
        for (const auto& [id, c] : channels) { (void)id; c->Stop(); }
        SetEvent(stop.get()); events.clear(); events.push_back({"mcpUnavailable", {}, {}, {}, {}});
      } else {
      if (channel && event.type == "mcpFrame" && !channel->frames.Admit()) { channel->Stop(); return; }
      events.push_back(std::move(event));
      }
    } notify();
  }
  void Serve(const std::shared_ptr<Channel>& c) {
    try {
      if (!PeerIdentity(c->pipe->get(), false, Wide(user), Wide(logon))) Fail();
      Lines lines;
      auto frame = lines.Read(c->pipe->get(), c->stop.get(), 5000); const auto auth = Decode(frame);
      if (!ClientIdentity(c->pipe->get(), Wide(user), Wide(logon))) Fail();
      Push({"mcpChannelOpened", c->id, {}, user, logon}, c);
      const auto& object = auth.object(); const auto client = auth.at("clientId").string();
      if (object.size() != 6 || auth.at("kind").string() != "auth" || auth.at("version").integer() != 1 ||
          auth.at("ownerEpoch").string() != epoch || !CanonicalUuid(client) || auth.at("grantVersion").integer() < 1 || auth.at("secret").string().size() != 43) Fail();
      Push({"mcpFrame", c->id, frame, {}, {}}, c);
      for (;;) {
        frame = lines.Read(c->pipe->get(), c->stop.get()); const auto value = Decode(frame);
        { std::lock_guard<std::mutex> lock(mutex);
          if (!c->authorized && value.object().size() == 2 && value.at("kind").string() == "authDeniedAcknowledged" &&
              value.at("version").integer() == 1 && c->denial.Acknowledge()) return;
          if (!c->authorized || value.object().size() != 2 || value.at("kind").string() != "mcp") Fail();
        }
        value.at("payload").object(); Push({"mcpFrame", c->id, frame, {}, {}}, c);
      }
    } catch (...) { c->Stop(); Push({"_mcpStopped", c->id, {}, {}, {}}, c); }
  }
  void Write(const std::shared_ptr<Channel>& c) {
    try { for (;;) { std::string frame;
      { std::unique_lock<std::mutex> lock(c->outputMutex); c->outputReady.wait(lock, [&] { return c->closed || !c->output.empty(); });
        if (c->closed) return; frame = std::move(c->output.front()); c->output.pop_front(); }
      WriteLine(c->pipe->get(), c->stop.get(), frame);
    } } catch (...) { c->Stop(); }
  }
  void Accept(HANDLE initial) {
    auto pipe = std::make_unique<Handle>(initial);
    for (;;) {
      Handle connected(CreateEventW(nullptr, TRUE, FALSE, nullptr)); if (!connected.valid()) Fail(); OVERLAPPED operation{}; operation.hEvent = connected.get();
      if (!ConnectNamedPipe(pipe->get(), &operation)) {
        const auto error = GetLastError();
        if (error == ERROR_IO_PENDING) { HANDLE waits[]{stop.get(), connected.get()}; DWORD n = 0;
          if (WaitForMultipleObjects(2, waits, FALSE, INFINITE) != WAIT_OBJECT_0 + 1) { CancelIoEx(pipe->get(), &operation); GetOverlappedResult(pipe->get(), &operation, &n, TRUE); return; }
          if (!GetOverlappedResult(pipe->get(), &operation, &n, FALSE)) Fail();
        } else if (error != ERROR_PIPE_CONNECTED) Fail();
      }
      // Reap confirmed native closures, keeping no detached thread or reused ID.
      std::vector<std::shared_ptr<Channel>> retired;
      { std::lock_guard<std::mutex> lock(mutex); for (auto it = channels.begin(); it != channels.end();) {
        if (it->second->closed) retired.push_back(it->second); ++it; } }
      for (const auto& c : retired) { c->Join(); std::lock_guard<std::mutex> lock(mutex); channels.erase(c->id); }
      if (WaitForSingleObject(stop.get(), 0) == WAIT_OBJECT_0) return;
      { std::lock_guard<std::mutex> lock(mutex); if (channels.size() >= 8) { DisconnectNamedPipe(pipe->get()); continue; } }
      auto next = std::make_unique<Handle>(Pipe(false)); if (!next->valid()) Fail();
      { std::lock_guard<std::mutex> lock(mutex);
        if (channels.size() < 8) {
          const auto id = ChannelId();
          auto c = std::make_shared<Channel>(id, std::move(pipe)); channels.emplace(c->id, c);
          try { c->workers.Start([this, c] { Serve(c); }, [this, c] { Write(c); }); }
          catch (...) { c->Stop(); throw; }
        }
      }
      pipe = std::move(next);
    }
  }
};
Broker::Broker(std::filesystem::path root, std::string epoch, std::function<void()> notify)
  : impl_(std::make_unique<Impl>(std::move(root), std::move(epoch), std::move(notify))) {}
Broker::~Broker() { try { Remove(); } catch (...) {} }
void Broker::Publish() {
  Remove(); auto& s = *impl_; SecureDirectory(s.root / L"mcp"); SecureDirectory(s.root / L"mcp" / L"clients"); ResetEvent(s.stop.get());
  HANDLE first = INVALID_HANDLE_VALUE;
  for (int i = 0; i < 8 && first == INVALID_HANDLE_VALUE; ++i) { auto random = Utf8(Uuid()); random.erase(std::remove(random.begin(), random.end(), '-'), random.end());
    s.name = "\\\\.\\pipe\\EndlessNet.ClientUi.Mcp." + s.epoch + "." + random; first = s.Pipe(true); }
  if (first == INVALID_HANDLE_VALUE) Fail();
  try { s.listener = std::thread([&s, first] { try { s.Accept(first); } catch (...) { SetEvent(s.stop.get()); s.Push({"mcpUnavailable", {}, {}, {}, {}}); } });
    AtomicJson(s.root / L"mcp" / L"owner.json", Json::Object{{"protocolVersion", 1}, {"ownerEpoch", s.epoch}, {"pid", static_cast<int64_t>(GetCurrentProcessId())},
      {"processCreationTime", std::to_string(Creation())}, {"userSid", s.user}, {"logonSid", s.logon}, {"pipeName", s.name}}); s.published = true;
  } catch (...) { if (!s.listener.joinable()) CloseHandle(first); Remove(); throw; }
}
void Broker::Remove() {
  auto& s = *impl_; s.published = false; SetEvent(s.stop.get());
  bool descriptorFailure = false;
  try {
    const auto path = ExtendedPath(s.root / L"mcp" / L"owner.json"); RejectReparse(path);
    if (!DeleteFileW(path.c_str()) && GetLastError() != ERROR_FILE_NOT_FOUND && GetLastError() != ERROR_PATH_NOT_FOUND) descriptorFailure = true;
  } catch (...) { descriptorFailure = true; }
  if (s.listener.joinable()) s.listener.join();
  std::vector<std::shared_ptr<Impl::Channel>> channels;
  { std::lock_guard<std::mutex> lock(s.mutex); for (const auto& [id, c] : s.channels) { (void)id; c->Stop(); channels.push_back(c); } }
  for (const auto& c : channels) c->Join();
  { std::lock_guard<std::mutex> lock(s.mutex); s.channels.clear(); s.events.clear(); }
  if (descriptorFailure) Fail();
}
void Broker::Send(const std::string& id, const std::string& frame) {
  if (!CanonicalUuid(id) || frame.size() + 1 > kFrameBytes || frame.find('\n') != std::string::npos) InvalidJson(); const auto value = Decode(frame);
  auto& s = *impl_; std::shared_ptr<Impl::Channel> c;
  { std::lock_guard<std::mutex> lock(s.mutex); const auto it = s.channels.find(id); if (it == s.channels.end() || it->second->closed) Fail(); c = it->second;
    const auto kind = value.at("kind").string();
    if (!c->authorized) { if (kind == "authorized") { if (value.at("version").integer() != 1) InvalidJson(); c->authorized = true; }
      else {
        if (kind != "error" || value.object().size() != 2 || value.at("code").string() != "AUTH_REQUIRED") InvalidJson();
        c->denial.Queue();
      } }
    else if (kind != "mcp" || value.object().size() != 2) InvalidJson();
  }
  { std::lock_guard<std::mutex> lock(c->outputMutex); if (c->closed || c->output.size() >= 16) { c->Stop(); Fail(); } c->output.push_back(frame); } c->outputReady.notify_one();
}
void Broker::Close(const std::string& id) {
  if (!CanonicalUuid(id)) InvalidJson(); auto& s = *impl_; std::shared_ptr<Impl::Channel> c;
  { std::lock_guard<std::mutex> lock(s.mutex); const auto it = s.channels.find(id); if (it == s.channels.end()) return; c = it->second; }
  // Send acknowledges enqueueing; terminal auth errors additionally require a
  // helper receipt before disconnecting, otherwise Stop could discard the frame.
  c->denial.Await(std::chrono::milliseconds(5000));
  c->Stop(); c->Join(); { std::lock_guard<std::mutex> lock(s.mutex); s.channels.erase(id); }
}
std::vector<Event> Broker::TakeEvents() {
  auto& s = *impl_; std::deque<Event> pending;
  { std::lock_guard<std::mutex> lock(s.mutex); pending.swap(s.events); }
  std::vector<Event> result;
  for (auto& event : pending) {
    if (event.type == "_mcpStopped") { Close(event.channelId); event.type = "mcpChannelClosed"; }
    else if (event.type == "mcpFrame") {
      std::lock_guard<std::mutex> lock(s.mutex); const auto it = s.channels.find(event.channelId);
      if (it == s.channels.end() || it->second->closed) continue;
    }
    result.push_back(std::move(event));
  } return result;
}
void Broker::Acknowledge(const std::string& id) {
  if (!CanonicalUuid(id)) InvalidJson(); auto& s = *impl_; std::lock_guard<std::mutex> lock(s.mutex);
  const auto it = s.channels.find(id); if (it != s.channels.end()) it->second->frames.Acknowledge();
}
void Broker::WriteGrant(const std::string& client, int64_t version, const std::vector<uint8_t>& bytes) {
  if (!CanonicalUuid(client) || version < 1 || version > 9007199254740991LL || bytes.empty() || bytes.size() > 8192) InvalidJson();
  auto& s = *impl_; SecureDirectory(s.root / L"mcp"); SecureDirectory(s.root / L"mcp" / L"clients");
  AtomicJson(s.root / L"mcp" / L"clients" / (Wide(client) + L".grant"), Json::Object{{"version", 1}, {"clientId", client}, {"grantVersion", version}, {"protectedSecret", EncodeBase64(bytes.data(), bytes.size())}});
}
void Broker::DeleteGrant(const std::string& client) {
  if (!CanonicalUuid(client)) InvalidJson(); const auto path = ExtendedPath(impl_->root / L"mcp" / L"clients" / (Wide(client) + L".grant")); RejectReparse(path);
  if (!DeleteFileW(path.c_str()) && GetLastError() != ERROR_FILE_NOT_FOUND && GetLastError() != ERROR_PATH_NOT_FOUND) Fail();
}
namespace {
std::string PrivateRead(const std::filesystem::path& input, size_t maximum) {
  const auto path = ExtendedPath(input); RejectReparse(path);
  Handle file(CreateFileW(path.c_str(), GENERIC_READ | READ_CONTROL, FILE_SHARE_READ | FILE_SHARE_DELETE, nullptr,
    OPEN_EXISTING, FILE_FLAG_OPEN_REPARSE_POINT, nullptr)); if (!file.valid()) Fail();
  FILE_ATTRIBUTE_TAG_INFO attributes{};
  if (!GetFileInformationByHandleEx(file.get(), FileAttributeTagInfo, &attributes, sizeof(attributes)) ||
      (attributes.FileAttributes & (FILE_ATTRIBUTE_REPARSE_POINT | FILE_ATTRIBUTE_DIRECTORY))) Fail();
  PSID owner = nullptr; PACL acl = nullptr; PSECURITY_DESCRIPTOR descriptor = nullptr;
  if (GetSecurityInfo(file.get(), SE_FILE_OBJECT, OWNER_SECURITY_INFORMATION | DACL_SECURITY_INFORMATION,
      &owner, nullptr, &acl, nullptr, &descriptor) != ERROR_SUCCESS) Fail();
  bool valid = false;
  try {
    LPWSTR ownerText = nullptr; if (!owner || !ConvertSidToStringSidW(owner, &ownerText)) Fail();
    const std::wstring ownerSid(ownerText); LocalFree(ownerText); if (!acl) Fail();
    std::vector<std::string> allowedSids;
    for (DWORD i = 0; i < acl->AceCount; ++i) {
      void* raw = nullptr; if (!GetAce(acl, i, &raw)) Fail(); const auto* header = static_cast<ACE_HEADER*>(raw);
      if (header->AceType == ACCESS_DENIED_ACE_TYPE) continue;
      if (header->AceType != ACCESS_ALLOWED_ACE_TYPE) Fail();
      const auto* ace = static_cast<ACCESS_ALLOWED_ACE*>(raw); LPWSTR text = nullptr;
      if (!ConvertSidToStringSidW(const_cast<DWORD*>(&ace->SidStart), &text)) Fail(); const std::wstring sid(text); LocalFree(text);
      allowedSids.push_back(Utf8(sid));
    } valid = PrivateMetadataPolicy(Utf8(UserSid()), Utf8(ownerSid), false, true, allowedSids);
  } catch (...) { LocalFree(descriptor); throw; }
  LocalFree(descriptor); if (!valid) Fail();
  LARGE_INTEGER size{}; if (!GetFileSizeEx(file.get(), &size) || size.QuadPart < 1 || static_cast<uint64_t>(size.QuadPart) > maximum) Fail();
  std::string text(static_cast<size_t>(size.QuadPart), '\0'); DWORD count = 0;
  if (!ReadFile(file.get(), text.data(), static_cast<DWORD>(text.size()), &count, nullptr) || count != text.size()) Fail();
  return text;
}
struct Secret {
  DATA_BLOB data{};
  ~Secret() { if (data.pbData) { SecureZeroMemory(data.pbData, data.cbData); LocalFree(data.pbData); } }
};
void Stderr(const char* message) {
  DWORD n = 0; WriteFile(GetStdHandle(STD_ERROR_HANDLE), message, static_cast<DWORD>(strlen(message)), &n, nullptr);
}
void PlainWrite(HANDLE handle, const std::string& text) {
  size_t offset = 0; while (offset < text.size()) { DWORD n = 0;
    if (!WriteFile(handle, text.data() + offset, static_cast<DWORD>(text.size() - offset), &n, nullptr) || !n) Fail(); offset += n; }
}
}
int RunStdio(const std::string& clientId) {
  if (!CanonicalUuid(clientId)) return 2;
  int failure = 20;
  try {
    const auto root = DataRoot(); std::unique_ptr<Handle> pipe;
    Handle stop(CreateEventW(nullptr, TRUE, FALSE, nullptr)); if (!stop.valid()) Fail(); Lines lines;
    BridgePorts ports;
    ports.userSid = [] { return Utf8(UserSid()); }; ports.logonSid = [] { return Utf8(LogonSid()); };
    ports.readPrivate = [&](const std::string& relative, size_t maximum) { return PrivateRead(root / Wide(relative), maximum); };
    ports.connect = [&](const OwnerDescriptor& owner) {
      if (!WaitNamedPipeW(Wide(owner.pipeName).c_str(), 1000)) Fail();
      pipe = std::make_unique<Handle>(CreateFileW(Wide(owner.pipeName).c_str(), GENERIC_READ | GENERIC_WRITE, 0, nullptr, OPEN_EXISTING,
        FILE_FLAG_OVERLAPPED | SECURITY_SQOS_PRESENT | SECURITY_IDENTIFICATION, nullptr));
      if (!pipe->valid()) Fail();
    };
    ports.verifyPeer = [&](const OwnerDescriptor& owner) { return PeerIdentity(pipe->get(), true, Wide(owner.userSid), Wide(owner.logonSid), owner.pid, owner.creation); };
    ports.unprotect = [](const std::vector<uint8_t>& cipher, const std::string& purpose) {
      DATA_BLOB input{static_cast<DWORD>(cipher.size()), const_cast<BYTE*>(cipher.data())};
      DATA_BLOB entropy{static_cast<DWORD>(purpose.size()), reinterpret_cast<BYTE*>(const_cast<char*>(purpose.data()))}; Secret secret;
      if (!CryptUnprotectData(&input, nullptr, &entropy, nullptr, nullptr, CRYPTPROTECT_UI_FORBIDDEN, &secret.data)) Fail();
      return std::vector<uint8_t>(secret.data.pbData, secret.data.pbData + secret.data.cbData);
    };
    ports.sendFrame = [&](const std::string& frame) { WriteLine(pipe->get(), stop.get(), frame); };
    ports.readFrame = [&] { return lines.Read(pipe->get(), stop.get(), 5000); };
    std::mutex inputMutex;
    std::condition_variable inputReady;
    BridgeFrames input;
    OutputFrames output;
    BridgeOutcome outcome;
    const auto writeOutput = [&](const std::string& text) {
      output.Push(text);
    };
    const auto finish = [&](int value) {
      outcome.Finish(value);
      { std::lock_guard<std::mutex> lock(inputMutex); SetEvent(stop.get()); }
      output.Stop(); inputReady.notify_all();
    };
    IdleBridgePorts idlePorts;
    idlePorts.connect = [&] {
      // Wake always re-verifies current owner, grant and DPAPI. No cached secret.
      pipe.reset(); lines = Lines();
      return AuthenticateBridge(ports, clientId).version;
    };
    idlePorts.disconnect = [&] { pipe.reset(); lines = Lines(); };
    idlePorts.send = ports.sendFrame;
    idlePorts.receive = ports.readFrame;
    idlePorts.output = writeOutput;
    idlePorts.now = [] { return GetTickCount64(); };
    IdleBridge bridge(std::move(idlePorts));
    try { bridge.Connect(); } catch (const BoundaryFailure& error) { failure = error.code; throw; }
    failure = 23;
    const auto cancelStdio = [](std::thread& inputThread, std::thread& outputThread) {
      for (;;) {
        bool running = false;
        for (auto* worker : {&inputThread, &outputThread}) if (worker->joinable() && WaitForSingleObject(worker->native_handle(), 0) != WAIT_OBJECT_0) {
          running = true; CancelSynchronousIo(worker->native_handle());
        }
        if (!running) break;
        HANDLE handles[2]{}; DWORD count = 0;
        if (inputThread.joinable()) handles[count++] = inputThread.native_handle();
        if (outputThread.joinable()) handles[count++] = outputThread.native_handle();
        WaitForMultipleObjects(count, handles, TRUE, 25);
      }
    };
    OwnedIoWorkers workers([&] { finish(0); }, [] {}, cancelStdio);
    try {
      workers.Start([&] {
        try {
          PumpStdioInput([&](char* bytes, size_t count, uint32_t) {
            DWORD n = 0;
            if (!ReadFile(GetStdHandle(STD_INPUT_HANDLE), bytes, static_cast<DWORD>(count), &n, nullptr)) {
              const auto error = GetLastError();
              if (error != ERROR_BROKEN_PIPE && error != ERROR_HANDLE_EOF && error != ERROR_NO_DATA && WaitForSingleObject(stop.get(), 0) != WAIT_OBJECT_0) Fail();
              return size_t{0};
            } return static_cast<size_t>(n);
          }, [&](const std::string& frame) {
            std::lock_guard<std::mutex> lock(inputMutex);
            input.Push(frame); inputReady.notify_one();
          }, writeOutput, [&] { return WaitForSingleObject(stop.get(), 0) == WAIT_OBJECT_0; });
          finish(0);
        } catch (...) { finish(WaitForSingleObject(stop.get(), 0) == WAIT_OBJECT_0 ? 0 : 23); }
      }, [&] {
        try { output.Run([](const std::string& text) { PlainWrite(GetStdHandle(STD_OUTPUT_HANDLE), text + '\n'); }); }
        catch (...) { finish(WaitForSingleObject(stop.get(), 0) == WAIT_OBJECT_0 ? 0 : 23); }
      });
      while (WaitForSingleObject(stop.get(), 0) != WAIT_OBJECT_0) {
        // One worker owns the pipe. Peek does not consume partial frames.
        if (bridge.connected()) {
          DWORD available = 0;
          if (!PeekNamedPipe(pipe->get(), nullptr, 0, nullptr, &available, nullptr)) Fail();
          if (available || lines.HasFrame()) { bridge.Output(lines.Read(pipe->get(), stop.get(), 5000)); continue; }
        }
        std::string frame;
        {
          std::unique_lock<std::mutex> lock(inputMutex);
          if (input.empty()) {
            bridge.Park();
            if (bridge.connected()) inputReady.wait_for(lock, std::chrono::milliseconds(25));
            else inputReady.wait(lock, [&] { return !input.empty() || WaitForSingleObject(stop.get(), 0) == WAIT_OBJECT_0; });
          }
          if (!input.empty()) { frame = input.Pop(); }
        }
        if (!frame.empty()) bridge.Input(frame);
      }
    } catch (const BoundaryFailure& error) { finish(error.code); }
    catch (...) { finish(23); }
    workers.Close();
    if (outcome.code()) Stderr(BridgeFailureMessage(outcome.code()));
    return outcome.code();
  } catch (...) {
    Stderr(BridgeFailureMessage(failure)); return failure;
  }
}
}  // namespace sd::mcp
