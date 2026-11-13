import 'dart:convert';

import 'package:anywork_client/acp_sessions.dart';
import 'package:flutter_test/flutter_test.dart';

// Decode only the formal ACP raw values and MCP structuredContent envelope.
// Unknown provider wrappers fail visibly; assistant prose is never evidence.
final class AgyHostTrace {
  AgyHostTrace(Iterable<AcpConversationContentItem> content)
    : calls = content.whereType<AcpConversationToolItem>().toList();

  final List<AcpConversationToolItem> calls;

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
        },
    ];
  }

  Map<String, dynamic> input(AcpConversationToolItem call) =>
      _object(_value(call.fields.rawInput), 'ACP tool rawInput');

  dynamic output(AcpConversationToolItem call) {
    var value = _value(call.fields.rawOutput);
    if (value is String) value = jsonDecode(value);
    if (value is Map<String, dynamic> &&
        value.containsKey('structuredContent')) {
      expect(value['isError'], isNot(true), reason: 'Host MCP tool failed');
      value = value['structuredContent'];
    }
    expect(call.fields.status, AcpToolCallStatusView.completed);
    return value;
  }

  Map<String, dynamic> _taskResult(String id, String status) {
    final reads = named('anywork_get_tool_task').where((call) {
      final arguments = input(call);
      return arguments['taskId'] == id && arguments['resultCursor'] == 0;
    });
    for (final read in reads) {
      final response = _object(output(read), 'get_tool_task response');
      expect(response['archiveError'], isNull);
      final task = _object(response['task'], 'task status');
      if (task['status'] != status) continue;
      expect(task['taskId'], id);
      final result = _object(response['result'], 'immutable task payload page');
      expect(result['format'], 'pl.host.tool-result');
      expect(result['version'], 1);
      expect(
        result['nextCursor'],
        isNull,
        reason: 'Synthetic receipt must fit one complete page',
      );
      // WorkspaceTools stores HostResult, not the command record alone.
      final envelope = _object(
        jsonDecode(result['content'] as String),
        'original HostResult',
      );
      expect(envelope['is_error'], status != 'succeeded');
      final value = _object(envelope['value'], 'original HostResult value');
      return status == 'succeeded'
          ? value
          : _object(value['output'], 'original failed command output');
    }
    throw StateError('No original terminal $status payload read for $id');
  }

  String _commandTask(String expectedCommand) {
    final exec = named('anywork_exec_command')
        .singleWhere((call) => input(call)['command'] == expectedCommand);
    final receipt = _object(output(exec), 'exec acceptance receipt');
    final id = receipt['taskId'];
    expect(id, isA<String>());
    expect(id, isNotEmpty);
    // The identity must have been observed in this same Thread, not derived
    // from an ACP call ID or copied from another model-generated document.
    expect(
      named('anywork_list_tool_tasks').any((call) {
        final rows = output(call);
        return rows is List &&
            rows.any((row) => row is Map && row['taskId'] == id);
      }),
      isTrue,
      reason: 'Original task must be present in list_tool_tasks',
    );
    expect(
      named('anywork_wait')
          .any((call) => (input(call)['taskIds'] as List).contains(id)),
      isTrue,
      reason: 'Observe exact receipt identity through wait',
    );
    return id as String;
  }

  Map<String, Object?> verifyTasks(
    String marker,
    String Function(String) processCommand,
  ) {
    final stdin = _commandTask(processCommand('stdin'));
    final writes = named('anywork_write_stdin')
        .where((call) => input(call)['taskId'] == stdin)
        .toList();
    expect(writes, hasLength(1), reason: 'Do not replay accepted stdin');
    final request = input(writes.single);
    expect(request['chars'], '$marker-stdin\n');
    expect(request['closeStdin'], isTrue);
    final write = _object(output(writes.single), 'stdin receipt');
    expect(write['targetTaskId'], stdin);
    final delivery = _object(write['inputReceipt'], 'inputReceipt');
    expect(delivery['acceptedBytes'], utf8.encode('$marker-stdin\n').length);
    expect(delivery['outcome'], 'complete');
    expect(delivery['closeState'], 'closed');
    final exited = _taskResult(stdin, 'succeeded');
    expect(exited['processStarted'], isTrue);
    expect(exited['exitCode'], 0);

    final cancelled = _commandTask(processCommand('cancel'));
    final cancel = named('anywork_cancel_tool_task')
        .singleWhere((call) => input(call)['taskId'] == cancelled);
    final acknowledgement = _object(output(cancel), 'cancel acknowledgement');
    expect(acknowledgement['taskId'], cancelled);
    expect(acknowledgement['cancellation'], 'requested');
    final terminal = _taskResult(cancelled, 'cancelled');
    expect(terminal['processStarted'], isTrue);
    expect(
      _object(terminal['diagnostic'], 'cancel diagnostic')['code'],
      'exec.cancelled',
    );

    return {
      'stdinTaskId': stdin,
      'stdinAcceptedBytes': delivery['acceptedBytes'],
      'stdinCloseState': delivery['closeState'],
      'stdinExitCode': exited['exitCode'],
      'cancelTaskId': cancelled,
      'cancelTerminalStatus': 'cancelled',
    };
  }

  Map<String, Object?> verifyShutdown(String expectedCommand) {
    final id = _commandTask(expectedCommand);
    final wait = named('anywork_wait')
        .singleWhere((call) => (input(call)['taskIds'] as List).contains(id));
    expect(input(wait)['timeoutMs'], 1);
    final observed = _object(output(wait), 'shutdown task observation');
    expect(observed['timedOut'], isTrue);
    expect(
      (observed['tasks'] as List).any(
        (row) =>
            row is Map && row['taskId'] == id && row['status'] == 'running',
      ),
      isTrue,
    );
    return {'shutdownTaskId': id, 'statusAtRootCompletion': 'running'};
  }

  Map<String, Object?> verifyChild(
    String profile,
    String marker,
    String parentAgentId,
  ) {
    expect(named('anywork_list_agent_profiles'), isNotEmpty);
    final spawn = named('anywork_spawn_agent').single;
    final args = input(spawn);
    expect(args['profileId'], profile);
    for (final forbidden in [
      'modelSelection',
      'writablePaths',
      'reviewTargetAgentId',
      'reviewFeedback',
    ]) {
      expect(args[forbidden], isNull);
    }
    final created = _object(output(spawn), 'spawn result');
    expect(created['messageError'], isNull);
    final receipt = _object(created['receipt'], 'spawn receipt');
    final id = receipt['agentId'] as String;
    expect(receipt['profileId'], profile);
    expect(receipt['messageAccepted'], isTrue);
    final waited = named('anywork_wait_agent')
        .where((call) => input(call)['target'] == id);
    Map<String, dynamic>? original;
    Map<String, dynamic>? current;
    String? cursor;
    for (final call in waited) {
      final value = _object(output(call), 'wait_agent result');
      expect(value['target'], id);
      expect(value['gap'], isFalse);
      final reports = value['reports'] as List;
      if (reports.isEmpty) continue;
      expect(value['timedOut'], isFalse);
      expect(reports, hasLength(1));
      original = _object(reports.single, 'original ACP terminal report');
      current = _object(value['current'], 'current ACP member');
      cursor = value['cursor'] as String;
      break;
    }
    expect(original, isNotNull, reason: 'Spawn acceptance is not completion');
    expect(current!['id'], id);
    expect(current['parentId'], parentAgentId);
    expect(current['backend'], 'acp');
    expect(current['activeRun'], isNull);
    final childMcp = _object(current['hostMcp'], 'child Host MCP facts');
    expect(childMcp['injected'], isTrue);
    expect(childMcp['observedToolCalls'], greaterThanOrEqualTo(2));
    final source = _object(current['lastCompleted'], 'ACP source completion');
    final success = _object(source['result'], 'ACP source result')['ok'];
    expect(success, isNotNull);
    expect(original!['generation'], isA<String>());
    expect(original['generation'], isNotEmpty);
    expect(original['run'], source['run']);
    expect(original['completionSequence'], source['completionSequence']);
    expect(
      original['summary'] == source['summary'],
      isTrue,
      reason: 'Original summary differs from current source; text redacted',
    );
    // acp_read serializes the original Rust Result; the current row uses its
    // public lowercase ok/error view. Compare the actual payload, not prose.
    expect(
      equals(
        success,
      ).matches(_object(original['result'], 'original ACP result')['Ok'], {}),
      isTrue,
      reason: 'Original result differs from current source',
    );
    expect(original['truncated'], isFalse);
    expect(
      (original['summary'] as String).contains('$marker-child'),
      isTrue,
      reason: 'Child completion marker missing; summary text redacted',
    );
    final run = _object(original['run'], 'original ACP run');
    expect(run['instance'], isPositive);
    expect(run['sequence'], isPositive);
    expect(original['completionSequence'], isPositive);
    expect(cursor, isNotEmpty);
    final close = named('anywork_close_agent')
        .singleWhere((call) => input(call)['target'] == id);
    final closed = _object(output(close), 'close_agent result');
    expect(closed['agentId'], id);
    expect(closed['executionClosed'], isTrue);
    return {
      'agentId': id,
      'profileId': profile,
      'messageSequence': receipt['messageSequence'],
      'generation': original['generation'],
      'run': original['run'],
      'completionSequence': original['completionSequence'],
      'cursor': cursor,
      'executionClosed': closed['executionClosed'],
      'childObservedHostToolCalls': childMcp['observedToolCalls'],
    };
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
        if (canonicalName(call.fields.name) != null) ...{
          'rawInput': _diagnosticJson(
            _value(call.fields.rawInput),
            safeCommands,
            markers,
          ),
          'rawOutput': _diagnosticJson(
            _value(call.fields.rawOutput),
            safeCommands,
            markers,
          ),
        },
      },
  ];
}

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
    // Other admitted fields are typed IDs, cursors, enums or relative cwd.
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
