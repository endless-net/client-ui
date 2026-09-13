#ifndef ENDLESSNET_NOTIFICATION_ACTIVATIONS_H_
#define ENDLESSNET_NOTIFICATION_ACTIVATIONS_H_

#include <algorithm>
#include <deque>
#include <gio/gio.h>

// Bounded receipt IDs only. No account, profile, body, URL or executable action.
class NotificationActivations {
 public:
  void remember(guint32 id) {
    if (id == 0) return;
    forget(id);
    ids_.push_back(id);
    if (ids_.size() > 64) ids_.pop_front();
  }
  void forget(guint32 id) {
    ids_.erase(std::remove(ids_.begin(), ids_.end(), id), ids_.end());
  }
  bool consume(guint32 id, const char* action) {
    if (g_strcmp0(action, "default") != 0 ||
        std::find(ids_.begin(), ids_.end(), id) == ids_.end()) return false;
    forget(id);
    return true;
  }
  void clear() { ids_.clear(); }

 private:
  std::deque<guint32> ids_;
};

#endif
