#pragma once
#include "mcp_json.h"
#include <algorithm>
#include <atomic>
#include <functional>
#include <mutex>
#include <thread>
#include <condition_variable>
#include <chrono>

namespace sd::mcp {
struct BoundaryFailure { int code; };
struct EndOfStream {};
class AuthDenialDelivery {
 public:
  void Queue() { std::lock_guard<std::mutex> lock(mutex_); queued_ = true; }
  bool Acknowledge() {
    std::lock_guard<std::mutex> lock(mutex_);
    if (!queued_ || failed_) return false;
    acknowledged_ = true; ready_.notify_all(); return true;
  }
  void Fail() { std::lock_guard<std::mutex> lock(mutex_); failed_ = true; ready_.notify_all(); }
  bool Await(std::chrono::milliseconds timeout) {
    std::unique_lock<std::mutex> lock(mutex_);
    if (!queued_) return true;
    ready_.wait_for(lock, timeout, [&] { return acknowledged_ || failed_; });
    return acknowledged_;
  }
 private:
  std::mutex mutex_;
  std::condition_variable ready_;
  bool queued_ = false, acknowledged_ = false, failed_ = false;
};
inline const char* BridgeFailureMessage(int code) {
  switch (code) {
    case 20: return "APP_UNAVAILABLE\n";
    case 21: return "PEER_REJECTED\n";
    case 22: return "AUTH_REQUIRED\n";
    default: return "MCP_PROTOCOL\n";
  }
}
class FrameReservations {
 public:
  bool Admit() { if (count_ >= 16) return false; ++count_; return true; }
  bool Acknowledge() { if (!count_) return false; --count_; return true; }
  size_t count() const { return count_; }
 private:
  size_t count_ = 0;
};
inline void Wipe(std::string& value) { volatile char* p = value.empty() ? nullptr : &value[0]; for (size_t i = 0; i < value.size(); ++i) p[i] = 0; }
inline void Wipe(std::vector<uint8_t>& value) { volatile uint8_t* p = value.empty() ? nullptr : value.data(); for (size_t i = 0; i < value.size(); ++i) p[i] = 0; }
inline std::string EncodeBase64(const uint8_t* data, size_t length, bool url = false) {
  constexpr char alphabet[] = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"; std::string out;
  for (size_t i = 0; i < length; i += 3) {
    const uint32_t v = (static_cast<uint32_t>(data[i]) << 16) | (i + 1 < length ? static_cast<uint32_t>(data[i + 1]) << 8 : 0) | (i + 2 < length ? data[i + 2] : 0);
    out += alphabet[(v >> 18) & 63]; out += alphabet[(v >> 12) & 63]; out += i + 1 < length ? alphabet[(v >> 6) & 63] : '='; out += i + 2 < length ? alphabet[v & 63] : '=';
  }
  if (url) { for (auto& c : out) { if (c == '+') c = '-'; else if (c == '/') c = '_'; } while (!out.empty() && out.back() == '=') out.pop_back(); } return out;
}
inline std::vector<uint8_t> DecodeBase64(const std::string& text, size_t maximum) {
  if (text.empty() || text.size() % 4 || text.size() > ((maximum + 2) / 3) * 4) InvalidJson();
  const std::string alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"; std::vector<uint8_t> out;
  for (size_t i = 0; i < text.size(); i += 4) {
    uint32_t bits = 0; size_t padding = 0;
    for (size_t n = 0; n < 4; ++n) { const auto c = text[i + n]; if (c == '=') { if (n < 2 || i + 4 != text.size()) InvalidJson(); ++padding; bits <<= 6; }
      else { if (padding) InvalidJson(); const auto index = alphabet.find(c); if (index == std::string::npos) InvalidJson(); bits = (bits << 6) | static_cast<uint32_t>(index); } }
    out.push_back(static_cast<uint8_t>(bits >> 16)); if (padding < 2) out.push_back(static_cast<uint8_t>(bits >> 8)); if (!padding) out.push_back(static_cast<uint8_t>(bits));
  }
  if (out.size() > maximum || EncodeBase64(out.data(), out.size()) != text) InvalidJson(); return out;
}
struct OwnerDescriptor {
  std::string epoch, pipeName, userSid, logonSid; uint32_t pid = 0; uint64_t creation = 0;
};
inline OwnerDescriptor ReadOwner(const std::string& text, const std::string& user, const std::string& logon) {
  const auto value = Decode(text); OwnerDescriptor owner;
  owner.epoch = value.at("ownerEpoch").string(); owner.pipeName = value.at("pipeName").string();
  owner.userSid = value.at("userSid").string(); owner.logonSid = value.at("logonSid").string();
  const auto pid = value.at("pid").integer(); const auto creation = value.at("processCreationTime").string();
  const auto result = std::from_chars(creation.data(), creation.data() + creation.size(), owner.creation);
  const auto prefix = "\\\\.\\pipe\\EndlessNet.ClientUi.Mcp." + owner.epoch + ".";
  if (value.at("protocolVersion").integer() != 1 || !CanonicalUuid(owner.epoch) || pid < 1 || pid > UINT32_MAX || !owner.creation ||
      result.ec != std::errc() || result.ptr != creation.data() + creation.size() || std::to_string(owner.creation) != creation ||
      owner.userSid != user || owner.logonSid != logon || owner.pipeName.size() != prefix.size() + 32 ||
      owner.pipeName.compare(0, prefix.size(), prefix) || owner.pipeName.find_first_not_of("0123456789abcdef", prefix.size()) != std::string::npos) InvalidJson();
  owner.pid = static_cast<uint32_t>(pid); return owner;
}
inline bool PrivateMetadataPolicy(const std::string& expectedUser, const std::string& owner, bool reparse,
                                  bool daclPresent, const std::vector<std::string>& allowedSids) {
  if (reparse || !daclPresent || expectedUser != owner) return false;
  for (const auto& sid : allowedSids) if (sid != expectedUser && sid != "S-1-5-18" && sid != "S-1-5-32-544") return false;
  return true;
}
struct BridgePorts {
  std::function<std::string()> userSid, logonSid;
  std::function<std::string()> readOwner;
  std::function<Json()> readGrant;
  std::function<void(const OwnerDescriptor&)> connect;
  std::function<bool(const OwnerDescriptor&)> verifyPeer;
  std::function<std::vector<uint8_t>(const std::vector<uint8_t>&, const std::string&)> unprotect;
  std::function<void(const std::string&)> sendFrame;
  std::function<std::string()> readFrame;
};
inline std::string GrantPurpose(const std::string& client) {
  return "mcp-grant.v1:" + client;
}
inline int64_t ValidateGrant(const Json& grant, const std::string& client) {
  const auto version = grant.at("grantVersion").integer();
  if (grant.at("version").integer() != 1 || grant.at("clientId").string() != client ||
      !CanonicalUuid(client) || version < 1 || version > 9007199254740991LL) InvalidJson();
  return version;
}
inline int64_t AuthenticateBridge(BridgePorts& ports, const std::string& client) {
  int failure = 20; std::vector<uint8_t> cipher, secret; std::string auth;
  try {
    if (!CanonicalUuid(client)) throw BoundaryFailure{2};
    const auto owner = ReadOwner(ports.readOwner(), ports.userSid(), ports.logonSid());
    ports.connect(owner); failure = 21;
    if (!ports.verifyPeer(owner)) throw BoundaryFailure{21};
    failure = 22;
    const auto grant = ports.readGrant();
    const auto version = ValidateGrant(grant, client);
    cipher = DecodeBase64(grant.at("protectedSecret").string(), 8192); secret = ports.unprotect(cipher, GrantPurpose(client)); Wipe(cipher);
    if (secret.size() != 32) InvalidJson();
    Json::Object frame{{"kind", "auth"}, {"version", 1}, {"ownerEpoch", owner.epoch}, {"clientId", client}, {"grantVersion", version}, {"secret", EncodeBase64(secret.data(), secret.size(), true)}};
    auth = Encode(frame); Wipe(std::get<std::string>(frame.at("secret").value)); Wipe(secret);
    failure = 23; ports.sendFrame(auth); Wipe(auth);
    const auto accepted = Decode(ports.readFrame());
    if (accepted.object().size() == 2 && accepted.at("kind").string() == "error" && accepted.at("code").string() == "AUTH_REQUIRED") {
      // The server closes only after this receipt acknowledgment or its bounded
      // deadline. A failed ACK cannot erase the explicit denial already read.
      try { ports.sendFrame(Encode(Json::Object{{"kind","authDeniedAcknowledged"},{"version",1}})); } catch (...) {}
      throw BoundaryFailure{22};
    }
    if (accepted.object().size() != 3 || accepted.at("kind").string() != "authorized" || accepted.at("version").integer() != 1) InvalidJson();
    const auto acceptedVersion = accepted.at("grantVersion").integer();
    if (acceptedVersion < 1 || acceptedVersion > 9007199254740991LL) InvalidJson();
    if (acceptedVersion != version) throw BoundaryFailure{22};
    return version;
  } catch (const BoundaryFailure&) { Wipe(cipher); Wipe(secret); Wipe(auth); throw; }
  catch (...) { Wipe(cipher); Wipe(secret); Wipe(auth); throw BoundaryFailure{failure}; }
}
enum class ClientPeerResult { allowed, denied, revertFailed };
struct ClientPeerPorts {
  std::function<bool()> processIdentity, impersonate, revert;
  std::function<std::pair<std::string,std::string>()> tokenIdentity;
};
inline ClientPeerResult VerifyClientPeer(ClientPeerPorts& ports, const std::string& user, const std::string& logon) {
  try { if (!ports.processIdentity() || !ports.impersonate()) return ClientPeerResult::denied; } catch (...) { return ClientPeerResult::denied; }
  bool allowed = false;
  try { const auto token = ports.tokenIdentity(); allowed = token.first == user && token.second == logon; } catch (...) {}
  try { if (!ports.revert()) return ClientPeerResult::revertFailed; } catch (...) { return ClientPeerResult::revertFailed; }
  return allowed ? ClientPeerResult::allowed : ClientPeerResult::denied;
}
using ReadFrameBytes = std::function<size_t(char*,size_t,uint32_t)>;
using WriteFrameBytes = std::function<size_t(const char*,size_t)>;
class FrameReader {
 public:
  explicit FrameReader(std::function<uint64_t()> now) : now_(std::move(now)) {}
  bool HasFrame() const { return buffer_.HasFrame(); }
  std::string Read(const ReadFrameBytes& read, uint32_t timeout = UINT32_MAX) {
    const auto start = now_();
    for (;;) { std::string frame; if (buffer_.Take(frame)) return frame; if (!buffer_.capacity()) InvalidJson();
      const auto elapsed = now_() - start; if (timeout != UINT32_MAX && elapsed >= timeout) throw BoundaryFailure{23};
      char bytes[4096]; const auto requested = std::min(sizeof(bytes), buffer_.capacity());
      const auto count = read(bytes, requested, timeout == UINT32_MAX ? UINT32_MAX : timeout - static_cast<uint32_t>(elapsed));
      if (!count) throw EndOfStream{}; if (count > requested) InvalidJson(); buffer_.Push(bytes, count);
    }
  }
 private:
  LineBuffer buffer_; std::function<uint64_t()> now_;
};
inline void WriteFrame(const std::string& text, const WriteFrameBytes& write) {
  if (text.size() + 1 > kFrameBytes || text.find('\n') != std::string::npos) InvalidJson(); auto line = text + '\n';
  try { size_t offset = 0; while (offset < line.size()) { const auto remaining = line.size() - offset; const auto n = write(line.data() + offset, remaining);
      if (!n) throw EndOfStream{}; if (n > remaining) InvalidJson(); offset += n; } } catch (...) { Wipe(line); throw; } Wipe(line);
}
inline void PumpStdioInput(const ReadFrameBytes& read, const std::function<void(const std::string&)>& send,
                           const std::function<void(const std::string&)>& output, const std::function<bool()>& stopped) {
  std::string pending; char bytes[4096];
  for (;;) { if (stopped()) return; const auto count = read(bytes, sizeof(bytes), UINT32_MAX);
    if (count > sizeof(bytes)) InvalidJson(); if (!count) { if (!pending.empty()) throw BoundaryFailure{23}; return; }
    for (size_t i = 0; i < count; ++i) {
      if (bytes[i] != '\n') { if (pending.size() >= kFrameBytes - 1) InvalidJson(); pending += bytes[i]; continue; }
      if (!pending.empty() && pending.back() == '\r') pending.pop_back(); Json payload; bool parsed = false;
      try { payload = Decode(pending); parsed = true; } catch (...) {}
      if (!parsed || !std::holds_alternative<Json::Object>(payload.value)) {
        output(Encode(Json::Object{{"jsonrpc", "2.0"}, {"error", Json::Object{{"code", parsed ? -32600 : -32700}, {"message", parsed ? "INVALID_REQUEST" : "PARSE_ERROR"}}}}));
      } else send(Encode(Json::Object{{"kind", "mcp"}, {"payload", payload}}));
      pending.clear();
    }
  }
}
inline void PumpStdioOutput(const std::function<std::string()>& receive, const std::function<void(const std::string&)>& output) {
  for (;;) { std::string frame; try { frame = receive(); } catch (const EndOfStream&) { return; }
    const auto value = Decode(frame); if (value.object().size() != 2 || value.at("kind").string() != "mcp") InvalidJson(); value.at("payload").object();
    output(Encode(value.at("payload")));
  }
}
// Used by native channels: exact worker acknowledgments precede handle release.
class OwnedIoWorkers {
 public:
  using BeforeJoin = std::function<void(std::thread&,std::thread&)>;
  OwnedIoWorkers(std::function<void()> cancel, std::function<void()> release, BeforeJoin beforeJoin = {})
    : cancel_(std::move(cancel)), release_(std::move(release)), beforeJoin_(std::move(beforeJoin)) {}
  ~OwnedIoWorkers() { Close(); }
  void Start(std::function<void()> reader, std::function<void()> writer) {
    writer_ = std::thread(std::move(writer));
    try { reader_ = std::thread(std::move(reader)); } catch (...) { cancel_(); if (beforeJoin_) beforeJoin_(reader_,writer_); writer_.join(); throw; }
  }
  void Close() {
    cancel_(); std::lock_guard<std::mutex> lock(mutex_);
    if (beforeJoin_ && (reader_.joinable() || writer_.joinable())) beforeJoin_(reader_,writer_);
    if (reader_.joinable()) reader_.join(); if (writer_.joinable()) writer_.join();
    if (!released_) { release_(); released_ = true; }
  }
 private:
  std::function<void()> cancel_, release_; BeforeJoin beforeJoin_; std::thread reader_,writer_; std::mutex mutex_; bool released_ = false;
};
}  // namespace sd::mcp
