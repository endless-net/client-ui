#pragma once
#include "mcp_json.h"
#include "security.h"
#include <functional>
#include <memory>
#include <optional>

namespace sd::mcp {
struct Event {
  std::string type, channelId, frame, userSid, logonSid;
};
class Broker {
 public:
  Broker(std::filesystem::path root, std::string epoch, std::function<void()> notify);
  ~Broker();
  Broker(const Broker&) = delete;
  Broker& operator=(const Broker&) = delete;
  void Publish();
  void Remove();
  void Send(const std::string& channelId, const std::string& frame);
  void Close(const std::string& channelId);
  void Acknowledge(const std::string& channelId);
  std::vector<Event> TakeEvents();
 private:
  struct Impl;
  std::unique_ptr<Impl> impl_;
};
std::optional<Json> ReadGrant(const std::filesystem::path& userRoot);
void WriteGrant(const std::filesystem::path& userRoot, const Json& grant);
std::vector<uint8_t> UnprotectGrant(const std::vector<uint8_t>& cipher,
                                    const std::string& purpose);
int RunStdio(const std::string& clientId);
}  // namespace sd::mcp
