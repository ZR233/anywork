import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'local_file_dialogs.dart';

typedef ProjectDirectoryPicker = Future<String?> Function();
typedef AttachmentPathPicker =
    Future<List<String>> Function({List<String> extensions});
typedef ExecutablePathPicker = Future<String?> Function();

final projectDirectoryPickerProvider = Provider<ProjectDirectoryPicker>(
  (ref) => pickLocalProjectDirectory,
);

final attachmentPathPickerProvider = Provider<AttachmentPathPicker>(
  (ref) => pickLocalAttachmentPaths,
);

final executablePathPickerProvider = Provider<ExecutablePathPicker>(
  (ref) => pickLocalExecutablePath,
);
