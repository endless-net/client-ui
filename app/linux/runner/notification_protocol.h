#ifndef ENDLESSNET_NOTIFICATION_PROTOCOL_H_
#define ENDLESSNET_NOTIFICATION_PROTOCOL_H_

#include <gio/gio.h>

inline const char* notification_error_result(const GError* error) {
  if (g_error_matches(error, G_DBUS_ERROR, G_DBUS_ERROR_ACCESS_DENIED) ||
      g_error_matches(error, G_DBUS_ERROR, G_DBUS_ERROR_AUTH_FAILED)) {
    return "permissionDenied";
  }
  if (g_error_matches(error, G_DBUS_ERROR, G_DBUS_ERROR_UNKNOWN_METHOD)) {
    return "unsupported";
  }
  return "unavailable";
}

inline GVariant* notification_parameters(const char* body) {
  GVariantBuilder actions;
  g_variant_builder_init(&actions, G_VARIANT_TYPE("as"));
  g_variant_builder_add(&actions, "s", "default");
  g_variant_builder_add(&actions, "s", "EndlessNet");
  GVariantBuilder hints;
  g_variant_builder_init(&hints, G_VARIANT_TYPE("a{sv}"));
  g_variant_builder_add(&hints, "{sv}", "suppress-sound", g_variant_new_boolean(TRUE));
  g_autofree gchar* escaped = g_markup_escape_text(body, -1);
  return g_variant_new("(susssasa{sv}i)", "EndlessNet", 0u, "",
                       "EndlessNet", escaped, &actions, &hints, -1);
}

#endif
