#include "tray_host.h"
#include "tray_host_protocol.h"

namespace {
void respond(FlMethodCall* call, bool available) {
  g_autoptr(FlValue) value = fl_value_new_bool(available);
  fl_method_call_respond_success(call, value, nullptr);
}
void finished(GObject* source, GAsyncResult* result, gpointer data) {
  g_autoptr(FlMethodCall) call = FL_METHOD_CALL(data);
  g_autoptr(GError) error = nullptr;
  g_autoptr(GVariant) reply = g_dbus_connection_call_finish(
      G_DBUS_CONNECTION(source), result, &error);
  respond(call, tray_host_registered(reply));
}
void call(FlMethodChannel*, FlMethodCall* method, gpointer data) {
  if (g_strcmp0(fl_method_call_get_name(method), "isAvailable") != 0) {
    fl_method_call_respond_not_implemented(method, nullptr);
    return;
  }
  auto* arguments = fl_method_call_get_args(method);
  auto* bus = static_cast<GDBusConnection*>(data);
  if ((arguments && fl_value_get_type(arguments) != FL_VALUE_TYPE_NULL) ||
      !bus || g_dbus_connection_is_closed(bus)) {
    respond(method, false);
    return;
  }
  // The KDE wire namespace is the one used by libappindicator/tray_manager.
  // Do not start a watcher or fall back to an unverified XEmbed tray.
  g_dbus_connection_call(bus, "org.kde.StatusNotifierWatcher", "/StatusNotifierWatcher",
      "org.freedesktop.DBus.Properties", "Get",
      g_variant_new("(ss)", "org.kde.StatusNotifierWatcher", "IsStatusNotifierHostRegistered"),
      G_VARIANT_TYPE("(v)"), G_DBUS_CALL_FLAGS_NO_AUTO_START, 1000, nullptr,
      finished, g_object_ref(method));
}
}  // namespace

void register_tray_host(FlBinaryMessenger* messenger, GDBusConnection* session_bus) {
  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  g_autoptr(FlMethodChannel) channel = fl_method_channel_new(
      messenger, "endlessnet/ui-tray-host", FL_METHOD_CODEC(codec));
  fl_method_channel_set_method_call_handler(channel, call,
      session_bus ? g_object_ref(session_bus) : nullptr,
      [](gpointer data) { if (data) g_object_unref(data); });
}
