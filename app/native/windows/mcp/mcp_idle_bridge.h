#pragma once
#include "mcp_boundary.h"
#include <optional>
#include <set>
#include <condition_variable>
#include <deque>

namespace sd::mcp {
// Zero is a settled clean EOF, not the absence of a failure. Cancellation IO
// errors arriving after EOF must not overwrite that first termination reason.
class BridgeOutcome {
 public:
  void Finish(int code) { int expected = -1; code_.compare_exchange_strong(expected, code); }
  int code() const { return code_.load(); }
 private:
  std::atomic<int> code_{-1};
};
// The caller locks input queues; OutputFrames owns its own lock. Limits include
// the newline and apply to queued bytes, not just the number of frames.
class BridgeFrames {
 public:
  bool empty() const { return frames_.empty(); }
  void Push(const std::string& frame) {
    if (frames_.size() >= 16 || frame.size() + 1 > kFrameBytes - bytes_) throw BoundaryFailure{23};
    frames_.push_back(frame); bytes_ += frame.size() + 1;
  }
  std::string Pop() {
    auto frame = std::move(frames_.front()); frames_.pop_front(); bytes_ -= frame.size() + 1; return frame;
  }
  void Clear() { frames_.clear(); bytes_ = 0; }
 private:
  std::deque<std::string> frames_;
  size_t bytes_ = 0;
};
class OutputFrames {
 public:
  void Push(const std::string& frame) {
    std::lock_guard<std::mutex> lock(mutex_);
    if (stopped_) return;
    frames_.Push(frame); ready_.notify_one();
  }
  void Stop() {
    std::lock_guard<std::mutex> lock(mutex_);
    stopped_ = true; frames_.Clear(); ready_.notify_all();
  }
  void Run(const std::function<void(const std::string&)>& write) {
    for (;;) {
      std::string frame;
      {
        std::unique_lock<std::mutex> lock(mutex_);
        ready_.wait(lock, [&] { return stopped_ || !frames_.empty(); });
        if (stopped_) return;
        frame = frames_.Pop();
      }
      // Never hold the queue lock across externally blocked/cancellable IO.
      write(frame);
    }
  }
 private:
  std::mutex mutex_;
  std::condition_variable ready_;
  BridgeFrames frames_;
  bool stopped_ = false;
};
// Only protocol initialization is retained across idle parking. Domain commands
// and their results are never cached or replayed by this transport.
struct IdleBridgePorts {
  std::function<int64_t()> connect;
  std::function<void()> disconnect;
  std::function<void(const std::string&)> send, output;
  std::function<std::string()> receive;
  std::function<uint64_t()> now;
};
class IdleBridge {
 public:
  static constexpr uint64_t idleMs = 300000;
  explicit IdleBridge(IdleBridgePorts ports) : ports_(std::move(ports)) {}
  void Connect() {
    const auto version = ports_.connect();
    if (grantVersion_ && grantVersion_ != version) throw BoundaryFailure{22};
    grantVersion_ = version; connected_ = true; Touch();
  }
  bool connected() const { return connected_; }
  bool Park() {
    if (!connected_ || !pending_.empty() || ports_.now() - lastActivity_ < idleMs) return false;
    // A half-initialized client cannot be transparently resumed.
    if (!initialized_) throw BoundaryFailure{23};
    ports_.disconnect(); connected_ = false; return true;
  }
  void Input(const std::string& envelope) {
    Touch();
    const auto payload = Decode(envelope).at("payload");
    const auto& object = payload.object();
    const auto request = Request(object);
    if (request && seen_.count(*request)) {
      ports_.output(Encode(Json::Object{{"jsonrpc","2.0"},{"id",object.at("id")},
        {"error",Json::Object{{"code",-32600},{"message","INVALID_REQUEST"}}}})); return;
    }
    if (request && seen_.size() >= 10000) {
      ports_.output(Encode(Json::Object{{"jsonrpc","2.0"},{"id",object.at("id")},
        {"error",Json::Object{{"code",-32000},{"message","SESSION_LIMIT"}}}})); throw BoundaryFailure{23};
    }
    if (!connected_) Resume();
    if (request) {
      if (pending_.size() >= 16) throw BoundaryFailure{23};
      seen_.insert(*request); pending_.insert(*request);
      if (object.at("method").string() == "initialize") {
        if (envelope.size() + 1 > kFrameBytes - initializationBytes_) throw BoundaryFailure{23};
        initializationRequests_[*request] = envelope; initializationBytes_ += envelope.size() + 1;
      }
    }
    ports_.send(envelope);
    if (ValidFrame(object) && !object.count("id") && object.count("method") &&
        std::holds_alternative<std::string>(object.at("method").value) &&
        object.at("method").string() == "notifications/initialized" && !initialization_.empty()) initialized_ = true;
  }
  void Output(const std::string& envelope) {
    Touch();
    const auto payload = Unwrap(envelope);
    const auto& object = payload.object();
    if (object.count("id")) {
      const auto key = Id(object.at("id"));
      if (key) {
        pending_.erase(*key);
        const auto init = initializationRequests_.find(*key);
        if (init != initializationRequests_.end()) {
          if (object.count("result")) {
            signature_ = Signature(payload); initialization_ = init->second;
          }
          initializationBytes_ -= init->second.size() + 1;
          initializationRequests_.erase(init);
        }
      }
    }
    ports_.output(Encode(payload));
  }
 private:
  IdleBridgePorts ports_;
  bool connected_ = false, initialized_ = false;
  uint64_t lastActivity_ = 0;
  int64_t grantVersion_ = 0;
  std::set<std::string> seen_, pending_;
  std::map<std::string, std::string> initializationRequests_;
  size_t initializationBytes_ = 0;
  std::string initialization_, signature_;
  void Touch() { lastActivity_ = ports_.now(); }
  static Json Unwrap(const std::string& envelope) {
    const auto frame = Decode(envelope);
    if (frame.object().size() != 2 || frame.at("kind").string() != "mcp") InvalidJson();
    frame.at("payload").object(); return frame.at("payload");
  }
  static std::string Signature(const Json& response) {
    const auto& result = response.at("result");
    return Encode(Json::Object{{"protocolVersion",result.at("protocolVersion")},{"capabilities",result.at("capabilities")}});
  }
  static std::optional<std::string> Id(const Json& id) {
    if (const auto* value = std::get_if<std::string>(&id.value)) {
      size_t units = 0;
      for (const auto c : *value) { const auto byte = static_cast<unsigned char>(c); if ((byte & 0xc0) != 0x80) units += byte >= 0xf0 ? 2 : 1; }
      if (units <= 128) return "s" + *value;
    }
    double number = 0;
    if (const auto* integer = std::get_if<int64_t>(&id.value)) number = static_cast<double>(*integer);
    else if (const auto* real = std::get_if<double>(&id.value)) number = *real;
    else return std::nullopt;
    if (std::isfinite(number) && std::abs(number) <= 9007199254740991.0 && std::trunc(number) == number)
      return "n" + std::to_string(static_cast<int64_t>(number));
    return std::nullopt;
  }
  static bool ValidFrame(const Json::Object& object) {
    if (!object.count("jsonrpc") || Encode(object.at("jsonrpc")) != "\"2.0\"" ||
        !object.count("method") || !std::holds_alternative<std::string>(object.at("method").value)) return false;
    for (const auto& [key, value] : object) {
      if (key != "jsonrpc" && key != "method" && key != "id" && key != "params") return false;
      if (key == "params" && !std::holds_alternative<Json::Object>(value.value)) return false;
    }
    return true;
  }
  static std::optional<std::string> Request(const Json::Object& object) {
    if (!ValidFrame(object) || !object.count("id")) return std::nullopt;
    return Id(object.at("id"));
  }
  void Resume() {
    Connect();
    ports_.send(initialization_);
    const auto response = Unwrap(ports_.receive());
    const auto original = Decode(initialization_).at("payload");
    if (Encode(response.at("id")) != Encode(original.at("id")) || Signature(response) != signature_) throw BoundaryFailure{23};
    ports_.send(Encode(Json::Object{{"kind","mcp"},{"payload",Json::Object{{"jsonrpc","2.0"},{"method","notifications/initialized"}}}}));
  }
};
}  // namespace sd::mcp
