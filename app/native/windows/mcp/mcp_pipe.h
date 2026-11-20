#pragma once
#include "mcp_json.h"
#include "security.h"
#include <functional>
#include <memory>

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
  void WriteGrant(const std::string& clientId, int64_t version, const std::vector<uint8_t>& bytes);
  void DeleteGrant(const std::string& clientId);
 private:
  struct Impl;
  std::unique_ptr<Impl> impl_;
};
int RunStdio(const std::string& clientId);
}  // namespace sd::mcp
