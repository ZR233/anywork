import 'dart:async';
import 'dart:convert';

import 'package:anywork_client/acp_sessions.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../anywork_client/test/support/acp_business_port.dart';
import '../integration_test/support/agy_submission_evidence.dart';
import '../integration_test/support/agy_host_trace.dart';

const remote = AcpRemoteSessionId('fixture-remote');
final target = AcpSessionTargetView(
  sessionId: 'fixture-session',
  agentId: 'fixture-agent',
  threadId: 'fixture-thread',
  instance: BigInt.one,
);
final run = AcpRunIdView(instance: BigInt.one, sequence: BigInt.one);
AcpSessionFrameView event(AcpSessionEventView v) => AcpEventFrameView(v);
AcpSessionFrameView update(AcpSessionUpdateView v) => event(
  AcpUpdateEventView(AcpSessionNotificationView(sessionId: remote, update: v)),
);
AcpSessionFrameView user(String text) => update(
  AcpUserMessageChunkView(
    AcpContentChunkView(content: AcpTextContentView(text: text)),
  ),
);
void push(ControlledAcpObservation source, AcpSessionFrameView frame) {
  final pending = source.read;
  if (pending != null && !pending.isCompleted) {
    pending.complete(frame);
  } else {
    source.frames.add(frame);
  }
}

AcpJsonValue raw(dynamic value) => switch (value) {
  null => const AcpJsonNull(),
  bool v => AcpJsonBool(v),
  int v => AcpJsonInteger(BigInt.from(v)),
  String v => AcpJsonString(v),
  List v => AcpJsonArray(v.map(raw)),
  Map v => AcpJsonObject(v.map((k, v) => MapEntry(k.toString(), raw(v)))),
  _ => throw StateError('unsupported fixture value'),
};

class Fixture {
  Fixture(this.source, this.port, this.client, this.owner);
  final ControlledAcpObservation source;
  final ControlledAcpBusinessPort port;
  final AcpSessionClient client;
  final AcpConversationSession owner;
  static Future<Fixture> open({String? replay}) async {
    final source = ControlledAcpObservation([
      AcpAcceptedFrameView(target: target, hasObservation: true),
      if (replay != null) user(replay),
      event(AcpReadyEventView(AcpNewSessionResponseView(sessionId: remote))),
      const AcpSettledFrameView(AcpSuccessView<void>(null)),
    ]);
    final port = ControlledAcpBusinessPort()
      ..sources.add(source)
      ..run = run;
    final client = AcpSessionClient(port: port);
    addTearDown(client.dispose);
    final owner = await client.openConversation(
      OpenAcpSessionRequestView(
        accountId: 'fixture',
        expectedConnectionRevision: BigInt.one,
        workspaceId: 'fixture-workspace',
        threadId: target.threadId,
        intent: const AcpLoadIntentView(remote),
      ),
    );
    await owner.source.waitFor((s) => s.ready && !s.openPending);
    return Fixture(source, port, client, owner);
  }

  Future<void> complete() async {
    push(
      source,
      event(
        AcpCompletedEventView(
          AcpCompletedRunView(
            run: run,
            completionSequence: BigInt.one,
            result: const AcpSuccessView(
              AcpPromptResponseView(stopReason: AcpStopReasonView.endTurn),
            ),
            summary: 'fixture',
            truncated: false,
          ),
        ),
      ),
    );
    await owner.source.waitFor(
      (s) => s.lastCompleted != null && s.activeRun == null,
    );
  }

  Future<AgyHostTrace> calls(List<Map<String, dynamic>> specs) async {
    for (var i = 0; i < specs.length; i++) {
      final s = specs[i];
      push(
        source,
        update(
          AcpToolCallSessionUpdateView(
            AcpToolCallView(
              toolCallId: AcpToolCallId('fixture-call-$i'),
              title: s['title'] ?? 'Fixture',
              name: s['name'],
              kind: AcpToolKindView.execute,
              status: AcpToolCallStatusView.completed,
              rawInput: raw(s['input']),
              rawOutput: raw(s['output']),
            ),
          ),
        ),
      );
    }
    await owner.source.waitFor(
      (s) =>
          s.content.whereType<AcpConversationToolItem>().length == specs.length,
    );
    return AgyHostTrace(owner.state.content);
  }
}

const prompt = 'question\n保持空白 ';
const secret = 'SYNTHETIC-HOST-INSTRUCTIONS-DO-NOT-EXPORT';
void main() {
  _defineToolContentTests();
  test('real Client publishes immutable submission before prompt; prefixed chunked echo stays independent', () async {
    final f = await Fixture.open(replay: 'older stage');
    final capture = AgySubmissionEvidence(
      expectedPrompt: prompt,
      before: f.owner.state,
    );
    var beforePort = false;
    final watch = f.owner.source.watch((s) {
      capture.observe(s);
      if (s.sendPending && s.content.length == 2) {
        beforePort = f.port.calls.every((c) => c.$1 != 'prompt');
      }
    });
    addTearDown(watch.cancel);
    f.port.promptResult = Completer<AcpRunIdView>();
    final send = f.owner.send(const [AcpTextContentView(text: prompt)]);
    capture.verify();
    expect(beforePort, isTrue);
    final submittedBefore = (capture.diagnostics())['submitted'];
    expect((submittedBefore as Map)['text'], {
      'utf16Length': 14,
      'utf8Bytes': 22,
      'sha256':
          '90fd0b5b9cd930f0d7fd236ed15c0e5ec03d624edcbaa8c14c32b143e16ab28b',
    });
    final request =
        f.port.calls.singleWhere((c) => c.$1 == 'prompt').$2
            as AcpPromptRequestView;
    expect((request.content.single as AcpTextContentView).text, prompt);
    push(f.source, user('$secret\n'));
    push(f.source, user('question\n'));
    push(f.source, user('保持空白 '));
    await f.owner.source.waitFor(
      (s) =>
          s.content
              .whereType<AcpConversationMessageItem>()
              .last
              .chunks
              .length ==
          3,
    );
    capture.verify();
    final after = capture.diagnostics();
    expect(after['submitted'], submittedBefore);
    final formal = (after['formalUserMessages'] as List).single as Map;
    expect(formal['equalsExpectedText'], isFalse);
    expect(formal['firstDifferenceUtf16'], 0);
    expect(formal['chunks'], hasLength(3));
    expect(jsonEncode(after).contains(secret), isFalse);
    expect(jsonEncode(after).contains(prompt), isFalse);
    f.port.promptResult!.complete(run);
    await send;
  });
  test(
    'wrong exact prompt fails through retained watch error; no trim',
    () async {
      final f = await Fixture.open();
      final capture = AgySubmissionEvidence(
        expectedPrompt: prompt,
        before: f.owner.state,
      );
      Object? failure;
      final watch = f.owner.source.watch((s) {
        try {
          capture.observe(s);
        } catch (e) {
          failure ??= e;
        }
      });
      addTearDown(watch.cancel);
      await f.owner.send([AcpTextContentView(text: prompt.trim())]);
      expect(failure, isA<StateError>());
      expect(capture.verify, throwsStateError);
    },
  );
  test(
    'missing provisional cannot be repaired by matching later formal chunks',
    () async {
      final f = await Fixture.open(replay: prompt);
      final capture = AgySubmissionEvidence(
        expectedPrompt: prompt,
        before: f.owner.state,
      );
      Object? failure;
      final watch = f.owner.source.watch((s) {
        try {
          capture.observe(s);
        } catch (e) {
          failure ??= e;
        }
      });
      addTearDown(watch.cancel);
      f.port.promptResult = Completer<AcpRunIdView>();
      final send = f.owner.send(const []);
      expect(failure, isA<StateError>());
      push(f.source, user(prompt));
      await f.owner.source.waitFor((s) => s.content.length == 2);
      expect(capture.verify, throwsStateError);
      f.port.promptResult!.complete(run);
      await send;
    },
  );
  test(
    'old-stage item and formal echo without send never prove submission',
    () async {
      final f = await Fixture.open(replay: prompt);
      final capture = AgySubmissionEvidence(
        expectedPrompt: prompt,
        before: f.owner.state,
      );
      final watch = f.owner.source.watch(capture.observe);
      addTearDown(watch.cancel);
      capture.observe(f.owner.state);
      expect(capture.verify, throwsStateError);
      push(f.source, user(prompt));
      await Future<void>.delayed(Duration.zero);
      expect(capture.verify, throwsStateError);
      expect((capture.diagnostics())['submissionCount'], 0);
    },
  );
  test('multiple actual submissions in one phase fail and cannot overwrite first evidence', () async {
    final f = await Fixture.open();
    final capture = AgySubmissionEvidence(
      expectedPrompt: prompt,
      before: f.owner.state,
    );
    Object? failure;
    final watch = f.owner.source.watch((s) {
      try {
        capture.observe(s);
      } catch (e) {
        failure ??= e;
      }
    });
    addTearDown(watch.cancel);
    await f.owner.send(const [AcpTextContentView(text: prompt)]);
    final first = (capture.diagnostics())['submitted'];
    await f.complete();
    await f.owner.send(const [AcpTextContentView(text: prompt)]);
    expect(failure, isA<StateError>());
    expect(capture.verify, throwsStateError);
    final after = capture.diagnostics();
    expect(after['submitted'], first);
    expect(after['submissionCount'], 2);
    expect(after['formalUserMessages'], isEmpty);
  });
  test('only exact raw namespace mapping; title and arbitrary service prefixes cannot impersonate', () async {
    final f = await Fixture.open();
    final names = <String?>[
      'anywork_exec_command',
      'mcp_anywork_anywork_exec_command',
      'mcp_other_anywork_exec_command',
      'prefix_anywork_exec_command',
      'mcp_anywork_mcp_anywork_anywork_exec_command',
      null,
    ];
    final trace = await f.calls([
      for (final name in names)
        {
          'name': name,
          'title': 'anywork_exec_command',
          'input': {},
          'output': {},
        },
    ]);
    expect(trace.named('anywork_exec_command'), hasLength(2));
    final verified = trace.verifyCompletedHostCalls();
    expect(verified, hasLength(2));
    expect(
      verified.map((v) => v['canonicalName']),
      everyElement('anywork_exec_command'),
    );
    expect(verified.map((v) => v['name']), names.take(2));
    expect(
      AgyHostTrace.canonicalName('mcp_anywork_anywork_mcp_anywork_x'),
      'anywork_mcp_anywork_x',
    );
    final diagnostics = trace.diagnostics(safeCommands: {}, markers: {});
    expect(
      diagnostics.take(2).every((r) => r.containsKey('rawOutput')),
      isTrue,
    );
    expect(
      diagnostics
          .skip(2)
          .every(
            (r) => !r.containsKey('rawOutput') && r['canonicalName'] == null,
          ),
      isTrue,
    );
  });
  test('diagnostics preserve task/report identity and redact arbitrary stdout, secrets and MCP env', () async {
    final f = await Fixture.open();
    final payload = {
      'taskId': 'task:fixture',
      'targetTaskId': 'task:target',
      'reports': [
        {
          'generation': 'generation-fixture',
          'run': {'instance': 1, 'sequence': 2},
          'completionSequence': 3,
          'summary': secret,
          'result': {
            'Ok': {'stopReason': 'endTurn'},
          },
          'truncated': false,
        },
      ],
      'cursor': 'cursor-fixture',
      'stdout': secret,
      'stderr': {'content': secret},
      'data': secret,
      'env': {'TOKEN': secret},
      'authorization': secret,
      'capability': secret,
      'url': 'https://secret.invalid/token',
    };
    final trace = await f.calls([
      {
        'name': 'mcp_anywork_anywork_wait_agent',
        'input': {'target': 'child-fixture', 'after': 'cursor-before'},
        'output': {'structuredContent': payload, 'isError': false},
      },
    ]);
    final d = trace.diagnostics(safeCommands: {}, markers: {}).single;
    final output = (d['rawOutput'] as Map)['structuredContent'] as Map;
    expect(output['taskId'], 'task:fixture');
    expect(output['targetTaskId'], 'task:target');
    expect(output['cursor'], 'cursor-fixture');
    final report = (output['reports'] as List).single as Map;
    expect(report['generation'], 'generation-fixture');
    expect(report['run'], {'instance': 1, 'sequence': 2});
    expect(report['completionSequence'], 3);
    expect(jsonEncode(d).contains(secret), isFalse);
    expect(jsonEncode(d).contains('secret.invalid'), isFalse);
    expect(output.containsKey('env'), isFalse);
    expect(output.containsKey('authorization'), isFalse);
  });
  test('unknown provider wrapper stays opaque instead of recursively supplying a receipt', () async {
    final f = await Fixture.open();
    final trace = await f.calls([
      {
        'name': 'mcp_anywork_anywork_exec_command',
        'input': {'command': 'fixture-stdin'},
        'output': {
          'mystery': {
            'structuredContent': {'taskId': 'task:fixture'},
          },
        },
      },
    ]);
    expect(trace.output(trace.calls.single), {
      'mystery': {
        'structuredContent': {'taskId': 'task:fixture'},
      },
    });
  });
}

const marker = 'PROBE_A';
AcpToolContentView text(String s) =>
    AcpToolContentView(content: AcpTextContentView(text: s));
Map<String, dynamic> call(
  dynamic output, {
  String name = 'anywork_exec_command',
  List<AcpToolCallContentView>? blocks,
  AcpJsonValue? raw,
  bool partial = false,
}) => {
  'name': name,
  'input': {'command': 'probe-stdin'},
  'blocks':
      blocks ??
      [
        text(jsonEncode({'structuredContent': output, 'isError': false})),
      ],
  'raw': ?raw,
  'partial': partial,
};
Future<AgyHostTrace> trace(
  List<Map<String, dynamic>> specs, {
  bool assistant = false,
}) async {
  final fixture = await Fixture.open();
  if (assistant) {
    push(
      fixture.source,
      update(
        const AcpAgentMessageChunkView(
          AcpContentChunkView(
            content: AcpTextContentView(text: '{"taskId":"task:assistant"}'),
          ),
        ),
      ),
    );
  }
  for (var i = 0; i < specs.length; i++) {
    final s = specs[i];
    final id = AcpToolCallId('content-call-$i');
    final blocks = s['blocks'] as List<AcpToolCallContentView>?;
    final rawOutput = s['raw'] as AcpJsonValue?;
    if (s['partial'] == true) {
      push(
        fixture.source,
        update(
          AcpToolCallChangedView(
            AcpToolCallUpdateView(
              toolCallId: id,
              fields: AcpToolCallUpdateFieldsView(
                name: s['name'],
                title: s['title'] ?? 'Fixture',
                kind: AcpToolKindView.execute,
                status: AcpToolCallStatusView.completed,
                rawInput: raw(s['input'] ?? {}),
                rawOutput: rawOutput,
                content: blocks,
              ),
            ),
          ),
        ),
      );
    } else {
      push(
        fixture.source,
        update(
          AcpToolCallSessionUpdateView(
            AcpToolCallView(
              toolCallId: id,
              title: s['title'] ?? 'Fixture',
              name: s['name'],
              kind: AcpToolKindView.execute,
              status: AcpToolCallStatusView.completed,
              rawInput: raw(s['input'] ?? {}),
              rawOutput: rawOutput,
              content: blocks ?? const [],
            ),
          ),
        ),
      );
    }
  }
  await fixture.owner.source.waitFor(
    (s) =>
        s.content.whereType<AcpConversationToolItem>().length == specs.length,
  );
  return AgyHostTrace(fixture.owner.state.content);
}

List<Map<String, Object?>> diag(AgyHostTrace t) => t.diagnostics(
  safeCommands: {'probe-stdin', 'probe-cancel'},
  markers: {marker},
);
Map<String, dynamic> page(
  String id,
  String status,
  Map<String, dynamic> payload,
) => {
  'archiveError': null,
  'task': {'taskId': id, 'status': status},
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
Map<String, dynamic> lifecycleCall(
  String name,
  Map<String, dynamic> input,
  dynamic value,
) => {
  'name': 'mcp_anywork_$name',
  'input': input,
  'blocks': [text(jsonEncode(value))],
};
void _defineToolContentTests() {
  test('usable raw keeps map, JSON string, list and one structuredContent layer; content not preferred', () async {
    final cases = <AcpJsonValue>[
      raw({'taskId': 'task:raw'}),
      raw(
        jsonEncode({
          'structuredContent': {'taskId': 'task:raw'},
          'isError': false,
        }),
      ),
      raw({
        'structuredContent': [
          {'taskId': 'task:raw'},
        ],
        'isError': false,
      }),
    ];
    final t = await trace([
      for (final raw in cases)
        call(null, raw: raw, blocks: [text('{"taskId":"task:wrong"}')]),
    ]);
    expect(t.output(t.calls[0]), {'taskId': 'task:raw'});
    expect(t.output(t.calls[1]), {'taskId': 'task:raw'});
    expect(t.output(t.calls[2]), [
      {'taskId': 'task:raw'},
    ]);
    expect(
      diag(t).map((r) => (r['outputEvidence'] as Map)['source']),
      everyElement('rawOutput'),
    );
  });
  test('missing and explicit-null raw accept only same-call full JSON object and retain source', () async {
    final t = await trace([
      call(
        {'taskId': 'task:missing'},
        blocks: [text('  {"taskId":"task:missing"} \n')],
      ),
      call({'taskId': 'task:null'}, raw: const AcpJsonNull()),
    ]);
    expect(t.output(t.calls[0]), {'taskId': 'task:missing'});
    expect(t.output(t.calls[1]), {'taskId': 'task:null'});
    final d = diag(t);
    expect(d.map((r) => r['rawOutputState']), ['missing', 'explicitNull']);
    expect(
      d.map((r) => (r['outputEvidence'] as Map)['source']),
      everyElement('content.text.jsonContainer'),
    );
    expect(
      d.map((r) => (r['outputEvidence'] as Map)['contentIndex']),
      everyElement(0),
    );
    expect(
      t.verifyCompletedHostCalls().map(
        (r) => (r['outputEvidence'] as Map)['source'],
      ),
      everyElement('content.text.jsonContainer'),
    );
  });
  test('prose, fences, substrings, JSON strings and primitives are not container evidence', () async {
    final texts = [
      secret,
      '```json\n{"taskId":"task:fake"}\n```',
      'prefix {"taskId":"task:fake"}',
      jsonEncode('{"taskId":"task:fake"}'),
      'null',
      'true',
      '1',
    ];
    final t = await trace([
      for (final s in texts) call(null, blocks: [text(s)]),
    ]);
    for (final c in t.calls) {
      expect(() => t.output(c), throwsStateError);
    }
    final d = diag(t);
    expect(
      d.every((r) => (r['outputEvidence'] as Map)['source'] == 'unavailable'),
      isTrue,
    );
    expect(jsonEncode(d).contains(secret), isFalse);
  });
  test(
    'title, assistant and another toolCallId cannot supply a missing output',
    () async {
      final t = await trace([
        {
          'name': 'anywork_exec_command',
          'title': '{"taskId":"task:title"}',
          'input': {},
          'partial': true,
        },
        call({'taskId': 'task:other'}),
      ], assistant: true);
      expect(() => t.output(t.calls[0]), throwsStateError);
      expect(t.output(t.calls[1]), {'taskId': 'task:other'});
      final d = diag(t);
      expect(d.first['contentState'], 'missing');
      expect(d.last['contentState'], 'present');
    },
  );
  test(
    'two JSON object candidates, including identical objects, fail',
    () async {
      final t = await trace([
        call(null, blocks: [text('{"taskId":"task:x"}'), text('{}')]),
        call(null, blocks: [text('{}'), text('{}')]),
      ]);
      for (final c in t.calls) {
        expect(() => t.output(c), throwsStateError);
      }
      final d = diag(t);
      expect(
        d.map(
          (r) => (r['outputEvidence'] as Map)['jsonContainerCandidateCount'],
        ),
        everyElement(2),
      );
    },
  );
  test('non-null raw cannot fallback even if null after decode, malformed or unknown', () async {
    final t = await trace([
      call(
        null,
        raw: raw({
          'mystery': {'taskId': 'task:wrapped'},
        }),
      ),
      call(null, raw: const AcpJsonString('null')),
      call(null, raw: const AcpJsonString(secret)),
    ]);
    expect(t.output(t.calls[0]), {
      'mystery': {'taskId': 'task:wrapped'},
    });
    expect(t.output(t.calls[1]), isNull);
    Object? failure;
    try {
      t.output(t.calls[2]);
    } catch (e) {
      failure = e;
    }
    expect(failure, isA<StateError>());
    expect(failure.toString().contains(secret), isFalse);
    for (final c in t.calls.take(2)) {
      expect(
        () => AgyHostTrace([c]).verifyTasks(marker, (k) => 'probe-$k'),
        throwsA(anyOf(isA<TestFailure>(), isA<StateError>())),
      );
    }
    expect(
      diag(t).map((r) => (r['outputEvidence'] as Map)['source']),
      everyElement('rawOutput'),
    );
  });
  test('unknown content wrapper, missing fields and nested structuredContent fail business checks', () async {
    for (final output in [
      {
        'mystery': {'taskId': 'task:x'},
      },
      {},
      {
        'structuredContent': {'taskId': 'task:x'},
      },
    ]) {
      final t = await trace([call(output)]);
      expect(t.output(t.calls.single), output);
      expect(
        () => t.verifyTasks(marker, (k) => 'probe-$k'),
        throwsA(isA<TestFailure>()),
      );
    }
  });
  test('diff, terminal, URI and nontext contents retain only types; secrets never exported', () async {
    final metadata = AcpJsonObject({'TOKEN': const AcpJsonString(secret)});
    final blocks = <AcpToolCallContentView>[
      text('Login https://secret.invalid/$secret'),
      AcpToolDiffView(
        path: secret,
        newText: secret,
        oldText: secret,
        meta: metadata,
      ),
      AcpToolTerminalView(
        terminalId: const AcpTerminalId(secret),
        meta: metadata,
      ),
      const AcpToolContentView(
        content: AcpResourceLinkView(
          name: secret,
          uri: 'https://secret.invalid/token',
        ),
      ),
      text(
        jsonEncode({
          'taskId': 'task:identity',
          'targetTaskId': 'task:parent',
          'cursor': 'cursor',
          'reports': [
            {
              'generation': 'generation',
              'run': {'instance': 1, 'sequence': 2},
              'completionSequence': 3,
              'summary': secret,
            },
          ],
          'stdout': secret,
          'stderr': {'content': secret},
          'env': {'TOKEN': secret},
          'authorization': secret,
          'url': 'https://secret.invalid/token',
        }),
      ),
    ];
    final t = await trace([call(null, blocks: blocks)]);
    expect((t.output(t.calls.single) as Map)['taskId'], 'task:identity');
    final d = diag(t).single;
    final shape = d['contentBlocks'] as List;
    expect(shape, hasLength(5));
    expect((d['outputEvidence'] as Map)['contentIndex'], 4);
    expect(shape[1], {'index': 1, 'type': 'AcpToolDiffView'});
    expect(shape[2], {'index': 2, 'type': 'AcpToolTerminalView'});
    expect(shape[3], {
      'index': 3,
      'type': 'AcpToolContentView',
      'contentType': 'AcpResourceLinkView',
    });
    final json = shape[4]['jsonProjection'] as Map;
    expect(json['taskId'], 'task:identity');
    expect(json['targetTaskId'], 'task:parent');
    expect((json['reports'] as List).single['run'], {
      'instance': 1,
      'sequence': 2,
    });
    expect(jsonEncode(d).contains(secret), isFalse);
    expect(jsonEncode(d).contains('secret.invalid'), isFalse);
  });
  test('formal content carries exact get_tool_task HostResult and unchanged full task assertions', () async {
    const stdin = 'task:stdin';
    const cancel = 'task:cancel';
    final t = await trace([
      lifecycleCall(
        'anywork_exec_command',
        {'command': 'probe-stdin'},
        {'taskId': stdin},
      ),
      lifecycleCall('anywork_list_tool_tasks', {}, [
        {'taskId': stdin},
      ]),
      lifecycleCall(
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
      lifecycleCall('anywork_wait', {
        'taskIds': [stdin],
      }, {}),
      lifecycleCall('anywork_get_tool_task', {
        'taskId': stdin,
        'resultCursor': 0,
      }, page(stdin, 'succeeded', {'processStarted': true, 'exitCode': 0})),
      lifecycleCall(
        'anywork_exec_command',
        {'command': 'probe-cancel'},
        {'taskId': cancel},
      ),
      lifecycleCall('anywork_list_tool_tasks', {}, [
        {'taskId': cancel},
      ]),
      lifecycleCall(
        'anywork_cancel_tool_task',
        {'taskId': cancel},
        {'taskId': cancel, 'cancellation': 'requested'},
      ),
      lifecycleCall('anywork_wait', {
        'taskIds': [cancel],
      }, {}),
      lifecycleCall(
        'anywork_get_tool_task',
        {'taskId': cancel, 'resultCursor': 0},
        page(cancel, 'cancelled', {
          'output': {
            'processStarted': true,
            'diagnostic': {'code': 'exec.cancelled'},
          },
        }),
      ),
    ]);
    final result = t.verifyTasks(marker, (k) => 'probe-$k');
    expect(result['stdinTaskId'], stdin);
    expect(result['cancelTaskId'], cancel);
  });
  test('explicit MCP errors are not successful content results', () async {
    final t = await trace([
      call(
        null,
        blocks: [
          text(
            jsonEncode({
              'isError': true,
              'structuredContent': {'taskId': 'task:x'},
            }),
          ),
        ],
      ),
    ]);
    expect(() => t.output(t.calls.single), throwsA(isA<TestFailure>()));
  });
  test(
    'unknown service metadata remains visible but cannot impersonate Host name',
    () async {
      final t = await trace([
        call({
          'taskId': 'task:foreign',
        }, name: 'mcp_other_anywork_exec_command'),
      ]);
      final d = diag(t).single;
      expect(t.named('anywork_exec_command'), isEmpty);
      expect(d['canonicalName'], isNull);
      expect(d['contentBlocks'], hasLength(1));
      expect(
        (d['contentBlocks'] as List).single.containsKey('jsonProjection'),
        isFalse,
      );
    },
  );
}
