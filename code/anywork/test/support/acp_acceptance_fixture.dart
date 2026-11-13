import 'package:anywork_client/acp_sessions.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../anywork_client/test/support/acp_business_port.dart';
import '../../integration_test/support/agy_host_trace.dart';

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
