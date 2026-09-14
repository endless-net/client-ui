#ifndef ENDLESSNET_TRAY_HOST_PROTOCOL_H_
#define ENDLESSNET_TRAY_HOST_PROTOCOL_H_
#include <gio/gio.h>
inline bool tray_host_registered(GVariant* reply) {
  if (!reply || !g_variant_is_of_type(reply, G_VARIANT_TYPE("(v)"))) return false;
  g_autoptr(GVariant) boxed = g_variant_get_child_value(reply, 0);
  g_autoptr(GVariant) value = g_variant_get_variant(boxed);
  return g_variant_is_of_type(value, G_VARIANT_TYPE_BOOLEAN) &&
         g_variant_get_boolean(value);
}
#endif
