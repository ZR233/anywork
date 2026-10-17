import 'dart:io';

import 'package:desktop_drop/desktop_drop.dart';

/// Keep platform transfers alive until Rust has copied each file into a draft.
Future<void> admitDroppedAttachments(
  Iterable<DropFileItem> files,
  Future<void> Function(List<String> paths) admit,
) async {
  Directory? staging;
  try {
    final paths = <String>[];
    for (final item in files) {
      final localPath = item.localPath;
      if (localPath != null && localPath.isNotEmpty) {
        paths.add(localPath);
        continue;
      }

      final name = item.name
          .split(RegExp(r'[/\\]'))
          .last
          .replaceAll(RegExp(r'[<>:"|?*\x00-\x1f]'), '_');
      if (name.isEmpty || name == '.' || name == '..') {
        throw const FormatException('Dropped file has no valid filename.');
      }
      staging ??= await Directory.systemTemp.createTemp('anywork-drop-');
      final directory = await staging.createTemp('file-');
      final destination = File(
        '${directory.path}${Platform.pathSeparator}$name',
      );
      final output = await destination.open(mode: FileMode.write);
      try {
        await for (final chunk in item.file.openRead()) {
          await output.writeFrom(chunk);
        }
      } finally {
        await output.close();
      }
      paths.add(destination.path);
    }
    if (paths.isNotEmpty) await admit(paths);
  } finally {
    await staging?.delete(recursive: true);
  }
}
