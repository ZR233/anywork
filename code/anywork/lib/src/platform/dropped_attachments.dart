import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:anywork_client/studio_client.dart'
    show AttachmentDraftInput, AttachmentInputLimits;
import 'package:desktop_drop/desktop_drop.dart';

/// Keep platform transfers alive until Rust has copied each file into a draft.
Future<void> admitDroppedAttachments(
  Iterable<DropFileItem> files,
  AttachmentDraftInput input,
) async {
  final items = files.take(AttachmentInputLimits.maxFiles + 1).toList();
  if (items.isEmpty) return;
  if (items.length > AttachmentInputLimits.maxFiles) {
    throw StateError('Too many dropped files for one attachment batch.');
  }
  var batchBytes = 0;
  // Borrowed local files also consume the batch budget, before any provider
  // stream is opened or temporary disk space is allocated. Rust revalidates
  // these snapshots at admission, including files modified in the meantime.
  for (final item in items) {
    if (!input.isCurrent) return;
    final path = item.localPath;
    if (path == null || path.isEmpty) continue;
    final stat = await File(path).stat();
    if (!input.isCurrent) return;
    if (stat.type != FileSystemEntityType.file) {
      throw FileSystemException('Dropped item is not a regular file.', path);
    }
    _checkFileBytes(stat.size, item.name);
    batchBytes += stat.size;
    _checkBatchBytes(batchBytes);
  }
  if (items.every((item) => item.localPath?.isNotEmpty == true)) {
    await input.addLocalFiles([for (final item in items) item.localPath!]);
    return;
  }
  await input.withLocalStaging(
    create: () async =>
        (await Directory.systemTemp.createTemp('anywork-drop-')).path,
    cleanup: (path) async {
      final directory = Directory(path);
      if (await directory.exists()) await directory.delete(recursive: true);
    },
    use: (path) async {
      final staging = Directory(path);
      final paths = <String>[];
      for (final item in items) {
        if (!input.isCurrent) return;
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
        final directory = await staging.createTemp('file-');
        final destination = File(
          '${directory.path}${Platform.pathSeparator}$name',
        );
        final output = await destination.open(mode: FileMode.write);
        try {
          if (!input.isCurrent) return;
          final iterator = StreamIterator<Uint8List>(item.file.openRead());
          final copying = () async {
            var fileBytes = 0;
            while (input.isCurrent && await iterator.moveNext()) {
              if (!input.isCurrent) return;
              final chunk = iterator.current;
              fileBytes += chunk.length;
              _checkFileBytes(fileBytes, name);
              batchBytes += chunk.length;
              _checkBatchBytes(batchBytes);
              // Never write the chunk that would exceed either budget.
              await output.writeFrom(chunk);
            }
          }();
          try {
            await Future.any<void>([copying, input.whenInvalidated]);
          } finally {
            // StreamIterator.cancel wakes a suspended moveNext without a new
            // event. Its Future is the actual subscription cleanup ACK.
            try {
              await iterator.cancel();
            } finally {
              await copying;
            }
          }
        } finally {
          await output.close();
        }
        if (!input.isCurrent) return;
        paths.add(destination.path);
      }
      await input.addLocalFiles(paths);
    },
  );
}

void _checkFileBytes(int bytes, String name) {
  if (bytes > AttachmentInputLimits.maxFileBytes) {
    throw StateError(
      'Dropped file exceeds the transfer file-size limit: $name',
    );
  }
}

void _checkBatchBytes(int bytes) {
  if (bytes > AttachmentInputLimits.maxBatchBytes) {
    throw StateError('Dropped files exceed the transfer batch-size limit.');
  }
}
