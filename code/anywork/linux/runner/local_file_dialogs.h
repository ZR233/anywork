#ifndef RUNNER_LOCAL_FILE_DIALOGS_H_
#define RUNNER_LOCAL_FILE_DIALOGS_H_

#include <flutter_linux/flutter_linux.h>
#include <gtk/gtk.h>

void register_local_file_dialogs(FlBinaryMessenger* messenger, GtkWindow* window);

#endif  // RUNNER_LOCAL_FILE_DIALOGS_H_
