#include "notification_protocol.h"
#include "notification_activations.h"

static void parameters() {
  g_autoptr(GVariant) value = g_variant_ref_sink(notification_parameters("Срок <сессии> & данные"));
  g_assert_true(g_variant_is_of_type(value, G_VARIANT_TYPE("(susssasa{sv}i)")));
  const gchar *app, *icon, *title, *body;
  guint32 replacement;
  gint32 expiry;
  GVariant *actions_raw, *hints_raw;
  g_variant_get(value, "(&su&s&s&s@as@a{sv}i)", &app, &replacement, &icon,
                &title, &body, &actions_raw, &hints_raw, &expiry);
  g_autoptr(GVariant) actions = actions_raw;
  g_autoptr(GVariant) hints = hints_raw;
  g_assert_cmpstr(app, ==, "EndlessNet");
  g_assert_cmpuint(replacement, ==, 0);
  g_assert_cmpstr(icon, ==, "");
  g_assert_cmpstr(title, ==, "EndlessNet");
  g_assert_cmpstr(body, ==, "Срок &lt;сессии&gt; &amp; данные");
  g_assert_cmpuint(g_variant_n_children(actions), ==, 2);
  const gchar* action;
  const gchar* label;
  g_variant_get_child(actions, 0, "&s", &action);
  g_variant_get_child(actions, 1, "&s", &label);
  g_assert_cmpstr(action, ==, "default");
  g_assert_cmpstr(label, ==, "EndlessNet");
  g_assert_cmpuint(g_variant_n_children(hints), ==, 1);
  gboolean silent = FALSE;
  g_assert_true(g_variant_lookup(hints, "suppress-sound", "b", &silent));
  g_assert_true(silent);
  g_assert_cmpint(expiry, ==, -1);
}

static void failures() {
  const GDBusError codes[] = {G_DBUS_ERROR_ACCESS_DENIED, G_DBUS_ERROR_AUTH_FAILED,
                             G_DBUS_ERROR_UNKNOWN_METHOD, G_DBUS_ERROR_SERVICE_UNKNOWN,
                             G_DBUS_ERROR_NO_REPLY};
  const char* expected[] = {"permissionDenied", "permissionDenied", "unsupported",
                            "unavailable", "unavailable"};
  for (guint i = 0; i < G_N_ELEMENTS(codes); ++i) {
    g_autoptr(GError) error = g_error_new_literal(G_DBUS_ERROR, codes[i], "private bus detail");
    g_assert_cmpstr(notification_error_result(error), ==, expected[i]);
  }
  g_autoptr(GError) closed = g_error_new_literal(G_IO_ERROR, G_IO_ERROR_CLOSED, "private");
  g_assert_cmpstr(notification_error_result(closed), ==, "unavailable");
}

static void activations() {
  NotificationActivations receipts;
  receipts.remember(0);
  g_assert_false(receipts.consume(0, "default"));
  g_assert_false(receipts.consume(99, "default"));
  receipts.remember(1);
  g_assert_false(receipts.consume(1, "open-url"));
  g_assert_false(receipts.consume(1, nullptr));
  g_assert_true(receipts.consume(1, "default"));
  g_assert_false(receipts.consume(1, "default"));
  receipts.remember(2);
  receipts.forget(2);
  g_assert_false(receipts.consume(2, "default"));
  receipts.remember(3);
  receipts.clear();
  g_assert_false(receipts.consume(3, "default"));
}

static void bounded_receipts() {
  NotificationActivations receipts;
  for (guint32 i = 1; i <= 65; ++i) receipts.remember(i);
  g_assert_false(receipts.consume(1, "default"));
  receipts.remember(2);  // Refreshing an ID does not consume another slot.
  receipts.remember(66);
  g_assert_false(receipts.consume(3, "default"));
  g_assert_true(receipts.consume(2, "default"));
  for (guint32 i = 4; i <= 66; ++i) g_assert_true(receipts.consume(i, "default"));
}

int main(int argc, char** argv) {
  g_test_init(&argc, &argv, nullptr);
  g_test_add_func("/notifications/parameters", parameters);
  g_test_add_func("/notifications/errors", failures);
  g_test_add_func("/notifications/activation", activations);
  g_test_add_func("/notifications/bounded-receipts", bounded_receipts);
  return g_test_run();
}
