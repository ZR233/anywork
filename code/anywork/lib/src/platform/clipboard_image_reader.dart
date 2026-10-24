import 'dart:io';
import 'dart:ui' as ui;

import 'package:anywork_client/studio_client.dart' show ComposerClipboardReader;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pasteboard/pasteboard.dart';

final clipboardReaderProvider = Provider<ComposerClipboardReader>(
  (ref) => const SystemClipboardReader(),
);

abstract interface class ClipboardImageStager {
  Future<StagedClipboardImage> stage(Uint8List pngBytes);
}

final clipboardImageStagerProvider = Provider<ClipboardImageStager>(
  (ref) => const SystemClipboardImageStager(),
);

final class StagedClipboardImage {
  StagedClipboardImage({required this.path, required this.dispose});

  final String path;
  final Future<void> Function() dispose;
}

final class SystemClipboardImageStager implements ClipboardImageStager {
  const SystemClipboardImageStager();

  @override
  Future<StagedClipboardImage> stage(Uint8List pngBytes) async {
    final directory = await Directory.systemTemp.createTemp(
      'anywork-clipboard-',
    );
    try {
      final image = File('${directory.path}/clipboard-image.png');
      await image.writeAsBytes(pngBytes, flush: true);
      return StagedClipboardImage(
        path: image.path,
        dispose: () async {
          if (await directory.exists()) await directory.delete(recursive: true);
        },
      );
    } catch (_) {
      await directory.delete(recursive: true);
      rethrow;
    }
  }
}

final class SystemClipboardReader implements ComposerClipboardReader {
  const SystemClipboardReader();

  @override
  Future<List<String>> readFiles() => Pasteboard.files();

  @override
  Future<Uint8List?> readImage() async {
    final encoded = await Pasteboard.image;
    if (encoded == null || encoded.isEmpty) return null;

    final codec = await ui.instantiateImageCodec(encoded);
    try {
      final frame = await codec.getNextFrame();
      try {
        final png = await frame.image.toByteData(
          format: ui.ImageByteFormat.png,
        );
        if (png == null) {
          throw StateError('Clipboard image could not be encoded as PNG.');
        }
        return png.buffer.asUint8List(png.offsetInBytes, png.lengthInBytes);
      } finally {
        frame.image.dispose();
      }
    } finally {
      codec.dispose();
    }
  }

  @override
  Future<String?> readText() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    return data?.text;
  }
}
