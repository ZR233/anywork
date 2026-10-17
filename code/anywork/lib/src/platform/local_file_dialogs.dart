import 'package:flutter/services.dart';

const _fileDialogs = MethodChannel('io.github.zr233.anywork/file_dialogs');

Future<List<String>> pickLocalAttachmentPaths({
  List<String> extensions = const [],
}) async {
  final paths = await _fileDialogs.invokeListMethod<String>(
    'pickFiles',
    extensions,
  );
  if (paths == null) throw StateError('File dialog returned no result.');
  return paths;
}

Future<String?> pickLocalProjectDirectory() =>
    _fileDialogs.invokeMethod<String>('pickDirectory');
