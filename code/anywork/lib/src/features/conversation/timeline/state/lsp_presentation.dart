import 'dart:convert';

import '../../../../shared/typed_json.dart';
import 'tool_presentation.dart';

/// LSP 系列工具（`builtin.lsp_query@1`、`builtin.lsp_capabilities@1`、
/// `builtin.lsp_status@1`）的纯展示解析模型。
///
/// 只消费已内联的请求元数据与当前有界输出窗口，不读取工作区文件、不累计全文，
/// 也不按工具名猜测未知契约。
enum TimelineLspOperation {
  goToDefinition,
  goToImplementation,
  findReferences,
  hover,
  documentSymbol,
  workspaceSymbol,
  prepareCallHierarchy,
  incomingCalls,
  outgoingCalls,
  diagnostics,
  unknown;

  static TimelineLspOperation fromWire(String? raw) => switch (raw?.trim()) {
    'goToDefinition' => TimelineLspOperation.goToDefinition,
    'goToImplementation' => TimelineLspOperation.goToImplementation,
    'findReferences' => TimelineLspOperation.findReferences,
    'hover' => TimelineLspOperation.hover,
    'documentSymbol' => TimelineLspOperation.documentSymbol,
    'workspaceSymbol' => TimelineLspOperation.workspaceSymbol,
    'prepareCallHierarchy' => TimelineLspOperation.prepareCallHierarchy,
    'incomingCalls' => TimelineLspOperation.incomingCalls,
    'outgoingCalls' => TimelineLspOperation.outgoingCalls,
    'diagnostics' => TimelineLspOperation.diagnostics,
    _ => TimelineLspOperation.unknown,
  };
}

enum TimelineLspSymbolBadgeTone { typeLike, callable, container, member }

/// 标准 LSP `SymbolKind`（1..26）的紧凑语义标签与视觉分类。
({String badge, TimelineLspSymbolBadgeTone tone}) timelineLspSymbolKindSpec(
  int kind,
) => switch (kind) {
  1 => (badge: 'file', tone: TimelineLspSymbolBadgeTone.container),
  2 => (badge: 'mod', tone: TimelineLspSymbolBadgeTone.container),
  3 => (badge: 'ns', tone: TimelineLspSymbolBadgeTone.container),
  4 => (badge: 'pkg', tone: TimelineLspSymbolBadgeTone.container),
  5 => (badge: 'class', tone: TimelineLspSymbolBadgeTone.typeLike),
  6 => (badge: 'method', tone: TimelineLspSymbolBadgeTone.callable),
  7 => (badge: 'prop', tone: TimelineLspSymbolBadgeTone.member),
  8 => (badge: 'field', tone: TimelineLspSymbolBadgeTone.member),
  9 => (badge: 'ctor', tone: TimelineLspSymbolBadgeTone.callable),
  10 => (badge: 'enum', tone: TimelineLspSymbolBadgeTone.typeLike),
  11 => (badge: 'iface', tone: TimelineLspSymbolBadgeTone.typeLike),
  12 => (badge: 'fn', tone: TimelineLspSymbolBadgeTone.callable),
  13 => (badge: 'var', tone: TimelineLspSymbolBadgeTone.member),
  14 => (badge: 'const', tone: TimelineLspSymbolBadgeTone.member),
  15 => (badge: 'str', tone: TimelineLspSymbolBadgeTone.member),
  16 => (badge: 'num', tone: TimelineLspSymbolBadgeTone.member),
  17 => (badge: 'bool', tone: TimelineLspSymbolBadgeTone.member),
  18 => (badge: 'arr', tone: TimelineLspSymbolBadgeTone.member),
  19 => (badge: 'obj', tone: TimelineLspSymbolBadgeTone.container),
  20 => (badge: 'key', tone: TimelineLspSymbolBadgeTone.member),
  21 => (badge: 'null', tone: TimelineLspSymbolBadgeTone.member),
  22 => (badge: 'variant', tone: TimelineLspSymbolBadgeTone.member),
  23 => (badge: 'struct', tone: TimelineLspSymbolBadgeTone.typeLike),
  24 => (badge: 'event', tone: TimelineLspSymbolBadgeTone.callable),
  25 => (badge: 'op', tone: TimelineLspSymbolBadgeTone.callable),
  26 => (badge: 'type', tone: TimelineLspSymbolBadgeTone.typeLike),
  _ => (badge: 'sym', tone: TimelineLspSymbolBadgeTone.member),
};

sealed class TimelineLspPresentation {
  const TimelineLspPresentation();
}

final class TimelineLspQueryPresentation extends TimelineLspPresentation {
  const TimelineLspQueryPresentation({
    required this.operation,
    required this.body,
    this.rawOperation,
    this.languageId,
    this.filePath,
    this.line,
    this.character,
    this.query,
    this.maxResults,
    this.serverId,
    this.resultCount,
    this.fileCount,
    this.previewOmittedBytes,
  });

  final TimelineLspOperation operation;
  final String? rawOperation;
  final String? languageId;
  final String? filePath;
  final int? line;
  final int? character;
  final String? query;
  final int? maxResults;
  final String? serverId;
  final int? resultCount;
  final int? fileCount;
  final int? previewOmittedBytes;
  final TimelineLspQueryBody body;
}

sealed class TimelineLspQueryBody {
  const TimelineLspQueryBody();
}

/// 尚未产出结果正文（例如失败仅带错误消息，或执行被提前中断）。
final class TimelineLspNoOutputBody extends TimelineLspQueryBody {
  const TimelineLspNoOutputBody();
}

/// 语义查询完成但命中数为 0（含诊断为 0 的健康结果）。
final class TimelineLspEmptyQueryBody extends TimelineLspQueryBody {
  const TimelineLspEmptyQueryBody();
}

final class TimelineLspPosition {
  const TimelineLspPosition({required this.line, required this.character});

  final int line;
  final int character;
}

final class TimelineLspFileLocations {
  const TimelineLspFileLocations({required this.path, required this.positions});

  final String path;
  final List<TimelineLspPosition> positions;
}

final class TimelineLspLocationsBody extends TimelineLspQueryBody {
  const TimelineLspLocationsBody({required this.groups});

  final List<TimelineLspFileLocations> groups;
}

final class TimelineLspHoverBody extends TimelineLspQueryBody {
  const TimelineLspHoverBody({required this.markdown});

  final String markdown;
}

final class TimelineLspDocumentSymbolItem {
  const TimelineLspDocumentSymbolItem({
    required this.depth,
    required this.name,
    required this.kind,
  });

  final int depth;
  final String name;
  final int kind;
}

final class TimelineLspDocumentSymbolsBody extends TimelineLspQueryBody {
  const TimelineLspDocumentSymbolsBody({required this.items});

  final List<TimelineLspDocumentSymbolItem> items;
}

final class TimelineLspWorkspaceSymbolItem {
  const TimelineLspWorkspaceSymbolItem({
    required this.name,
    required this.kind,
    required this.path,
  });

  final String name;
  final int kind;
  final String path;
}

final class TimelineLspWorkspaceSymbolsBody extends TimelineLspQueryBody {
  const TimelineLspWorkspaceSymbolsBody({
    required this.items,
    this.omittedCount,
  });

  final List<TimelineLspWorkspaceSymbolItem> items;
  final int? omittedCount;
}

final class TimelineLspCallItem {
  const TimelineLspCallItem({required this.name, required this.path});

  final String name;
  final String path;
}

final class TimelineLspCallHierarchyBody extends TimelineLspQueryBody {
  const TimelineLspCallHierarchyBody({required this.items});

  final List<TimelineLspCallItem> items;
}

final class TimelineLspDiagnosticItem {
  const TimelineLspDiagnosticItem({
    required this.path,
    required this.line,
    required this.character,
    required this.message,
    this.code,
    this.source,
  });

  final String path;
  final int line;
  final int character;
  final String message;
  final String? code;
  final String? source;
}

final class TimelineLspDiagnosticsBody extends TimelineLspQueryBody {
  const TimelineLspDiagnosticsBody({required this.items, this.omittedCount});

  final List<TimelineLspDiagnosticItem> items;
  final int? omittedCount;
}

/// 非标准 JSON 或无法按已知条目解析的纯文本安全回退。
final class TimelineLspRawTextBody extends TimelineLspQueryBody {
  const TimelineLspRawTextBody({required this.text});

  final String text;
}

final class TimelineLspOperationSpec {
  const TimelineLspOperationSpec({required this.operation, required this.raw});

  final TimelineLspOperation operation;
  final String raw;
}

final class TimelineLspCapabilityServer {
  const TimelineLspCapabilityServer({
    required this.id,
    required this.displayName,
    required this.languageIds,
    required this.operations,
    required this.availability,
    required this.ready,
  });

  final String id;
  final String displayName;
  final List<String> languageIds;
  final List<TimelineLspOperationSpec> operations;
  final String availability;
  final bool ready;
}

final class TimelineLspCapabilitiesPresentation
    extends TimelineLspPresentation {
  const TimelineLspCapabilitiesPresentation({
    required this.servers,
    required this.hasOutput,
    this.previewOmittedBytes,
    this.fallbackText,
  });

  final List<TimelineLspCapabilityServer> servers;
  final bool hasOutput;
  final int? previewOmittedBytes;
  final String? fallbackText;
}

final class TimelineLspServerStatusItem {
  const TimelineLspServerStatusItem({
    required this.id,
    required this.displayName,
    required this.languageIds,
    required this.phase,
    required this.availability,
    required this.activity,
    this.configurationPath,
    this.message,
    this.activityTitle,
    this.activityMessage,
    this.activityPercentage,
    this.lastError,
  });

  final String id;
  final String displayName;
  final List<String> languageIds;
  final String? configurationPath;
  final String phase;
  final String availability;
  final String? message;
  final String activity;
  final String? activityTitle;
  final String? activityMessage;
  final int? activityPercentage;
  final String? lastError;
}

final class TimelineLspStatusPresentation extends TimelineLspPresentation {
  const TimelineLspStatusPresentation({
    required this.servers,
    required this.hasOutput,
    this.workspaceRoot,
    this.configurationDirectory,
    this.previewOmittedBytes,
    this.fallbackText,
  });

  final String? workspaceRoot;
  final String? configurationDirectory;
  final List<TimelineLspServerStatusItem> servers;
  final bool hasOutput;
  final int? previewOmittedBytes;
  final String? fallbackText;
}

/// 从 `lsp_query` 参数提取操作枚举，供折叠行标题与展开头部共用。
TimelineLspOperation timelineLspQueryOperation(TimelineToolPresentation item) {
  final args = decodeJsonObject(item.arguments);
  return TimelineLspOperation.fromWire(jsonStringValue(args['operation']));
}

/// 解析 LSP 工具卡片的请求上下文与有界输出文本。
TimelineLspPresentation? parseTimelineLspPresentation(
  TimelineToolPresentation tool, {
  String? outputOverride,
}) {
  final output = outputOverride ?? tool.output;
  return switch (tool.presentationContract) {
    'builtin.lsp_query@1' => _parseQuery(tool.arguments, output),
    'builtin.lsp_capabilities@1' => _parseCapabilities(output),
    'builtin.lsp_status@1' => _parseStatus(output),
    _ => null,
  };
}

final _previewTruncationPattern = RegExp(
  r'\n?\[LSP preview omitted (\d+) bytes; full result retained in history\.\]\s*$',
);

({String content, int? omittedBytes}) _stripPreviewEnvelope(String raw) {
  final match = _previewTruncationPattern.firstMatch(raw);
  if (match == null) return (content: raw, omittedBytes: null);
  final omitted = int.tryParse(match.group(1) ?? '');
  return (content: raw.substring(0, match.start), omittedBytes: omitted);
}

int? _jsonInt(Object? value) => switch (value) {
  final int number => number,
  final num number => number.toInt(),
  final String text => int.tryParse(text.trim()),
  _ => null,
};

List<String> _jsonStringList(Object? value) {
  if (value is! List) return const [];
  return [for (final entry in value) ?jsonStringValue(entry)];
}

Map<String, Object?>? _tryDecodeJsonMap(String text) {
  final trimmed = text.trim();
  if (!trimmed.startsWith('{')) return null;
  try {
    final decoded = jsonDecode(trimmed);
    if (decoded is Map) {
      return jsonObject(decoded);
    }
    return null;
  } on FormatException {
    return null;
  }
}

TimelineLspQueryPresentation _parseQuery(String arguments, String rawOutput) {
  final args = decodeJsonObject(arguments);
  final argOpRaw = jsonStringValue(args['operation']);
  final languageId = jsonStringValue(args['languageId']);
  final filePath = jsonStringValue(args['filePath']);
  final line = _jsonInt(args['line']);
  final character = _jsonInt(args['character']);
  final query = jsonStringValue(args['query']);
  final maxResults = _jsonInt(args['maxResults']);

  if (rawOutput.trim().isEmpty) {
    return TimelineLspQueryPresentation(
      operation: TimelineLspOperation.fromWire(argOpRaw),
      rawOperation: argOpRaw,
      languageId: languageId,
      filePath: filePath,
      line: line,
      character: character,
      query: query,
      maxResults: maxResults,
      body: const TimelineLspNoOutputBody(),
    );
  }

  final stripped = _stripPreviewEnvelope(rawOutput);
  final json = _tryDecodeJsonMap(stripped.content);
  if (json != null && json.containsKey('result')) {
    final opRaw = jsonStringValue(json['operation']) ?? argOpRaw;
    final op = TimelineLspOperation.fromWire(opRaw);
    final serverId = jsonStringValue(json['serverId']);
    final resultText = json['result']?.toString() ?? '';
    final resultCount = _jsonInt(json['resultCount']);
    final fileCount = _jsonInt(json['fileCount']);
    return TimelineLspQueryPresentation(
      operation: op,
      rawOperation: opRaw,
      languageId: languageId,
      filePath: filePath,
      line: line,
      character: character,
      query: query,
      maxResults: maxResults,
      serverId: serverId,
      resultCount: resultCount,
      fileCount: fileCount,
      previewOmittedBytes: stripped.omittedBytes,
      body: _parseQueryBody(
        op,
        resultText,
        resultCount: resultCount,
        truncated: stripped.omittedBytes != null,
      ),
    );
  }

  // 处理 12 KiB 预览截断导致的半截 QueryResult JSON，仅提取完整行且保留截断提示。
  if (stripped.omittedBytes != null) {
    final partial = _extractTruncatedQueryResult(stripped.content);
    if (partial != null) {
      final opRaw = partial.operation ?? argOpRaw;
      final op = TimelineLspOperation.fromWire(opRaw);
      return TimelineLspQueryPresentation(
        operation: op,
        rawOperation: opRaw,
        languageId: languageId,
        filePath: filePath,
        line: line,
        character: character,
        query: query,
        maxResults: maxResults,
        serverId: partial.serverId,
        previewOmittedBytes: stripped.omittedBytes,
        body: _parseQueryBody(
          op,
          partial.resultText,
          resultCount: null,
          truncated: true,
        ),
      );
    }
  }

  return TimelineLspQueryPresentation(
    operation: TimelineLspOperation.fromWire(argOpRaw),
    rawOperation: argOpRaw,
    languageId: languageId,
    filePath: filePath,
    line: line,
    character: character,
    query: query,
    maxResults: maxResults,
    previewOmittedBytes: stripped.omittedBytes,
    body: TimelineLspRawTextBody(text: stripped.content.trim()),
  );
}

({String? operation, String? serverId, String resultText})?
_extractTruncatedQueryResult(String content) {
  const marker = '"result":"';
  final markerIndex = content.indexOf(marker);
  if (markerIndex < 0) return null;
  final header = content.substring(0, markerIndex);
  final opMatch = RegExp(r'"operation"\s*:\s*"([^"]+)"').firstMatch(header);
  final serverMatch = RegExp(r'"serverId"\s*:\s*"([^"]+)"').firstMatch(header);
  final rawSlice = content.substring(markerIndex + marker.length);
  final decoded = _unescapePartialJsonString(rawSlice);
  final lastNewline = decoded.lastIndexOf('\n');
  final completeLines = lastNewline >= 0
      ? decoded.substring(0, lastNewline)
      : decoded;
  return (
    operation: opMatch?.group(1),
    serverId: serverMatch?.group(1),
    resultText: completeLines,
  );
}

String _unescapePartialJsonString(String slice) {
  final buffer = StringBuffer();
  var index = 0;
  while (index < slice.length) {
    final char = slice[index];
    if (char == '"') break;
    if (char != r'\') {
      buffer.write(char);
      index++;
      continue;
    }
    if (index + 1 >= slice.length) break;
    final next = slice[index + 1];
    switch (next) {
      case 'n':
        buffer.write('\n');
        index += 2;
      case 'r':
        buffer.write('\r');
        index += 2;
      case 't':
        buffer.write('\t');
        index += 2;
      case '"':
        buffer.write('"');
        index += 2;
      case r'\':
        buffer.write(r'\');
        index += 2;
      case '/':
        buffer.write('/');
        index += 2;
      case 'u':
        if (index + 6 > slice.length) return buffer.toString();
        final code = int.tryParse(
          slice.substring(index + 2, index + 6),
          radix: 16,
        );
        if (code != null) buffer.writeCharCode(code);
        index += 6;
      default:
        buffer.write(next);
        index += 2;
    }
  }
  return buffer.toString();
}

TimelineLspQueryBody _parseQueryBody(
  TimelineLspOperation operation,
  String text, {
  required int? resultCount,
  required bool truncated,
}) {
  final normalized = text.replaceAll('\r\n', '\n');
  final trimmed = normalized.trim();
  if (!truncated && resultCount == 0) {
    return const TimelineLspEmptyQueryBody();
  }
  if (trimmed.isEmpty) {
    return const TimelineLspEmptyQueryBody();
  }
  return switch (operation) {
    TimelineLspOperation.goToDefinition ||
    TimelineLspOperation.goToImplementation ||
    TimelineLspOperation.findReferences => _parseLocationsBody(trimmed),
    TimelineLspOperation.hover => _parseHoverBody(trimmed),
    TimelineLspOperation.documentSymbol => _parseDocumentSymbolsBody(
      normalized,
    ),
    TimelineLspOperation.workspaceSymbol => _parseWorkspaceSymbolsBody(trimmed),
    TimelineLspOperation.prepareCallHierarchy ||
    TimelineLspOperation.incomingCalls ||
    TimelineLspOperation.outgoingCalls => _parseCallHierarchyBody(trimmed),
    TimelineLspOperation.diagnostics => _parseDiagnosticsBody(trimmed),
    TimelineLspOperation.unknown => TimelineLspRawTextBody(text: trimmed),
  };
}

final _foundLocationsHeader = RegExp(
  r'^Found \d+ [a-zA-Z]+(?: across \d+ files)?:$',
);
final _locationLinePattern = RegExp(r'^(.+):(\d+):(\d+)$');

TimelineLspQueryBody _parseLocationsBody(String text) {
  if (text == 'No definitions found.' || text == 'No references found.') {
    return const TimelineLspEmptyQueryBody();
  }
  final lines = text.split('\n');
  final grouped = <String, List<TimelineLspPosition>>{};
  var startIndex = 0;
  if (lines.isNotEmpty && _foundLocationsHeader.hasMatch(lines.first.trim())) {
    startIndex = 1;
  }
  for (var index = startIndex; index < lines.length; index++) {
    final line = lines[index].trim();
    if (line.isEmpty) continue;
    final match = _locationLinePattern.firstMatch(line);
    if (match == null) {
      return TimelineLspRawTextBody(text: text);
    }
    final path = match.group(1)!.trim();
    final lineNumber = int.tryParse(match.group(2)!);
    final character = int.tryParse(match.group(3)!);
    if (path.isEmpty || lineNumber == null || character == null) {
      return TimelineLspRawTextBody(text: text);
    }
    (grouped[path] ??= <TimelineLspPosition>[]).add(
      TimelineLspPosition(line: lineNumber, character: character),
    );
  }
  if (grouped.isEmpty) {
    return const TimelineLspEmptyQueryBody();
  }
  return TimelineLspLocationsBody(
    groups: [
      for (final entry in grouped.entries)
        TimelineLspFileLocations(path: entry.key, positions: entry.value),
    ],
  );
}

TimelineLspQueryBody _parseHoverBody(String text) {
  if (text == 'No hover information found.') {
    return const TimelineLspEmptyQueryBody();
  }
  return TimelineLspHoverBody(markdown: text);
}

final _documentSymbolLinePattern = RegExp(r'^( *)(.+?) kind=(\d+)\s*$');

TimelineLspQueryBody _parseDocumentSymbolsBody(String text) {
  final trimmed = text.trim();
  if (trimmed == 'No document symbols found.') {
    return const TimelineLspEmptyQueryBody();
  }
  final items = <TimelineLspDocumentSymbolItem>[];
  for (final rawLine in text.split('\n')) {
    if (rawLine.trim().isEmpty) continue;
    final match = _documentSymbolLinePattern.firstMatch(rawLine);
    if (match == null) {
      return TimelineLspRawTextBody(text: trimmed);
    }
    final spaces = match.group(1)!.length;
    final name = match.group(2)!.trim();
    final kind = int.tryParse(match.group(3)!) ?? 0;
    items.add(
      TimelineLspDocumentSymbolItem(depth: spaces ~/ 2, name: name, kind: kind),
    );
  }
  if (items.isEmpty) return const TimelineLspEmptyQueryBody();
  return TimelineLspDocumentSymbolsBody(items: items);
}

final _workspaceSymbolLinePattern = RegExp(r'^(.+) kind=(\d+) (.*)$');
final _omittedSymbolsPattern = RegExp(r'^\.\.\. (\d+) more symbols omitted$');

TimelineLspQueryBody _parseWorkspaceSymbolsBody(String text) {
  if (text == 'No workspace symbols found.') {
    return const TimelineLspEmptyQueryBody();
  }
  final items = <TimelineLspWorkspaceSymbolItem>[];
  int? omittedCount;
  for (final rawLine in text.split('\n')) {
    final line = rawLine.trim();
    if (line.isEmpty) continue;
    final omittedMatch = _omittedSymbolsPattern.firstMatch(line);
    if (omittedMatch != null) {
      omittedCount = int.tryParse(omittedMatch.group(1)!);
      continue;
    }
    final match = _workspaceSymbolLinePattern.firstMatch(line);
    if (match == null) {
      return TimelineLspRawTextBody(text: text);
    }
    items.add(
      TimelineLspWorkspaceSymbolItem(
        name: match.group(1)!.trim(),
        kind: int.tryParse(match.group(2)!) ?? 0,
        path: match.group(3)!.trim(),
      ),
    );
  }
  if (items.isEmpty && omittedCount == null) {
    return const TimelineLspEmptyQueryBody();
  }
  return TimelineLspWorkspaceSymbolsBody(
    items: items,
    omittedCount: omittedCount,
  );
}

final _callItemLinePattern = RegExp(r'^(.+?)\s+(\S+)$');

TimelineLspQueryBody _parseCallHierarchyBody(String text) {
  if (text == 'No call hierarchy results found.') {
    return const TimelineLspEmptyQueryBody();
  }
  final items = <TimelineLspCallItem>[];
  for (final rawLine in text.split('\n')) {
    final line = rawLine.trim();
    if (line.isEmpty) continue;
    final match = _callItemLinePattern.firstMatch(line);
    if (match == null) {
      return TimelineLspRawTextBody(text: text);
    }
    items.add(
      TimelineLspCallItem(
        name: match.group(1)!.trim(),
        path: match.group(2)!.trim(),
      ),
    );
  }
  if (items.isEmpty) return const TimelineLspEmptyQueryBody();
  return TimelineLspCallHierarchyBody(items: items);
}

final _diagnosticStartPattern = RegExp(r'^(\S.*?):(\d+):(\d+)\s+(.+)$');
final _diagnosticMetaSuffixPattern = RegExp(
  r'^(.*?)(?:\s+\[([^\]]+)\])?(?:\s+\(([^)]+)\))?$',
  dotAll: true,
);
final _omittedDiagnosticsPattern = RegExp(
  r'^\.\.\. (\d+) more diagnostics omitted$',
);

TimelineLspQueryBody _parseDiagnosticsBody(String text) {
  if (text == 'No diagnostics.') {
    return const TimelineLspEmptyQueryBody();
  }
  final rawEntries = <({String path, int line, int character, String rest})>[];
  int? omittedCount;
  for (final rawLine in text.split('\n')) {
    final trimmed = rawLine.trim();
    if (trimmed.isEmpty) continue;
    final omittedMatch = _omittedDiagnosticsPattern.firstMatch(trimmed);
    if (omittedMatch != null) {
      omittedCount = int.tryParse(omittedMatch.group(1)!);
      continue;
    }
    final match = _diagnosticStartPattern.firstMatch(rawLine);
    if (match != null) {
      final line = int.tryParse(match.group(2)!);
      final character = int.tryParse(match.group(3)!);
      if (line != null && character != null) {
        rawEntries.add((
          path: match.group(1)!.trim(),
          line: line,
          character: character,
          rest: match.group(4)!.trim(),
        ));
        continue;
      }
    }
    if (rawEntries.isNotEmpty) {
      final last = rawEntries.removeLast();
      rawEntries.add((
        path: last.path,
        line: last.line,
        character: last.character,
        rest: '${last.rest}\n$trimmed',
      ));
    } else {
      return TimelineLspRawTextBody(text: text);
    }
  }
  if (rawEntries.isEmpty && omittedCount == null) {
    return const TimelineLspEmptyQueryBody();
  }
  final items = <TimelineLspDiagnosticItem>[];
  for (final entry in rawEntries) {
    final suffix = _diagnosticMetaSuffixPattern.firstMatch(entry.rest);
    final message = (suffix?.group(1) ?? entry.rest).trim();
    items.add(
      TimelineLspDiagnosticItem(
        path: entry.path,
        line: entry.line,
        character: entry.character,
        message: message.isEmpty ? entry.rest : message,
        code: suffix?.group(2)?.trim(),
        source: suffix?.group(3)?.trim(),
      ),
    );
  }
  return TimelineLspDiagnosticsBody(items: items, omittedCount: omittedCount);
}

TimelineLspCapabilitiesPresentation _parseCapabilities(String rawOutput) {
  if (rawOutput.trim().isEmpty) {
    return const TimelineLspCapabilitiesPresentation(
      servers: [],
      hasOutput: false,
    );
  }
  final stripped = _stripPreviewEnvelope(rawOutput);
  final json = _tryDecodeJsonMap(stripped.content);
  if (json == null || json['servers'] is! List) {
    return TimelineLspCapabilitiesPresentation(
      servers: const [],
      hasOutput: true,
      previewOmittedBytes: stripped.omittedBytes,
      fallbackText: stripped.content.trim(),
    );
  }
  final servers = <TimelineLspCapabilityServer>[];
  for (final rawServer in json['servers'] as List) {
    final map = jsonObject(rawServer);
    if (map.isEmpty) continue;
    final id = jsonStringValue(map['id']) ?? '';
    final displayName = jsonStringValue(map['displayName']) ?? id;
    final operations = [
      for (final op in _jsonStringList(map['operations']))
        TimelineLspOperationSpec(
          operation: TimelineLspOperation.fromWire(op),
          raw: op,
        ),
    ];
    servers.add(
      TimelineLspCapabilityServer(
        id: id,
        displayName: displayName.isEmpty ? 'LSP' : displayName,
        languageIds: _jsonStringList(map['languageIds']),
        operations: operations,
        availability: jsonStringValue(map['availability']) ?? 'available',
        ready: map['ready'] == true,
      ),
    );
  }
  return TimelineLspCapabilitiesPresentation(
    servers: servers,
    hasOutput: true,
    previewOmittedBytes: stripped.omittedBytes,
  );
}

TimelineLspStatusPresentation _parseStatus(String rawOutput) {
  if (rawOutput.trim().isEmpty) {
    return const TimelineLspStatusPresentation(servers: [], hasOutput: false);
  }
  final stripped = _stripPreviewEnvelope(rawOutput);
  final json = _tryDecodeJsonMap(stripped.content);
  if (json == null || json['servers'] is! List) {
    return TimelineLspStatusPresentation(
      servers: const [],
      hasOutput: true,
      previewOmittedBytes: stripped.omittedBytes,
      fallbackText: stripped.content.trim(),
    );
  }
  final servers = <TimelineLspServerStatusItem>[];
  for (final rawServer in json['servers'] as List) {
    final map = jsonObject(rawServer);
    if (map.isEmpty) continue;
    final id = jsonStringValue(map['id']) ?? '';
    final displayName = jsonStringValue(map['displayName']) ?? id;
    servers.add(
      TimelineLspServerStatusItem(
        id: id,
        displayName: displayName.isEmpty ? 'LSP' : displayName,
        languageIds: _jsonStringList(map['languageIds']),
        configurationPath: jsonStringValue(map['configurationPath']),
        phase: jsonStringValue(map['phase']) ?? 'unknown',
        availability: jsonStringValue(map['availability']) ?? 'unknown',
        message: jsonStringValue(map['message']),
        activity: jsonStringValue(map['activity']) ?? 'idle',
        activityTitle: jsonStringValue(map['activityTitle']),
        activityMessage: jsonStringValue(map['activityMessage']),
        activityPercentage: _jsonInt(map['activityPercentage']),
        lastError: jsonStringValue(map['lastError']),
      ),
    );
  }
  return TimelineLspStatusPresentation(
    workspaceRoot: jsonStringValue(json['workspaceRoot']),
    configurationDirectory: jsonStringValue(json['configurationDirectory']),
    servers: servers,
    hasOutput: true,
    previewOmittedBytes: stripped.omittedBytes,
  );
}
