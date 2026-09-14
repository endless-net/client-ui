#ifndef RUNNER_UI_TRAY_HOST_H_
#define RUNNER_UI_TRAY_HOST_H_

#include <cstdint>

// Readiness is local to one UI host. TaskbarCreated can also accompany a DPI
// change; either way old icon registration is no longer trusted. The shell
// shows the main window instead of assuming that the plugin restored its icon.
class UiTrayHostState {
 public:
  void Initialize(std::uint32_t restart_message) {
    restart_message_ = restart_message;
    invalidated_ = false;
  }

  void OnMessage(std::uint32_t message) {
    if (restart_message_ != 0 && message == restart_message_) {
      invalidated_ = true;
    }
  }

  bool Available(bool shell_present) const {
    return restart_message_ != 0 && shell_present && !invalidated_;
  }

 private:
  std::uint32_t restart_message_ = 0;
  bool invalidated_ = false;
};

#endif  // RUNNER_UI_TRAY_HOST_H_
