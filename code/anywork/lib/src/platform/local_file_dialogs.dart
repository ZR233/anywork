import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

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

/// The native chooser owns overwrite confirmation. No bytes are read and no
/// file is created when the user cancels or the original display retires.
Future<bool> saveArchivedFile({
  required String filename,
  required Future<Uint8List> Function() readBytes,
  required bool Function() isActive,
}) async {
  if (!isActive()) return false;
  final path = await _fileDialogs.invokeMethod<String>('saveFile', filename);
  if (path == null || !isActive()) return false;
  if (!p.isAbsolute(path)) throw StateError('保存位置不是绝对路径');
  final bytes = await readBytes();
  if (!isActive()) return false;
  await File(path).writeAsBytes(bytes, flush: true);
  return true;
}

Future<void> revealLocalFile(
  String path, {
  required bool Function() isActive,
}) async {
  if (!isActive()) return;
  if (!p.isAbsolute(path)) throw StateError('本地文件来源不是绝对路径');
  if (!await File(path).exists()) throw StateError('原文件已不存在：$path');
  if (!isActive()) return;
  await _fileDialogs.invokeMethod<void>('revealFile', path);
}

/// 选择一个本地可执行文件（例如官方 ACP server 程序）。
///
/// 复用同一个原生文件对话框通道，但不带扩展名过滤：ACP server 是不带后缀的可执行
/// 文件，按扩展名过滤会把它排除。用户取消时返回 null，不伪造路径。
Future<String?> pickLocalExecutablePath() async {
  final paths = await _fileDialogs.invokeListMethod<String>(
    'pickFiles',
    const [],
  );
  if (paths == null || paths.isEmpty) return null;
  return paths.first;
}
