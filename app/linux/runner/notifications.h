#ifndef ENDLESSNET_NOTIFICATIONS_H_
#define ENDLESSNET_NOTIFICATIONS_H_

#include <flutter_linux/flutter_linux.h>
#include <gio/gio.h>

void register_notifications(FlBinaryMessenger* messenger,
                            GDBusConnection* session_bus);

#endif
