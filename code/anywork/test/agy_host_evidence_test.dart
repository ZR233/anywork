import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'support/acp_acceptance_fixture.dart' as f;
import '../integration_test/support/agy_host_evidence.dart';
import '../integration_test/support/agy_host_trace.dart';

const gui = 4242,
    root = 'fixture-agent',
    child = 'fixture-child',
    marker = 'PROBE_A';
const secret = 'SYNTHETIC-SECRET-DO-NOT-EXPORT';
Map<String, dynamic> rec(
  String id,
  String tool,
  Map<String, dynamic> args,
  dynamic value, {
  String caller = root,
  bool error = false,
  int pid = gui,
}) => {
  'kind': 'acp_host_call_result',
  'version': 1,
  'pid': pid,
  'callerAgentId': caller,
  'hostCallId': id,
  'toolId': tool,
  'arguments': args,
  'value': value,
  'isError': error,
};
String frame(Map<String, dynamic> r) =>
    '2026-11-13T21:00:00.123456Z TRACE ThreadId(7) pl_studio_runtime::acp_host_call_evidence: host_mcp_call_result record_json=${jsonEncode(r)}\n';
Future<Directory> home() async {
  final h = await Directory.systemTemp.createTemp('host-evidence-test-');
  addTearDown(() => h.delete(recursive: true));
  await Directory(p.join(h.path, 'studio', 'logs')).create(recursive: true);
  return h;
}

File log(Directory h) => File(p.join(h.path, 'studio', 'logs', 'studio.log'));
AgyHostEvidenceLog reader(Directory h, {int? bytes, int? events}) =>
    AgyHostEvidenceLog(
      home: h,
      guiPid: gui,
      rootCaller: root,
      maxBytes: bytes ?? 32 * 1024 * 1024,
      maxEvents: events ?? 4096,
    );
Future<AgyHostTrace> acp(List<Map<String, dynamic>> rows) async {
  final fixture = await f.Fixture.open();
  return fixture.calls([
    for (final r in rows)
      {
        'name': 'mcp_anywork_${r['toolId']}',
        'input': r['arguments'],
        'output': null,
      },
  ]);
}

Map<String, dynamic> page(
  String id,
  String status,
  Map<String, dynamic> payload,
) => {
  'task': {'taskId': id, 'status': status},
  'archiveError': null,
  'result': {
    'format': 'pl.host.tool-result',
    'version': 1,
    'nextCursor': null,
    'content': jsonEncode({
      'is_error': status != 'succeeded',
      'value': payload,
    }),
  },
};
void main() {
  test('original root counter includes its own query and detects lost or foreign returns', () {
    AgyHostCalls counter(int count, {String actor = root}) => AgyHostCalls([
      AgyHostRecord.parse(
        rec('counter-call', 'anywork_list_agents', {}, [
          {
            'id': root,
            'hostMcp': {'injected': true, 'observedToolCalls': count},
          },
        ], caller: actor),
        gui,
        'studio.log',
        1,
      ),
    ]);
    expect(counter(7).verifyCallerCounter(root, 7)['observedToolCalls'], 7);
    expect(() => counter(6).verifyCallerCounter(root, 7), throwsStateError);
    expect(
      () => counter(7, actor: child).verifyCallerCounter(root, 7),
      throwsStateError,
    );
  });
  test('exact logger header and schema only; trusted top caller cannot be forged by args', () {
    final data = rec('h1', 'anywork_list_tool_tasks', {
      'callerAgentId': child,
      'requestId': 1,
    }, []);
    final parsed = AgyHostEvidenceLog.parseLine(
      frame(data).trimRight(),
      gui,
      'studio.log',
      1,
    )!;
    expect(parsed.caller, root);
    expect(parsed.arguments['callerAgentId'], child);
    expect(
      AgyHostEvidenceLog.parseLine(
        'TRACE other: host_mcp_call_result record_json=${jsonEncode(data)}',
        gui,
        'studio.log',
        1,
      ),
      isNull,
    );
    expect(
      () => AgyHostEvidenceLog.parseLine(
        frame(data).trimRight(),
        gui + 1,
        'studio.log',
        1,
      ),
      throwsStateError,
    );
    expect(
      () => AgyHostEvidenceLog.parseLine(
        frame({...data, 'version': 2}).trimRight(),
        gui,
        'studio.log',
        1,
      ),
      throwsStateError,
    );
    expect(
      () => AgyHostEvidenceLog.parseLine(
        frame({...data, 'kind': 'wrong'}).trimRight(),
        gui,
        'studio.log',
        1,
      ),
      throwsStateError,
    );
    expect(
      () => AgyHostEvidenceLog.parseLine(
        frame({...data, 'extra': 'not-schema'}).trimRight(),
        gui,
        'studio.log',
        1,
      ),
      throwsStateError,
    );
    expect(
      () => AgyHostEvidenceLog.parseLine(
        'DEBUG other: pl_studio_runtime::acp_host_call_evidence: host_mcp_call_result record_json=${jsonEncode(data)}',
        gui,
        'studio.log',
        1,
      ),
      throwsStateError,
    );
  });
  test(
    'interleaved callers and duplicate argument multiset have no id pairing',
    () async {
      final h = await home();
      final a = rec('z-host', 'anywork_list_tool_tasks', {}, []),
          b = rec('a-host', 'anywork_list_tool_tasks', {}, []);
      final c = rec('c1', 'anywork_list_tool_tasks', {}, [], caller: child),
          d = rec('c2', 'anywork_list_tool_tasks', {}, [], caller: child);
      await log(h).writeAsString([c, a, d, b].map(frame).join());
      final r = reader(h);
      final calls = await r.matchPhase(
        await acp([a, b]),
        root,
        timeout: Duration.zero,
      );
      expect(calls.records.map((v) => v.hostCallId), ['z-host', 'a-host']);
      expect(
        calls.collectionEvidence!['pairing'],
        'multiset equality only; no ID-to-ID mapping',
      );
      expect(
        () => r.claimChild(child, 2, timeout: Duration.zero),
        throwsStateError,
      );
      r.bindCaller(child);
      expect(
        (await r.claimChild(child, 2)).records.every((v) => v.caller == child),
        isTrue,
      );
      final drain = await r.verifyDrained();
      expect(drain['claimedRecords'], 4);
    },
  );
  test('fake caller in args does not route a root record to child', () async {
    final h = await home();
    final data = rec('h1', 'anywork_list_tool_tasks', {
      'callerAgentId': child,
    }, []);
    await log(h).writeAsString(frame(data));
    final r = reader(h);
    r.bindCaller(child);
    final t = await acp([data]);
    await expectLater(
      r.matchPhase(t, child, timeout: Duration.zero),
      throwsStateError,
    );
    await r.matchPhase(t, root);
    expect((await r.verifyDrained())['claimedRecords'], 1);
  });
  test(
    'missing, extra and mismatched arguments fail rather than guessed pairing',
    () async {
      final a = rec('h1', 'anywork_list_tool_tasks', {'x': 1}, []),
          b = rec('h2', 'anywork_list_tool_tasks', {'x': 1}, []);
      final h = await home();
      await log(h).writeAsString(frame(a));
      await expectLater(
        reader(h).matchPhase(await acp([a, b]), root, timeout: Duration.zero),
        throwsStateError,
      );
      await log(h).writeAsString(frame(a) + frame(b));
      await expectLater(
        reader(h).matchPhase(await acp([a]), root, timeout: Duration.zero),
        throwsStateError,
      );
      await log(h).writeAsString(frame(a));
      await expectLater(
        reader(h).matchPhase(
          await acp([
            {
              ...a,
              'arguments': {'x': 2},
            },
          ]),
          root,
          timeout: Duration.zero,
        ),
        throwsStateError,
      );
    },
  );
  test('duplicate Host id across callers and bad complete JSON fail', () async {
    final h = await home();
    final a = rec('same', 'anywork_list_tool_tasks', {}, []);
    await log(h)
        .writeAsString(frame(a) + frame({...a, 'callerAgentId': child}));
    await expectLater(reader(h).read(), throwsStateError);
    await log(h).writeAsString(
      'TRACE pl_studio_runtime::acp_host_call_evidence: host_mcp_call_result record_json={broken}\n',
    );
    await expectLater(reader(h).read(), throwsStateError);
  });
  test('incomplete tail waits, never parses until newline, and drain waits for complete tail', () async {
    final h = await home();
    final a = rec('h1', 'anywork_list_tool_tasks', {}, []);
    await log(h).writeAsString(frame(a).trimRight());
    final r = reader(h);
    await r.read();
    expect(r.pendingTail, isTrue);
    expect(r.diagnostics({}, {}), isEmpty);
    await expectLater(
      r.matchPhase(await acp([a]), root, timeout: Duration.zero),
      throwsStateError,
    );
    await log(h).writeAsString('\n', mode: FileMode.append);
    await r.matchPhase(await acp([a]), root);
    await log(h).writeAsString('unfinished', mode: FileMode.append);
    await expectLater(
      r.verifyDrained(timeout: Duration.zero),
      throwsStateError,
    );
    await log(h).writeAsString('\n', mode: FileMode.append);
    expect((await r.verifyDrained())['pendingTail'], isFalse);
  });
  test(
    'numbered rotation retains original records; loss and gaps fail',
    () async {
      final h = await home();
      final a = rec('h1', 'anywork_list_tool_tasks', {}, []),
          b = rec('h2', 'anywork_list_tool_tasks', {}, []);
      await log(h).writeAsString(frame(a));
      final r = reader(h);
      await r.read();
      await log(h).rename('${log(h).path}.1');
      await log(h).writeAsString(frame(b));
      expect(
        (await r.matchPhase(await acp([a, b]), root)).records,
        hasLength(2),
      );
      await File(p.join(log(h).parent.path, 'studio.log.1')).delete();
      await expectLater(r.verifyDrained(), throwsStateError);
      await File(p.join(log(h).parent.path, 'studio.log.2'))
          .writeAsString(frame(a));
      await expectLater(reader(h).read(), throwsStateError);

      await File(p.join(log(h).parent.path, 'studio.log.2')).delete();
      await File('${log(h).path}.8').writeAsString(frame(a));
      await expectLater(reader(h).read(), throwsStateError);
    },
  );
  test(
    'temporary rotation gap is retried without treating it as zero evidence',
    () async {
      final h = await home();
      final a = rec('h1', 'anywork_list_tool_tasks', {}, []);
      await log(h).writeAsString(frame(a));
      final r = reader(h);
      await r.read();
      await log(h).rename('${log(h).path}.1');
      final completingRotation = Future<void>.delayed(
        const Duration(milliseconds: 5),
        () async {
          await log(h).writeAsString('');
        },
      );
      try {
        await r.read();
      } finally {
        await completingRotation;
      }
      expect(
        (await r.matchPhase(await acp([a]), root)).records.single.hostCallId,
        'h1',
      );
      await r.verifyDrained();
    },
  );
  test('missing logs, byte and event caps are hard failures', () async {
    final h = await home();
    expect(
      () => AgyHostEvidenceLog(home: h, guiPid: 0, rootCaller: root),
      throwsStateError,
    );
    expect(() => reader(h, bytes: 0), throwsStateError);
    await expectLater(reader(h).read(), throwsStateError);
    final a = rec('h1', 'anywork_list_tool_tasks', {}, []),
        b = rec('h2', 'anywork_list_tool_tasks', {}, []);
    await log(h).writeAsString(frame(a) + frame(b));
    await expectLater(reader(h, bytes: 8).read(), throwsStateError);
    await expectLater(reader(h, events: 1).read(), throwsStateError);
  });
  test('Host direct values pass unchanged STDIN, cancellation and original HostResult validator', () async {
    const stdin = 'task:stdin', cancel = 'task:cancel';
    var n = 0;
    Map<String, dynamic> row(
      String tool,
      Map<String, dynamic> args,
      dynamic value,
    ) => rec('task-host-${++n}', tool, args, value);
    final rows = [
      row(
        'anywork_exec_command',
        {'command': 'probe-stdin'},
        {'taskId': stdin},
      ),
      row('anywork_list_tool_tasks', {}, [
        {'taskId': stdin},
      ]),
      row(
        'anywork_write_stdin',
        {'taskId': stdin, 'chars': '$marker-stdin\n', 'closeStdin': true},
        {
          'targetTaskId': stdin,
          'inputReceipt': {
            'acceptedBytes': utf8.encode('$marker-stdin\n').length,
            'outcome': 'complete',
            'closeState': 'closed',
          },
        },
      ),
      row('anywork_wait', {
        'taskIds': [stdin],
      }, {}),
      row('anywork_get_tool_task', {
        'taskId': stdin,
        'resultCursor': 0,
      }, page(stdin, 'succeeded', {'processStarted': true, 'exitCode': 0})),
      row(
        'anywork_exec_command',
        {'command': 'probe-cancel'},
        {'taskId': cancel},
      ),
      row('anywork_list_tool_tasks', {}, [
        {'taskId': cancel},
      ]),
      row(
        'anywork_cancel_tool_task',
        {'taskId': cancel},
        {'taskId': cancel, 'cancellation': 'requested'},
      ),
      row('anywork_wait', {
        'taskIds': [cancel],
      }, {}),
      row(
        'anywork_get_tool_task',
        {'taskId': cancel, 'resultCursor': 0},
        page(cancel, 'cancelled', {
          'output': {
            'processStarted': true,
            'diagnostic': {'code': 'exec.cancelled'},
          },
        }),
      ),
    ];
    final h = await home();
    await log(h).writeAsString(rows.map(frame).join());
    final r = reader(h);
    final calls = await r.matchPhase(await acp(rows), root);
    calls.verifyGeneratedResults();
    final result = calls.verifyTasks(marker, (kind) => 'probe-$kind');
    expect(result['stdinTaskId'], stdin);
    expect(result['cancelTaskId'], cancel);
    await r.verifyDrained();
  });
  test('original child report uses real spawn result caller, not args, with interleaving', () async {
    final run = {'instance': 1, 'sequence': 1};
    final ok = {'stopReason': 'endTurn'};
    final report = {
      'generation': 'g1',
      'run': run,
      'completionSequence': 1,
      'result': {'Ok': ok},
      'summary': '$marker-child',
      'truncated': false,
    };
    final rows = [
      rec('r1', 'anywork_list_agent_profiles', {}, []),
      rec(
        'r2',
        'anywork_spawn_agent',
        {'profileId': 'profile', 'callerAgentId': 'forged'},
        {
          'messageError': null,
          'receipt': {
            'agentId': child,
            'profileId': 'profile',
            'messageAccepted': true,
            'messageSequence': 1,
          },
        },
      ),
      rec(
        'r3',
        'anywork_wait_agent',
        {'target': child},
        {
          'target': child,
          'gap': false,
          'timedOut': false,
          'reports': [report],
          'current': {
            'id': child,
            'parentId': root,
            'backend': 'acp',
            'activeRun': null,
            'hostMcp': {'injected': true, 'observedToolCalls': 2},
            'lastCompleted': {
              'run': run,
              'completionSequence': 1,
              'result': {'ok': ok},
              'summary': '$marker-child',
            },
          },
          'cursor': 'cursor-original',
        },
      ),
      rec(
        'r4',
        'anywork_close_agent',
        {'target': child},
        {'agentId': child, 'executionClosed': true},
      ),
    ];
    final children = [
      rec(
        'c1',
        'anywork_exec_command',
        {'command': 'cat input-token.txt'},
        {'taskId': 'task:child'},
        caller: child,
      ),
      rec(
        'c2',
        'anywork_write_file',
        {'path': 'child-result.txt', 'content': secret},
        {'bytesWritten': 33},
        caller: child,
      ),
    ];
    final h = await home();
    await log(h).writeAsString(
      [
        rows[0],
        children[0],
        rows[1],
        children[1],
        ...rows.skip(2),
      ].map(frame).join(),
    );
    final r = reader(h);
    final calls = await r.matchPhase(await acp(rows), root);
    final actual = calls.verifyChild('profile', marker, root);
    expect(actual['agentId'], child);
    r.bindCaller(actual['agentId'] as String);
    final owned = await r.claimChild(
      actual['agentId'] as String,
      actual['childObservedHostToolCalls'] as int,
    );
    owned.verifyGeneratedResults();
    await r.verifyDrained();
  });
  test(
    'C task remains running at exact 1ms observation under same validator',
    () async {
      final rows = [
        rec(
          's1',
          'anywork_exec_command',
          {'command': 'probe-shutdown'},
          {'taskId': 'task:shutdown'},
        ),
        rec('s2', 'anywork_list_tool_tasks', {}, [
          {'taskId': 'task:shutdown'},
        ]),
        rec(
          's3',
          'anywork_wait',
          {
            'taskIds': ['task:shutdown'],
            'timeoutMs': 1,
          },
          {
            'timedOut': true,
            'tasks': [
              {'taskId': 'task:shutdown', 'status': 'running'},
            ],
          },
        ),
      ];
      final h = await home();
      await log(h).writeAsString(rows.map(frame).join());
      final r = reader(h);
      final calls = await r.matchPhase(await acp(rows), root);
      expect(
        calls.verifyShutdown('probe-shutdown')['statusAtRootCompletion'],
        'running',
      );
      await r.verifyDrained();
    },
  );
  test('errors do not become success; diagnostics omit command/result/env/header secrets', () async {
    final data = rec(
      'private-host',
      'anywork_exec_command',
      {
        'command': secret,
        'env': {'TOKEN': secret},
        'callerAgentId': 'forged',
      },
      {
        'stdout': {'content': secret},
        'summary': secret,
        'env': {'TOKEN': secret},
        'headers': {'Authorization': secret},
      },
      error: true,
    );
    final h = await home();
    await log(h).writeAsString(frame(data));
    final r = reader(h);
    final calls = await r.matchPhase(await acp([data]), root);
    expect(calls.verifyGeneratedResults, throwsA(isA<TestFailure>()));
    final d = calls.diagnostics({}, {});
    expect(jsonEncode(d).contains(secret), isFalse);
    expect(d.single['callerAgentId'], root);
    expect(d.single['hostCallId'], 'private-host');
  });
  test('failed-call diagnostics retain only the fixed workspace cwd', () {
    for (final cwd in [
      '.',
      '/private/$secret',
      '../$secret',
      'private-$secret',
    ]) {
      final data = rec(
        'failed-cwd',
        'anywork_exec_command',
        {'command': 'synthetic command', 'cwd': cwd},
        {
          'diagnostic': {'cwd': cwd},
        },
        error: true,
      );
      final calls = AgyHostCalls([
        AgyHostRecord.parse(data, gui, 'studio.log', 1),
      ]);
      final diagnostic = calls.diagnostics({}, {}).single;
      final arguments = diagnostic['arguments'] as Map;
      final value = diagnostic['value'] as Map;
      final expected = cwd == '.'
          ? '.'
          : {'redacted': true, 'length': cwd.length};
      expect(arguments['cwd'], expected);
      expect((value['diagnostic'] as Map)['cwd'], expected);
      expect(jsonEncode(diagnostic).contains(secret), isFalse);
      expect(calls.records.single.arguments['cwd'], cwd);
      expect(calls.verifyGeneratedResults, throwsA(isA<TestFailure>()));
    }
  });
  test(
    'unclaimed late calls and changed content after claim fail final drain',
    () async {
      final h = await home();
      final a = rec('h1', 'anywork_list_tool_tasks', {}, []),
          b = rec('h2', 'anywork_list_tool_tasks', {}, [], caller: 'foreign');
      await log(h).writeAsString(frame(a));
      final r = reader(h);
      await r.matchPhase(await acp([a]), root);
      await log(h).writeAsString(frame(b), mode: FileMode.append);
      await expectLater(r.verifyDrained(), throwsStateError);

      final changedHome = await home();
      await log(changedHome).writeAsString(frame(a));
      final changedReader = reader(changedHome);
      await changedReader.matchPhase(await acp([a]), root);
      await log(changedHome).writeAsString(
        frame({
          ...a,
          'value': {'changed': true},
        }),
      );
      await expectLater(changedReader.verifyDrained(), throwsStateError);
    },
  );
}
