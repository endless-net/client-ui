#ifndef ENDLESSNET_TRAY_HOST_H_
#define ENDLESSNET_TRAY_HOST_H_
#include <flutter_linux/flutter_linux.h>
#include <gio/gio.h>
void register_tray_host(FlBinaryMessenger* messenger, GDBusConnection* session_bus);
#endif
