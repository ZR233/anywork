#include "local_file_dialogs.h"

#include <algorithm>
#include <string>

namespace {

FlMethodResponse* Error(const char* code, const char* message) {
  return FL_METHOD_RESPONSE(fl_method_error_response_new(code, message, nullptr));
}

bool FileFilter(FlValue* arguments, std::string* pattern) {
  if (arguments == nullptr || fl_value_get_type(arguments) != FL_VALUE_TYPE_LIST) {
    return false;
  }
  for (size_t index = 0; index < fl_value_get_length(arguments); ++index) {
    FlValue* value = fl_value_get_list_value(arguments, index);
    if (fl_value_get_type(value) != FL_VALUE_TYPE_STRING) return false;
    const std::string extension = fl_value_get_string(value);
    if (extension.empty() ||
        !std::all_of(extension.begin(), extension.end(), [](unsigned char c) {
          return g_ascii_isalnum(c);
        })) {
      return false;
    }
    if (!pattern->empty()) pattern->append("; ");
    pattern->append("*." + extension);
  }
  return true;
}

FlMethodResponse* Pick(GtkWindow* window, bool directory, FlValue* arguments) {
  std::string pattern;
  if (!directory && !FileFilter(arguments, &pattern)) {
    return Error("invalid_arguments", "Expected file extensions.");
  }
  g_autoptr(GtkFileChooserNative) dialog = gtk_file_chooser_native_new(
      nullptr, window,
      directory ? GTK_FILE_CHOOSER_ACTION_SELECT_FOLDER
                : GTK_FILE_CHOOSER_ACTION_OPEN,
      nullptr, nullptr);
  GtkFileChooser* chooser = GTK_FILE_CHOOSER(dialog);
  gtk_file_chooser_set_local_only(chooser, TRUE);
  gtk_file_chooser_set_select_multiple(chooser, !directory);
  if (!pattern.empty()) {
    GtkFileFilter* filter = gtk_file_filter_new();
    gtk_file_filter_set_name(filter, pattern.c_str());
    for (size_t index = 0; index < fl_value_get_length(arguments); ++index) {
      const std::string extension =
          fl_value_get_string(fl_value_get_list_value(arguments, index));
      gtk_file_filter_add_pattern(filter, ("*." + extension).c_str());
    }
    gtk_file_chooser_add_filter(chooser, filter);
  }

  // The native modal loop keeps GTK events running. Its scoped owner retains
  // the chooser and selection until the platform response has been encoded.
  const gint response = gtk_native_dialog_run(GTK_NATIVE_DIALOG(dialog));
  g_autoptr(FlValue) selection = directory ? nullptr : fl_value_new_list();
  if (response == GTK_RESPONSE_ACCEPT) {
    if (directory) {
      g_autofree gchar* path = gtk_file_chooser_get_filename(chooser);
      if (path == nullptr) {
        gtk_native_dialog_destroy(GTK_NATIVE_DIALOG(dialog));
        return Error("file_dialog_failed", "No local directory was selected.");
      }
      selection = fl_value_new_string(path);
    } else {
      GSList* paths = gtk_file_chooser_get_filenames(chooser);
      for (GSList* entry = paths; entry != nullptr; entry = entry->next) {
        fl_value_append_take(selection,
                             fl_value_new_string(static_cast<gchar*>(entry->data)));
      }
      g_slist_free_full(paths, g_free);
    }
  } else if (response != GTK_RESPONSE_CANCEL &&
             response != GTK_RESPONSE_DELETE_EVENT) {
    gtk_native_dialog_destroy(GTK_NATIVE_DIALOG(dialog));
    return Error("file_dialog_failed", "File dialog failed to return a selection.");
  }
  gtk_native_dialog_destroy(GTK_NATIVE_DIALOG(dialog));
  return FL_METHOD_RESPONSE(fl_method_success_response_new(selection));
}

FlMethodResponse* Save(GtkWindow* window, FlValue* arguments) {
  if (arguments == nullptr ||
      fl_value_get_type(arguments) != FL_VALUE_TYPE_STRING) {
    return Error("invalid_arguments", "Expected a suggested filename.");
  }
  g_autoptr(GtkFileChooserNative) dialog = gtk_file_chooser_native_new(
      nullptr, window, GTK_FILE_CHOOSER_ACTION_SAVE, nullptr, nullptr);
  GtkFileChooser* chooser = GTK_FILE_CHOOSER(dialog);
  gtk_file_chooser_set_local_only(chooser, TRUE);
  gtk_file_chooser_set_do_overwrite_confirmation(chooser, TRUE);
  g_autofree gchar* name = g_path_get_basename(fl_value_get_string(arguments));
  gtk_file_chooser_set_current_name(chooser, name);
  const gint response = gtk_native_dialog_run(GTK_NATIVE_DIALOG(dialog));
  g_autoptr(FlValue) selection = nullptr;
  if (response == GTK_RESPONSE_ACCEPT) {
    g_autofree gchar* path = gtk_file_chooser_get_filename(chooser);
    if (path == nullptr) {
      gtk_native_dialog_destroy(GTK_NATIVE_DIALOG(dialog));
      return Error("file_dialog_failed", "No local save path was selected.");
    }
    selection = fl_value_new_string(path);
  } else if (response != GTK_RESPONSE_CANCEL &&
             response != GTK_RESPONSE_DELETE_EVENT) {
    gtk_native_dialog_destroy(GTK_NATIVE_DIALOG(dialog));
    return Error("file_dialog_failed", "Save dialog failed.");
  }
  gtk_native_dialog_destroy(GTK_NATIVE_DIALOG(dialog));
  return FL_METHOD_RESPONSE(fl_method_success_response_new(selection));
}

void RevealFinished(GObject* source, GAsyncResult* result, gpointer user_data) {
  g_autoptr(FlMethodCall) call = FL_METHOD_CALL(user_data);
  g_autoptr(GError) error = nullptr;
  g_autoptr(GVariant) reply =
      g_dbus_connection_call_finish(G_DBUS_CONNECTION(source), result, &error);
  g_autoptr(FlMethodResponse) response =
      reply != nullptr
          ? FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr))
          : Error("reveal_file_failed", error->message);
  g_autoptr(GError) send_error = nullptr;
  if (!fl_method_call_respond(call, response, &send_error)) {
    g_warning("Failed to send reveal response: %s", send_error->message);
  }
}

// org.freedesktop.FileManager1 is the desktop's native file-selection API.
// No shell command or fallback opens a remote path as a local location.
FlMethodResponse* Reveal(FlMethodCall* call) {
  FlValue* arguments = fl_method_call_get_args(call);
  if (arguments == nullptr ||
      fl_value_get_type(arguments) != FL_VALUE_TYPE_STRING) {
    return Error("invalid_arguments", "Expected an absolute local path.");
  }
  const gchar* path = fl_value_get_string(arguments);
  if (!g_path_is_absolute(path) || !g_file_test(path, G_FILE_TEST_IS_REGULAR)) {
    return Error("reveal_file_failed", "The original local file does not exist.");
  }
  g_autoptr(GError) error = nullptr;
  g_autofree gchar* uri = g_filename_to_uri(path, nullptr, &error);
  if (uri == nullptr) return Error("reveal_file_failed", error->message);
  g_autoptr(GDBusConnection) bus = g_bus_get_sync(G_BUS_TYPE_SESSION, nullptr, &error);
  if (bus == nullptr) return Error("reveal_file_failed", error->message);
  const gchar* uris[] = {uri, nullptr};
  g_dbus_connection_call(
      bus, "org.freedesktop.FileManager1", "/org/freedesktop/FileManager1",
      "org.freedesktop.FileManager1", "ShowItems",
      g_variant_new("(^ass)", uris, ""), nullptr, G_DBUS_CALL_FLAGS_NONE,
      -1, nullptr, RevealFinished, g_object_ref(call));
  return nullptr;  // The retained method call is completed by RevealFinished.
}

void OnMethodCall(FlMethodChannel* channel, FlMethodCall* call, gpointer user_data) {
  (void)channel;
  const gchar* method = fl_method_call_get_name(call);
  const bool directory = g_strcmp0(method, "pickDirectory") == 0;
  g_autoptr(FlMethodResponse) response = nullptr;
  if (g_strcmp0(method, "revealFile") == 0) {
    response = Reveal(call);
    if (response == nullptr) return;
  } else if (g_strcmp0(method, "saveFile") == 0) {
    response = Save(GTK_WINDOW(user_data), fl_method_call_get_args(call));
  } else if (directory || g_strcmp0(method, "pickFiles") == 0) {
    response = Pick(GTK_WINDOW(user_data), directory, fl_method_call_get_args(call));
  } else {
    response = FL_METHOD_RESPONSE(fl_method_not_implemented_response_new());
  }
  g_autoptr(GError) error = nullptr;
  if (!fl_method_call_respond(call, response, &error)) {
    g_warning("Failed to send file dialog response: %s", error->message);
  }
}

}  // namespace

void register_local_file_dialogs(FlBinaryMessenger* messenger, GtkWindow* window) {
  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  g_autoptr(FlMethodChannel) channel = fl_method_channel_new(
      messenger, "io.github.zr233.anywork/file_dialogs", FL_METHOD_CODEC(codec));
  // The window owns the engine and its messenger, which retains the channel.
  fl_method_channel_set_method_call_handler(channel, OnMethodCall, window, nullptr);
}
