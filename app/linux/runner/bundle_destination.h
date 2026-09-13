#ifndef ENDLESSNET_BUNDLE_DESTINATION_H_
#define ENDLESSNET_BUNDLE_DESTINATION_H_

#include <flutter_linux/flutter_linux.h>
#include <gtk/gtk.h>

void register_bundle_destination(FlBinaryMessenger* messenger, GtkWindow* window);

#endif
