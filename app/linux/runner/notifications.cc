#include "notifications.h"
#include "notification_protocol.h"
#include "notification_activations.h"

#include <cstring>
#include <memory>

namespace {
struct NotificationContext {
  GDBusConnection* bus;
  GWeakRef window;
  NotificationActivations activations;
  guint signals = 0;
  guint owner_signal = 0;
  guint64 generation = 0;
  bool active = true;

  NotificationContext(GDBusConnection* connection, GtkWindow* target)
      : bus(connection != nullptr ? G_DBUS_CONNECTION(g_object_ref(connection)) : nullptr) {
    g_weak_ref_init(&window, G_OBJECT(target));
  }
  void stop() {
    active = false;
    activations.clear();
    if (signals != 0) g_dbus_connection_signal_unsubscribe(bus, signals);
    if (owner_signal != 0) g_dbus_connection_signal_unsubscribe(bus, owner_signal);
    signals = owner_signal = 0;
  }
  ~NotificationContext() {
    stop();
    g_weak_ref_clear(&window);
    g_clear_object(&bus);
  }
};
using Context = std::shared_ptr<NotificationContext>;
struct PendingNotification {
  FlMethodCall* call;
  Context context;
  guint64 generation;
  ~PendingNotification() { g_object_unref(call); }
};

void notification_signal(GDBusConnection*, const gchar*, const gchar*,
                         const gchar*, const gchar* signal, GVariant* parameters,
                         gpointer data) {
  const auto context = *static_cast<Context*>(data);
  if (!context->active) return;
  if (g_strcmp0(signal, "NameOwnerChanged") == 0) {
    context->generation++;
    context->activations.clear();
  } else if (g_strcmp0(signal, "NotificationClosed") == 0 &&
             g_variant_is_of_type(parameters, G_VARIANT_TYPE("(uu)"))) {
    guint32 id, reason;
    g_variant_get(parameters, "(uu)", &id, &reason);
    context->activations.forget(id);
  } else if (g_strcmp0(signal, "ActionInvoked") == 0 &&
             g_variant_is_of_type(parameters, G_VARIANT_TYPE("(us)"))) {
    guint32 id;
    const gchar* action;
    g_variant_get(parameters, "(u&s)", &id, &action);
    if (!context->activations.consume(id, action)) return;
    g_autoptr(GObject) target = G_OBJECT(g_weak_ref_get(&context->window));
    if (target != nullptr) gtk_window_present(GTK_WINDOW(target));
  }
}

void respond(FlMethodCall* call, const char* result) {
  g_autoptr(FlValue) value = fl_value_new_string(result);
  fl_method_call_respond_success(call, value, nullptr);
}

void notification_finished(GObject* source, GAsyncResult* result, gpointer data) {
  std::unique_ptr<PendingNotification> pending(static_cast<PendingNotification*>(data));
  FlMethodCall* call = pending->call;
  g_autoptr(GError) error = nullptr;
  g_autoptr(GVariant) reply = g_dbus_connection_call_finish(
      G_DBUS_CONNECTION(source), result, &error);
  if (error != nullptr) {
    // No raw D-Bus error, address, desktop context or exception crosses to UI.
    respond(call, notification_error_result(error));
    return;
  }
  guint32 id = 0;
  if (reply != nullptr) g_variant_get(reply, "(u)", &id);
  if (pending->context->active && pending->generation == pending->context->generation) {
    pending->context->activations.remember(id);
  }
  // Accepted by the notification service, not proof of display or interaction.
  respond(call, id > 0 ? "delivered" : "failed");
}

void notification_call(FlMethodChannel*, FlMethodCall* call, gpointer data) {
  if (std::strcmp(fl_method_call_get_name(call), "deliver") != 0) {
    fl_method_call_respond_not_implemented(call, nullptr);
    return;
  }
  FlValue* args = fl_method_call_get_args(call);
  if (args == nullptr || fl_value_get_type(args) != FL_VALUE_TYPE_MAP ||
      fl_value_get_length(args) != 2) {
    respond(call, "failed");
    return;
  }
  FlValue* title = fl_value_lookup_string(args, "title");
  FlValue* body = fl_value_lookup_string(args, "body");
  if (title == nullptr || body == nullptr ||
      fl_value_get_type(title) != FL_VALUE_TYPE_STRING ||
      fl_value_get_type(body) != FL_VALUE_TYPE_STRING ||
      std::strcmp(fl_value_get_string(title), "EndlessNet") != 0 ||
      std::strlen(fl_value_get_string(body)) == 0 ||
      std::strlen(fl_value_get_string(body)) > 2048) {
    respond(call, "failed");
    return;
  }
  auto context = *static_cast<Context*>(data);
  auto* bus = context->bus;
  if (bus == nullptr || g_dbus_connection_is_closed(bus)) {
    respond(call, "unavailable");
    return;
  }
  g_dbus_connection_call(
      bus, "org.freedesktop.Notifications", "/org/freedesktop/Notifications",
      "org.freedesktop.Notifications", "Notify",
      notification_parameters(fl_value_get_string(body)),
      G_VARIANT_TYPE("(u)"), G_DBUS_CALL_FLAGS_NONE, 5000, nullptr,
      notification_finished, new PendingNotification{
        FL_METHOD_CALL(g_object_ref(call)), context, context->generation});
}
}  // namespace

void register_notifications(FlBinaryMessenger* messenger,
                            GDBusConnection* session_bus, GtkWindow* window) {
  auto context = std::make_shared<NotificationContext>(session_bus, window);
  if (session_bus != nullptr) {
    context->signals = g_dbus_connection_signal_subscribe(
        session_bus, "org.freedesktop.Notifications", "org.freedesktop.Notifications",
        nullptr, "/org/freedesktop/Notifications", nullptr, G_DBUS_SIGNAL_FLAGS_NONE,
        notification_signal, new Context(context),
        [](gpointer data) { delete static_cast<Context*>(data); });
    context->owner_signal = g_dbus_connection_signal_subscribe(
        session_bus, "org.freedesktop.DBus", "org.freedesktop.DBus", "NameOwnerChanged",
        "/org/freedesktop/DBus", "org.freedesktop.Notifications", G_DBUS_SIGNAL_FLAGS_NONE,
        notification_signal, new Context(context),
        [](gpointer data) { delete static_cast<Context*>(data); });
  }
  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  g_autoptr(FlMethodChannel) channel = fl_method_channel_new(
      messenger, "endlessnet/ui-notifications", FL_METHOD_CODEC(codec));
  fl_method_channel_set_method_call_handler(
      channel, notification_call,
      new Context(context), [](gpointer data) {
        auto* value = static_cast<Context*>(data);
        (*value)->stop();
        delete value;
      });
}
