#include "tray_host_protocol.h"
int main() {
  g_assert_false(tray_host_registered(nullptr));
  g_autoptr(GVariant) yes = g_variant_ref_sink(g_variant_new("(v)", g_variant_new_boolean(TRUE)));
  g_autoptr(GVariant) no = g_variant_ref_sink(g_variant_new("(v)", g_variant_new_boolean(FALSE)));
  g_autoptr(GVariant) wrong_value = g_variant_ref_sink(g_variant_new("(v)", g_variant_new_string("true")));
  g_autoptr(GVariant) wrong_tuple = g_variant_ref_sink(g_variant_new("(b)", TRUE));
  g_assert_true(tray_host_registered(yes));
  g_assert_false(tray_host_registered(no));
  g_assert_false(tray_host_registered(wrong_value));
  g_assert_false(tray_host_registered(wrong_tuple));
}
