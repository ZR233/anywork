import 'dart:convert';

import 'package:anywork_client/acp_sessions.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

import 'agy_call_validator.dart';
import 'agy_json_evidence.dart';

// Decode only formal ACP raw values or one same-call JSON content container,
// followed by the existing single MCP structuredContent envelope.
// Unknown provider wrappers fail visibly; assistant prose is never evidence.
final class AgyHostTrace extends AgyCallValidator<AcpConversationToolItem> {
  AgyHostTrace(Iterable<AcpConversationContentItem> content)
    : calls = content.whereType<AcpConversationToolItem>().toList();

  final List<AcpConversationToolItem> calls;

  @override
  List<AcpConversationToolItem> named(String name) =>
      calls.where((call) => canonicalName(call.fields.name) == name).toList();

  static String? canonicalName(String? raw) {
    if (raw == null) return null;
    if (raw.startsWith('mcp_anywork_anywork_')) {
      return raw.substring('mcp_anywork_'.length);
    }
    return raw.startsWith('anywork_') ? raw : null;
  }

  List<Map<String, Object?>> verifyCompletedHostCalls() {
    final hostCalls = calls
        .where((call) => canonicalName(call.fields.name) != null)
        .toList();
    expect(
      hostCalls,
      isNotEmpty,
      reason: 'Expected real Host MCP tool updates',
    );
    expect(
      hostCalls.map((call) => call.fields.status),
      everyElement(AcpToolCallStatusView.completed),
    );
    return [
      for (final call in hostCalls)
        {
          'toolCallId': call.toolCallId.value,
          'name': call.fields.name,
          'canonicalName': canonicalName(call.fields.name),
          'status': call.fields.status?.name,
          'outputEvidence': _outputOrigin(
            call,
            _contentContainers(call)
                .map((candidate) => candidate.index)
                .toList(),
          ),
        },
    ];
  }

  @override
  Map<String, dynamic> input(AcpConversationToolItem call) =>
      _object(_value(call.fields.rawInput), 'ACP tool rawInput');

  // agy acceptance only: rawInput/input() remain the unmodified peer report.
  Map<String, dynamic> mcpArguments(AcpConversationToolItem call) {
    if (canonicalName(call.fields.name) == null) {
      throw StateError('MCP argument projection requires a formal Host tool');
    }
    return _agyMcpArguments(input(call));
  }

  @override
  dynamic output(AcpConversationToolItem call) {
    dynamic value;
    if (_hasRawOutput(call)) {
      value = _value(call.fields.rawOutput);
      if (value is String) {
        try {
          value = jsonDecode(value);
        } on FormatException {
          throw StateError('Invalid formal rawOutput JSON; body not logged');
        }
      }
    } else {
      final candidates = _contentContainers(call);
      if (candidates.length != 1) {
        throw StateError(
          'Expected exactly one same-call formal JSON container content block; '
          'found ${candidates.length}',
        );
      }
      value = candidates.single.value;
    }
    if (value is Map<String, dynamic> &&
        value.containsKey('structuredContent')) {
      expect(value['isError'], isNot(true), reason: 'Host MCP tool failed');
      value = value['structuredContent'];
    }
    expect(call.fields.status, AcpToolCallStatusView.completed);
    return value;
  }

  List<Map<String, Object?>> diagnostics({
    required Set<String> safeCommands,
    required Set<String> markers,
  }) => [
    for (final call in calls)
      {
        'toolCallId': call.toolCallId.value,
        'name': call.fields.name,
        'canonicalName': canonicalName(call.fields.name),
        'status': call.fields.status?.name,
        'rawOutputState': _rawOutputState(call.fields.rawOutput),
        'rawOutputType': call.fields.rawOutput?.runtimeType.toString(),
        ..._contentDiagnostics(call, safeCommands, markers),
        if (canonicalName(call.fields.name) != null) ...{
          ..._inputDiagnostics(call.fields.rawInput, safeCommands, markers),
          'rawOutput': _diagnosticJson(
            _value(call.fields.rawOutput),
            safeCommands,
            markers,
          ),
        },
      },
  ];
}

Map<String, Object?> _inputDiagnostics(
  AcpJsonValue? raw,
  Set<String> safeCommands,
  Set<String> markers,
) {
  dynamic value;
  try {
    value = _value(raw);
  } on StateError {
    // An unsupported original input must not hide the primary failure while
    // writing a snapshot. Business input()/matching remain strict and unchanged.
    return {
      'rawInputState': 'unrepresentable',
      'rawInputType': raw.runtimeType.toString(),
      'rawInput': {'unsupportedType': raw.runtimeType.toString()},
    };
  }
  return {
    'rawInputState': raw == null
        ? 'missing'
        : raw is AcpJsonNull
        ? 'null'
        : 'present',
    'rawInputType': _jsonType(value),
    'rawInput': _diagnosticJson(value, safeCommands, markers),
    if (value is Map<String, dynamic>)
      'rawInputFingerprint': agyArgumentsFingerprint(value),
    if (value is Map<String, dynamic>)
      'agyMcpArgumentsProjection': _mcpProjectionDiagnostic(value),
  };
}

Map<String, dynamic> _agyMcpArguments(Map<String, dynamic> original) {
  if (original.containsKey('toolSummary') &&
      original['toolSummary'] is! String) {
    throw StateError('agy toolSummary metadata must be a string; body private');
  }
  return Map<String, dynamic>.of(original)..remove('toolSummary');
}

Map<String, Object?> _mcpProjectionDiagnostic(Map<String, dynamic> original) {
  final present = original.containsKey('toolSummary');
  final valid = !present || original['toolSummary'] is String;
  return {
    'origin': 'agy-acceptance-mcp-arguments',
    'hasKnownToolSummary': present,
    if (present) 'knownToolSummaryType': _jsonType(original['toolSummary']),
    'state': valid ? 'available' : 'invalid-toolSummary-type',
    if (valid)
      'argumentsFingerprint': agyArgumentsFingerprint(
        _agyMcpArguments(original),
      ),
  };
}

bool _hasRawOutput(AcpConversationToolItem call) =>
    call.fields.rawOutput != null && call.fields.rawOutput is! AcpJsonNull;

String _rawOutputState(AcpJsonValue? value) => switch (value) {
  null => 'missing',
  AcpJsonNull() => 'explicitNull',
  _ => 'value',
};

({bool decodable, dynamic value}) _wholeJson(String text) {
  try {
    return (decodable: true, value: jsonDecode(text));
  } on FormatException {
    return (decodable: false, value: null);
  }
}

List<({int index, dynamic value})> _contentContainers(
  AcpConversationToolItem call,
) {
  final candidates = <({int index, dynamic value})>[];
  for (final (index, block) in (call.fields.content ?? []).indexed) {
    if (block case AcpToolContentView(
      content: AcpTextContentView(:final text),
    )) {
      final decoded = _wholeJson(text);
      if (decoded.value case final Map<String, dynamic> value) {
        candidates.add((index: index, value: value));
      } else if (decoded.value case final List<dynamic> value) {
        candidates.add((index: index, value: value));
      }
    }
  }
  return candidates;
}

Map<String, Object?> _outputOrigin(
  AcpConversationToolItem call,
  List<int> candidates,
) => {
  'source': _hasRawOutput(call)
      ? 'rawOutput'
      : candidates.length == 1
      ? 'content.text.jsonContainer'
      : 'unavailable',
  if (!_hasRawOutput(call)) ...{
    'jsonContainerCandidateCount': candidates.length,
    if (candidates.length == 1) 'contentIndex': candidates.single,
  },
};

Map<String, Object?> _contentDiagnostics(
  AcpConversationToolItem call,
  Set<String> safeCommands,
  Set<String> markers,
) {
  final blocks = <Map<String, Object?>>[];
  final candidates = <int>[];
  for (final (index, block) in (call.fields.content ?? []).indexed) {
    final data = <String, Object?>{
      'index': index,
      'type': block.runtimeType.toString(),
    };
    if (block case AcpToolContentView(:final content)) {
      data['contentType'] = content.runtimeType.toString();
      if (content case AcpTextContentView(:final text)) {
        final decoded = _wholeJson(text);
        final isContainer =
            decoded.value is Map<String, dynamic> || decoded.value is List;
        if (isContainer) candidates.add(index);
        data.addAll({
          'utf16Length': text.length,
          'utf8Bytes': utf8.encode(text).length,
          'sha256': sha256.convert(utf8.encode(text)).toString(),
          'jsonDecodable': decoded.decodable,
          'jsonType': decoded.decodable ? _jsonType(decoded.value) : null,
          'jsonContainerCandidate': isContainer,
          if (isContainer &&
              AgyHostTrace.canonicalName(call.fields.name) != null)
            'jsonProjection': _diagnosticJson(
              decoded.value,
              safeCommands,
              markers,
            ),
        });
      }
    }
    // Diff, Terminal and nontext content retain only their explicit types.
    blocks.add(data);
  }
  return {
    'contentState': call.fields.content == null ? 'missing' : 'present',
    'contentBlocks': blocks,
    'outputEvidence': _outputOrigin(call, candidates),
  };
}

String _jsonType(dynamic value) => switch (value) {
  null => 'null',
  Map() => 'object',
  List() => 'array',
  String() => 'string',
  bool() => 'boolean',
  num() => 'number',
  _ => throw StateError('Unsupported decoded JSON type'),
};

// Share the same whitelist between ACP diagnostics and Host domain evidence.
dynamic agyEvidenceDiagnostic(
  dynamic value, {
  required Set<String> safeCommands,
  required Set<String> markers,
}) => _diagnosticJson(value, safeCommands, markers);

// Keep formal task/report identities and state, not arbitrary tool text. This
// whitelist deliberately excludes MCP launch env, headers, authorization,
// capabilities, URLs, raw summaries and provider login messages.
const _diagnosticKeys = {
  'taskId',
  'taskIds',
  'targetTaskId',
  'toolId',
  'status',
  'cancelRequested',
  'command',
  'cwd',
  'interactive',
  'timeoutSeconds',
  'maxOutputChars',
  'chars',
  'closeStdin',
  'inputReceipt',
  'acceptedBytes',
  'closeState',
  'outcome',
  'processStarted',
  'exitCode',
  'signal',
  'state',
  'kind',
  'data',
  'stdout',
  'stderr',
  'originalBytes',
  'displayedBytes',
  'wasTruncated',
  'captureStatus',
  'archiveStatus',
  'diagnostic',
  'code',
  'task',
  'tasks',
  'result',
  'resultCursor',
  'nextCursor',
  'totalBytes',
  'format',
  'version',
  'content',
  'value',
  'output',
  'is_error',
  'isError',
  'structuredContent',
  'cancellation',
  'timedOut',
  'messagesReady',
  'target',
  'after',
  'timeoutMs',
  'cursor',
  'reports',
  'current',
  'gap',
  'generation',
  'run',
  'instance',
  'sequence',
  'completionSequence',
  'lastCompleted',
  'activeRun',
  'summary',
  'truncated',
  'ok',
  'Ok',
  'stopReason',
  'id',
  'agentId',
  'parentId',
  'profileId',
  'receipt',
  'messageAccepted',
  'messageSequence',
  'executionClosed',
  'backend',
  'hostMcp',
  'injected',
  'observedToolCalls',
  'force',
};

dynamic _diagnosticJson(
  dynamic value,
  Set<String> safeCommands,
  Set<String> markers, [
  String? key,
]) {
  if (value == null || value is num || value is bool) return value;
  if (value is String) {
    if (key == 'cwd') {
      return value == '.' ? value : {'redacted': true, 'length': value.length};
    }
    if (key == 'command') {
      return safeCommands.contains(value)
          ? value
          : {'redacted': true, 'length': value.length};
    }
    if (key == 'chars') {
      return markers.any((marker) => value == '$marker-stdin\n')
          ? value
          : {'redacted': true, 'length': value.length};
    }
    if (key == 'summary' ||
        key == 'content' ||
        key == 'stdout' ||
        key == 'stderr' ||
        key == 'data') {
      return {
        'redacted': true,
        'length': value.length,
        'expectedMarkerPresent': markers.any(value.contains),
      };
    }
    if (key == null) {
      if (value.length > 128 * 1024) {
        return {'redacted': true, 'length': value.length};
      }
      try {
        return _diagnosticJson(jsonDecode(value), safeCommands, markers);
      } on FormatException {
        return {'redacted': true, 'length': value.length};
      }
    }
    if (value.contains('://') ||
        value.contains('Bearer ') ||
        value.length > 4096) {
      return {'redacted': true, 'length': value.length};
    }
    if (key == 'value' ||
        key == 'output' ||
        key == 'result' ||
        key == 'structuredContent') {
      return {'redacted': true, 'length': value.length};
    }
    // Other admitted fields are typed IDs, cursors or enums.
    return value;
  }
  if (value is List) {
    return value
        .map((item) => _diagnosticJson(item, safeCommands, markers, key))
        .toList();
  }
  if (value is Map) {
    final result = <String, Object?>{};
    for (final name in ['error', 'archiveError', 'messageError']) {
      if (value.containsKey(name)) {
        result['${name}Present'] = value[name] != null;
      }
    }
    for (final entry in value.entries) {
      final name = entry.key.toString();
      if (!_diagnosticKeys.contains(name)) continue;
      if (name == 'content' && entry.value is List) {
        // MCP TextContent is formal protocol data, not assistant prose. Only
        // decode JSON and retain the same whitelist, never arbitrary text.
        result['mcpContent'] = [
          for (final block in entry.value as List)
            if (block is Map &&
                block['type'] == 'text' &&
                block['text'] is String)
              _diagnosticJson(block['text'], safeCommands, markers),
        ];
      } else if (name == 'content' &&
          value['format'] == 'pl.host.tool-result' &&
          entry.value is String) {
        try {
          result['decodedContent'] = _diagnosticJson(
            jsonDecode(entry.value as String),
            safeCommands,
            markers,
          );
        } on FormatException {
          result['content'] = {
            'redacted': true,
            'length': (entry.value as String).length,
          };
        }
      } else {
        result[name] = _diagnosticJson(
          entry.value,
          safeCommands,
          markers,
          name,
        );
      }
    }
    return result;
  }
  return {'unsupportedType': value.runtimeType.toString()};
}

Map<String, dynamic> _object(dynamic value, String label) {
  if (value is! Map<String, dynamic>) {
    throw StateError('Missing formal $label; unsupported raw payload shape');
  }
  return value;
}

dynamic _value(AcpJsonValue? value) => switch (value) {
  null || AcpJsonNull() => null,
  AcpJsonBool(:final value) => value,
  AcpJsonInteger(:final value) => _integer(value),
  AcpJsonDecimal(:final value) => value,
  AcpJsonString(:final value) => value,
  AcpJsonArray(:final values) => values.map(_value).toList(),
  AcpJsonObject(:final values) => values.map(
    (key, value) => MapEntry(key, _value(value)),
  ),
};

int _integer(BigInt value) {
  final exact = value.toInt();
  if (BigInt.from(exact) != value) {
    throw StateError('ACP raw integer exceeds exact platform representation');
  }
  return exact;
}
