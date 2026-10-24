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
