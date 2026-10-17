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

void OnMethodCall(FlMethodChannel* channel, FlMethodCall* call, gpointer user_data) {
  (void)channel;
  const gchar* method = fl_method_call_get_name(call);
  const bool directory = g_strcmp0(method, "pickDirectory") == 0;
  g_autoptr(FlMethodResponse) response =
      directory || g_strcmp0(method, "pickFiles") == 0
          ? Pick(GTK_WINDOW(user_data), directory, fl_method_call_get_args(call))
          : FL_METHOD_RESPONSE(fl_method_not_implemented_response_new());
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
