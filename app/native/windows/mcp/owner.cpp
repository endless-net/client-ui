#include "mcp_pipe.h"
#include "mcp_boundary.h"

#include <bcrypt.h>
#include <wincrypt.h>
#include <array>

namespace {
using sd::mcp::Broker;
using sd::mcp::Json;

struct Owner {
  std::filesystem::path root = sd::UserDataRoot();
  sd::Handle lock{CreateFileW(sd::ExtendedPath(root / L"grant.lock").c_str(),
      GENERIC_READ | GENERIC_WRITE | WRITE_DAC | READ_CONTROL, 0, nullptr,
      OPEN_ALWAYS, FILE_FLAG_OPEN_REPARSE_POINT, nullptr)};
  std::string id;
  int64_t grantVersion = 0;
  std::string secret;
  std::unique_ptr<Broker> broker;

  Owner() {
    if (!lock.valid()) throw std::runtime_error("MCP_OWNER_BUSY");
    FILE_ATTRIBUTE_TAG_INFO info{};
    if (!GetFileInformationByHandleEx(lock.get(), FileAttributeTagInfo, &info, sizeof(info)) ||
        (info.FileAttributes & (FILE_ATTRIBUTE_REPARSE_POINT | FILE_ATTRIBUTE_DIRECTORY))) {
      throw std::runtime_error("MCP_OWNER_UNAVAILABLE");
    }
    sd::SecureFileHandle(lock.get());
  }

  bool Restore() {
    const auto grant = sd::mcp::ReadGrant(root);
    if (!grant) return false;
    const auto& client = grant->at("clientId").string();
    const auto version = sd::mcp::ValidateGrant(*grant, client);
    const auto cipher = sd::mcp::DecodeBase64(grant->at("protectedSecret").string(), 8192);
    struct Cleartext {
      std::vector<uint8_t> bytes;
      ~Cleartext() { sd::mcp::Wipe(bytes); }
    } clear{sd::mcp::UnprotectGrant(cipher, sd::mcp::GrantPurpose(client))};
    if (clear.bytes.size() != 32) sd::mcp::InvalidJson();
    Start(client, version, clear.bytes.data(), clear.bytes.size());
    return true;
  }

  void Enable() {
    struct Secret {
      std::array<BYTE, 32> bytes{};
      ~Secret() { SecureZeroMemory(bytes.data(), bytes.size()); }
    } random;
    if (BCryptGenRandom(nullptr, random.bytes.data(),
                        static_cast<ULONG>(random.bytes.size()),
                        BCRYPT_USE_SYSTEM_PREFERRED_RNG) != 0) {
      throw std::runtime_error("MCP_GRANT_UNAVAILABLE");
    }
    const auto client = sd::Utf8(sd::Uuid());
    auto purpose = sd::mcp::GrantPurpose(client);
    DATA_BLOB input{static_cast<DWORD>(random.bytes.size()), random.bytes.data()};
    DATA_BLOB entropy{static_cast<DWORD>(purpose.size()),
                      reinterpret_cast<BYTE*>(purpose.data())};
    struct Protected {
      DATA_BLOB value{};
      ~Protected() { LocalFree(value.pbData); }
    } encrypted;
    if (!CryptProtectData(&input, nullptr, &entropy, nullptr, nullptr,
                          CRYPTPROTECT_UI_FORBIDDEN, &encrypted.value)) {
      throw std::runtime_error("MCP_GRANT_UNAVAILABLE");
    }
    sd::mcp::WriteGrant(root, Json::Object{
        {"version", 1}, {"clientId", client}, {"grantVersion", 1},
        {"protectedSecret", sd::mcp::EncodeBase64(encrypted.value.pbData, encrypted.value.cbData)}});
    Start(client, 1, random.bytes.data(), random.bytes.size());
  }

  void Revoke() {
    sd::mcp::WriteGrant(root, Json::Object{{"version", 1}, {"revoked", 1}});
  }

  void Start(const std::string& client, int64_t version,
             const uint8_t* bytes, size_t size) {
    broker.reset();
    sd::mcp::Wipe(secret);
    secret = sd::mcp::EncodeBase64(bytes, size, true);
    id = client;
    grantVersion = version;
    broker = std::make_unique<Broker>(sd::SessionDataRoot(root), sd::Utf8(sd::Uuid()), [] {});
    broker->Publish();
  }

  bool Authorize(const Json& frame) const {
    const auto& input = frame.at("secret").string();
    if (frame.at("clientId").string() != id ||
        frame.at("grantVersion").integer() != grantVersion || input.size() != secret.size()) {
      return false;
    }
    unsigned char diff = 0;
    for (size_t i = 0; i < secret.size(); ++i) {
      diff |= static_cast<unsigned char>(secret[i] ^ input[i]);
    }
    return diff == 0;
  }

  ~Owner() { sd::mcp::Wipe(secret); }
};

// Only the Flutter platform isolate calls these owner functions. The bridge
// runs in a separate process and owns no UI controller or SDK connection.
// Destruction joins workers and belongs to the UI lifecycle, never DLL detach.
Owner* owner = nullptr;
std::string events;
}

extern "C" __declspec(dllexport) int en_mcp_stdio(const char* client_id) {
  return sd::mcp::RunStdio(client_id);
}

extern "C" __declspec(dllexport) void en_mcp_stop() {
  delete owner;
  owner = nullptr;
}

extern "C" __declspec(dllexport) const char* en_mcp_restore() {
  try {
    if (owner) return owner->id.c_str();
    auto next = std::make_unique<Owner>();
    if (!next->Restore()) return "";
    owner = next.release();
    return owner->id.c_str();
  } catch (...) {
    return nullptr;
  }
}

extern "C" __declspec(dllexport) int en_mcp_disable() {
  try {
    if (owner) {
      owner->Revoke();
      en_mcp_stop();
    } else {
      Owner inactive;
      inactive.Revoke();
    }
    return 1;
  } catch (...) {
    return 0;
  }
}

extern "C" __declspec(dllexport) const char* en_mcp_enable() {
  try {
    if (owner) {
      owner->Enable();
    } else {
      auto next = std::make_unique<Owner>();
      next->Enable();
      owner = next.release();
    }
    return owner->id.c_str();
  } catch (...) {
    en_mcp_stop();
    return nullptr;
  }
}

extern "C" __declspec(dllexport) int en_mcp_active() {
  return owner != nullptr;
}

extern "C" __declspec(dllexport) const char* en_mcp_events() {
  if (!en_mcp_active()) return nullptr;
  try {
    events = "[";
    for (const auto& event : owner->broker->TakeEvents()) {
      if (event.type == "mcpUnavailable") return nullptr;
      if (event.type == "mcpChannelOpened") continue;
      std::string payload = "null";
      if (event.type == "mcpFrame") {
        owner->broker->Acknowledge(event.channelId);
        try {
          const auto frame = sd::mcp::Decode(event.frame);
          if (frame.at("kind").string() == "auth") {
            if (owner->Authorize(frame)) {
              owner->broker->Send(event.channelId, sd::mcp::Encode(Json::Object{
                  {"kind", "authorized"}, {"version", 1}, {"grantVersion", owner->grantVersion}}));
            } else {
              owner->broker->Close(event.channelId);
            }
            continue;
          }
          payload = sd::mcp::Encode(frame.at("payload"));
        } catch (...) {
          owner->broker->Close(event.channelId);
          continue;
        }
      }
      if (events.size() > 1) events += ',';
      events += "{\"channel\":\"" + event.channelId + "\",\"payload\":" + payload + "}";
    }
    events += ']';
    return events.c_str();
  } catch (...) {
    return nullptr;
  }
}

extern "C" __declspec(dllexport) void en_mcp_send(const char* channel, const char* frame) {
  if (!en_mcp_active()) return;
  try {
    owner->broker->Send(channel, frame);
  } catch (...) {
    try { owner->broker->Close(channel); } catch (...) {}
  }
}
