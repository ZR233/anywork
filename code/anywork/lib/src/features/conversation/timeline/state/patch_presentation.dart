import '../../../../shared/typed_json.dart';

/// `builtin.apply_patch@1` 的纯展示解析结果（design/26 §26.9.1）。
///
/// 只消费请求里的修改片段事实，不读取工作区文件、不计算第二份差异、
/// 不推断原文件行号；解析失败由调用方呈现明确的不可用提示。
enum TimelinePatchLineKind { addition, deletion, context }

enum TimelinePatchFileOp { add, update, delete }

final class TimelinePatchLine {
  const TimelinePatchLine({required this.kind, required this.text});

  /// 不含 `+`/`-`/前导空格控制前缀的正文，保留原始缩进与空行。
  final String text;
  final TimelinePatchLineKind kind;
}

final class TimelinePatchChunk {
  const TimelinePatchChunk({required this.context, required this.lines});

  /// `@@ <search context>` 的定位文本；裸 `@@` 与无头片段为 null。
  final String? context;
  final List<TimelinePatchLine> lines;
}

final class TimelinePatchFile {
  const TimelinePatchFile({
    required this.op,
    required this.path,
    this.moveTo,
    required this.chunks,
  });

  final TimelinePatchFileOp op;
  final String path;
  final String? moveTo;
  final List<TimelinePatchChunk> chunks;
}

final class TimelinePatchDocument {
  const TimelinePatchDocument({required this.files});

  final List<TimelinePatchFile> files;
}

/// 从 apply_patch 参数中提取补丁正文：仅接受 freeform 正文或当前契约的
/// JSON `{"input": "..."}` 信封，不对其他 JSON 字段做回退猜测。
String timelineApplyPatchSource(String arguments) {
  final input = jsonStringValue(decodeJsonObject(arguments)['input']);
  return input ?? arguments;
}

const _beginPatch = '*** Begin Patch';
const _endPatch = '*** End Patch';
const _addFile = '*** Add File: ';
const _updateFile = '*** Update File: ';
const _deleteFile = '*** Delete File: ';
const _moveTo = '*** Move to: ';
const _environmentId = '*** Environment ID: ';
const _eofMarker = '*** End of File';

/// 解析 Codex 风格补丁为片段展示模型。
///
/// 协议边界：`*** Begin Patch` 必须是首行、`*** End Patch` 必须是末行
///（仅整体信封空白可省略）；控制标记一律顶格，缩进的标记行按源码内容
/// 处理，不做全局扫描或吞掉块外文本。结构不完整或含不支持语法时返回
/// null，由调用方提示不可用，不回退原始文本。
TimelinePatchDocument? parseTimelinePatch(String raw) {
  final text = raw.trim();
  if (text.isEmpty) return null;
  final lines = [
    for (final line in text.split('\n'))
      line.endsWith('\r') ? line.substring(0, line.length - 1) : line,
  ];
  if (lines.first.trimRight() != _beginPatch) return null;
  if (lines.last.trimRight() != _endPatch) return null;
  final body = lines.sublist(1, lines.length - 1);
  var index = 0;
  if (body.isNotEmpty && body[index].startsWith(_environmentId)) {
    if (body[index].substring(_environmentId.length).trim().isEmpty) {
      return null;
    }
    index++;
  }
  final files = <TimelinePatchFile>[];
  while (index < body.length) {
    final line = body[index];
    if (line.trim().isEmpty) {
      index++;
      continue;
    }
    if (line.startsWith(_addFile)) {
      final path = line.substring(_addFile.length);
      if (path.trim().isEmpty) return null;
      index++;
      final linesToAdd = <TimelinePatchLine>[];
      while (index < body.length && body[index].startsWith('+')) {
        linesToAdd.add(
          TimelinePatchLine(
            kind: TimelinePatchLineKind.addition,
            text: body[index].substring(1),
          ),
        );
        index++;
      }
      files.add(
        TimelinePatchFile(
          op: TimelinePatchFileOp.add,
          path: path,
          chunks: [TimelinePatchChunk(context: null, lines: linesToAdd)],
        ),
      );
    } else if (line.startsWith(_deleteFile)) {
      final path = line.substring(_deleteFile.length);
      if (path.trim().isEmpty) return null;
      files.add(
        TimelinePatchFile(
          op: TimelinePatchFileOp.delete,
          path: path,
          chunks: const [],
        ),
      );
      index++;
    } else if (line.startsWith(_updateFile)) {
      final path = line.substring(_updateFile.length);
      if (path.trim().isEmpty) return null;
      index++;
      String? moveTo;
      if (index < body.length && body[index].startsWith(_moveTo)) {
        moveTo = body[index].substring(_moveTo.length);
        if (moveTo.trim().isEmpty) return null;
        index++;
      }
      final chunks = <TimelinePatchChunk>[];
      while (index < body.length) {
        final candidate = body[index];
        if (candidate.trim().isEmpty) {
          index++;
          continue;
        }
        if (candidate.startsWith('*** ')) break;
        final chunk = _parseChunk(body, index);
        if (chunk == null) return null;
        chunks.add(chunk.$1);
        index += chunk.$2;
      }
      if (chunks.isEmpty && moveTo == null) return null;
      files.add(
        TimelinePatchFile(
          op: TimelinePatchFileOp.update,
          path: path,
          moveTo: moveTo,
          chunks: chunks,
        ),
      );
    } else {
      return null;
    }
  }
  if (files.isEmpty) return null;
  return TimelinePatchDocument(files: files);
}

/// 解析一个 update 片段：可选顶格 `@@ [context]` 头 + 至少一行修改；
/// 返回 null 表示语法不受支持或片段为空。
(TimelinePatchChunk, int)? _parseChunk(List<String> body, int start) {
  var index = start;
  final header = body[index];
  String? context;
  if (header.startsWith('@@')) {
    final trimmed = header.trim();
    if (trimmed == '@@') {
      context = null;
      index++;
    } else if (trimmed.startsWith('@@ -')) {
      // unified diff 的 `@@ -1,2 +3,4` 范围头不受支持。
      return null;
    } else if (trimmed.startsWith('@@ ')) {
      context = trimmed.substring(3).trim();
      if (context.isEmpty) context = null;
      index++;
    } else {
      // `@@xyz` 等非协议片段头形态不受支持。
      return null;
    }
  }
  final lines = <TimelinePatchLine>[];
  while (index < body.length) {
    final line = body[index];
    if (line.trimRight() == _eofMarker) {
      index++;
      break;
    }
    if (line.startsWith('*** ') || line.startsWith('@@')) break;
    if (line.startsWith('+')) {
      lines.add(
        TimelinePatchLine(
          kind: TimelinePatchLineKind.addition,
          text: line.substring(1),
        ),
      );
    } else if (line.startsWith('-')) {
      lines.add(
        TimelinePatchLine(
          kind: TimelinePatchLineKind.deletion,
          text: line.substring(1),
        ),
      );
    } else {
      lines.add(
        TimelinePatchLine(
          kind: TimelinePatchLineKind.context,
          text: line.startsWith(' ') ? line.substring(1) : line,
        ),
      );
    }
    index++;
  }
  if (lines.isEmpty) return null;
  return (TimelinePatchChunk(context: context, lines: lines), index - start);
}
