#include "notifications.h"
#include "notification_protocol.h"

#include <cstring>

namespace {
void respond(FlMethodCall* call, const char* result) {
  g_autoptr(FlValue) value = fl_value_new_string(result);
  fl_method_call_respond_success(call, value, nullptr);
}

void notification_finished(GObject* source, GAsyncResult* result, gpointer data) {
  g_autoptr(FlMethodCall) call = FL_METHOD_CALL(data);
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
  auto* bus = static_cast<GDBusConnection*>(data);
  if (bus == nullptr || g_dbus_connection_is_closed(bus)) {
    respond(call, "unavailable");
    return;
  }
  g_dbus_connection_call(
      bus, "org.freedesktop.Notifications", "/org/freedesktop/Notifications",
      "org.freedesktop.Notifications", "Notify",
      notification_parameters(fl_value_get_string(body)),
      G_VARIANT_TYPE("(u)"), G_DBUS_CALL_FLAGS_NONE, 5000, nullptr,
      notification_finished, g_object_ref(call));
}
}  // namespace

void register_notifications(FlBinaryMessenger* messenger,
                            GDBusConnection* session_bus) {
  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  g_autoptr(FlMethodChannel) channel = fl_method_channel_new(
      messenger, "endlessnet/ui-notifications", FL_METHOD_CODEC(codec));
  fl_method_channel_set_method_call_handler(
      channel, notification_call,
      session_bus != nullptr ? g_object_ref(session_bus) : nullptr,
      session_bus != nullptr ? g_object_unref : nullptr);
}
