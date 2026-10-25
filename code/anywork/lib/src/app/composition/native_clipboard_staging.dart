import 'dart:typed_data';

import '../../platform/clipboard_image_reader.dart';

/// Adapts the existing platform staging lease to Drafts' two callbacks. The
/// Drafts owner retains each path and its budget until this exact lease closes.
final class NativeClipboardStaging {
  final _stager = const SystemClipboardImageStager();
  final Map<String, StagedClipboardImage> _images = {};

  Future<String?> stage(Uint8List bytes) async {
    final image = await _stager.stage(bytes);
    _images[image.path] = image;
    return image.path;
  }

  Future<void> cleanup(String path) async {
    final image = _images[path];
    if (image == null) {
      throw StateError(
        'Clipboard cleanup must retain its original staging lease.',
      );
    }
    // A failed deletion still owns this exact lease. Let Drafts record the
    // original error and retain its staging permit until explicit cleanup retry.
    await image.dispose();
    _images.remove(path);
  }
}
