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
      calls.where((call) => call.fields.name == name).toList();

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

    final shutdown = _commandTask(processCommand('shutdown'));
    return {
      'stdinTaskId': stdin,
      'stdinAcceptedBytes': delivery['acceptedBytes'],
      'stdinCloseState': delivery['closeState'],
      'stdinExitCode': exited['exitCode'],
      'cancelTaskId': cancelled,
      'cancelTerminalStatus': 'cancelled',
      'shutdownTaskId': shutdown,
    };
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
    expect(original['summary'], source['summary']);
    // acp_read serializes the original Rust Result; the current row uses its
    // public lowercase ok/error view. Compare the actual payload, not prose.
    expect(_object(original['result'], 'original ACP result')['Ok'], success);
    expect(original['truncated'], isFalse);
    expect(original['summary'], contains('$marker-child'));
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
