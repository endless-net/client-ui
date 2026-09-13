#include "bundle_destination.h"

#include <cstring>

namespace {
struct DestinationChooser {
  GWeakRef window;
  gulong destroy_handler = 0;
  GtkFileChooserNative* dialog = nullptr;
  FlMethodCall* pending = nullptr;
  bool closed = false;

  explicit DestinationChooser(GtkWindow* parent) {
    g_weak_ref_init(&window, G_OBJECT(parent));
    destroy_handler = g_signal_connect(parent, "destroy", G_CALLBACK(parent_destroyed), this);
  }
  ~DestinationChooser() {
    finish(nullptr);
    g_autoptr(GObject) parent = G_OBJECT(g_weak_ref_get(&window));
    if (parent != nullptr && destroy_handler != 0) {
      g_signal_handler_disconnect(parent, destroy_handler);
    }
    g_weak_ref_clear(&window);
  }
  static void parent_destroyed(GtkWidget*, gpointer data) {
    auto* self = static_cast<DestinationChooser*>(data);
    self->closed = true;
    self->finish(nullptr);
  }
  void finish(const char* path, bool failed = false) {
    // Remove callbacks before destroying the dialog: exactly one response.
    if (dialog != nullptr) {
      g_signal_handlers_disconnect_by_data(dialog, this);
      gtk_native_dialog_destroy(GTK_NATIVE_DIALOG(dialog));
      g_clear_object(&dialog);
    }
    if (pending == nullptr) return;
    if (failed) {
      fl_method_call_respond_error(pending, "destination_unavailable",
                                   "Destination unavailable", nullptr, nullptr);
    } else {
      g_autoptr(FlValue) value = path != nullptr ? fl_value_new_string(path) : nullptr;
      fl_method_call_respond_success(pending, value, nullptr);
    }
    g_clear_object(&pending);
  }
  static void response(GtkNativeDialog* native, gint response_id, gpointer data) {
    auto* self = static_cast<DestinationChooser*>(data);
    if (response_id != GTK_RESPONSE_ACCEPT) {
      self->finish(nullptr);
      return;
    }
    g_autofree gchar* path = gtk_file_chooser_get_filename(GTK_FILE_CHOOSER(native));
    self->finish(path, path == nullptr || !g_path_is_absolute(path));
  }
  void choose(FlMethodCall* call) {
    g_autoptr(GObject) parent = G_OBJECT(g_weak_ref_get(&window));
    if (closed || parent == nullptr || pending != nullptr) {
      fl_method_call_respond_error(call, "destination_unavailable",
                                   "Destination unavailable", nullptr, nullptr);
      return;
    }
    pending = FL_METHOD_CALL(g_object_ref(call));
    // OS-provided labels. No archive data, private path or profile is an input.
    dialog = gtk_file_chooser_native_new(nullptr, GTK_WINDOW(parent),
        GTK_FILE_CHOOSER_ACTION_SELECT_FOLDER, nullptr, nullptr);
    gtk_file_chooser_set_local_only(GTK_FILE_CHOOSER(dialog), TRUE);
    gtk_file_chooser_set_select_multiple(GTK_FILE_CHOOSER(dialog), FALSE);
    gtk_file_chooser_set_create_folders(GTK_FILE_CHOOSER(dialog), FALSE);
    gtk_native_dialog_set_modal(GTK_NATIVE_DIALOG(dialog), TRUE);
    g_signal_connect(dialog, "response", G_CALLBACK(response), this);
    gtk_native_dialog_show(GTK_NATIVE_DIALOG(dialog));
  }
};

void choose_directory(FlMethodChannel*, FlMethodCall* call, gpointer data) {
  if (std::strcmp(fl_method_call_get_name(call), "chooseDirectory") != 0) {
    fl_method_call_respond_not_implemented(call, nullptr);
    return;
  }
  FlValue* args = fl_method_call_get_args(call);
  if (args != nullptr && fl_value_get_type(args) != FL_VALUE_TYPE_NULL) {
    fl_method_call_respond_error(call, "invalid_arguments", "No arguments expected",
                                 nullptr, nullptr);
    return;
  }
  static_cast<DestinationChooser*>(data)->choose(call);
}
}  // namespace

void register_bundle_destination(FlBinaryMessenger* messenger, GtkWindow* window) {
  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  g_autoptr(FlMethodChannel) channel = fl_method_channel_new(
      messenger, "endlessnet/ui-diagnostics-destination", FL_METHOD_CODEC(codec));
  fl_method_channel_set_method_call_handler(channel, choose_directory,
      new DestinationChooser(window), [](gpointer data) {
        delete static_cast<DestinationChooser*>(data);
      });
}
