import 'dart:io';
import 'dart:typed_data';

import 'package:url_launcher/url_launcher.dart';

import 'local_file_dialogs.dart';

/// GUI-machine capabilities. No execution workspace path or download protocol.
abstract interface class PublicArtifactPlatform {
  Future<String?> chooseSavePath(String suggestedName);
  Future<void> writeBytes(String destination, Uint8List bytes);
  Future<bool> openFile(String destination);
}

final class SystemPublicArtifactPlatform implements PublicArtifactPlatform {
  const SystemPublicArtifactPlatform();

  @override
  Future<String?> chooseSavePath(String suggestedName) =>
      chooseLocalArtifactSavePath(suggestedName);

  @override
  Future<void> writeBytes(String destination, Uint8List bytes) async {
    // The host has read and verified the original before this function is called.
    // No target is opened/truncated on chooser cancellation or resource failure.
    // Standard-library completion includes flush and close; no cross-platform
    // atomic-rename or rollback guarantee is invented for an I/O failure.
    await File(destination).writeAsBytes(bytes, flush: true);
  }

  @override
  Future<bool> openFile(String destination) async {
    if (!await File(destination).exists()) return false;
    return launchUrl(
      Uri.file(destination),
      mode: LaunchMode.externalApplication,
    );
  }
}
