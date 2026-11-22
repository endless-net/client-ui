#include "mcp_pipe.h"
#include "mcp_boundary.h"

#include <bcrypt.h>
#include <wincrypt.h>
#include <array>

namespace {
using sd::mcp::Broker;
using sd::mcp::Json;

struct Owner {
  std::filesystem::path root = sd::DataRoot();
  sd::Handle lock{CreateFileW((root / L"owner.lock").c_str(),
      GENERIC_READ | GENERIC_WRITE | WRITE_DAC | READ_CONTROL, 0, nullptr,
      OPEN_ALWAYS, FILE_FLAG_OPEN_REPARSE_POINT, nullptr)};
  std::string id = sd::Utf8(sd::Uuid());
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
    broker = std::make_unique<Broker>(root, sd::Utf8(sd::Uuid()), [] {});
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
    auto purpose = "mcp-grant.v1:" + id;
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
    secret = sd::mcp::EncodeBase64(random.bytes.data(), random.bytes.size(), true);
    const auto* bytes = encrypted.value.pbData;
    broker->WriteGrant(id, 1, {bytes, bytes + encrypted.value.cbData});
    broker->Publish();
  }

  bool Authorize(const Json& frame) const {
    const auto& input = frame.at("secret").string();
    if (frame.at("clientId").string() != id ||
        frame.at("grantVersion").integer() != 1 || input.size() != secret.size()) {
      return false;
    }
    unsigned char diff = 0;
    for (size_t i = 0; i < secret.size(); ++i) {
      diff |= static_cast<unsigned char>(secret[i] ^ input[i]);
    }
    return diff == 0;
  }

  ~Owner() {
    if (!secret.empty()) SecureZeroMemory(secret.data(), secret.size());
    if (!broker) return;
    try { broker->Remove(); } catch (...) {}
    try { broker->DeleteGrant(id); } catch (...) {}
  }
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

extern "C" __declspec(dllexport) void en_mcp_disable() {
  delete owner;
  owner = nullptr;
}

extern "C" __declspec(dllexport) const char* en_mcp_enable() {
  try {
    en_mcp_disable();
    auto next = std::make_unique<Owner>();
    next->Enable();
    owner = next.release();
    return owner->id.c_str();
  } catch (...) {
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
                  {"kind", "authorized"}, {"version", 1}, {"grantVersion", 1}}));
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
