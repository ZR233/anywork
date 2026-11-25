import 'dart:async';

import 'package:anywork/src/app/app_graph.dart';
import 'package:anywork/src/features/status/state/workflow_graph_query.dart';
import 'package:anywork/src/features/conversation/timeline/view_models/thread_runtime_fields.dart';
import 'package:anywork_client/acp_sessions.dart';
import 'package:anywork_client/models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:riverpod/riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart'
    show Override, ProviderListenable;

import '../../../anywork_client/test/support/acp_business_port.dart';
import '../support/recording_demo_transport.dart';
import '../support/test_app_lifecycle.dart';
import '../support/test_statistics_feed.dart';

void main() {
  const threadId = 'thread-main';
  final nativeRun = threadWorkflowRunProvider(threadId);
  final nativeGraph = threadWorkflowGraphProvider(threadId);

  for (final (change, nextRun) in [
    ('mode', _run(mode: 'mode.next')),
    ('revision', _run(revision: 2)),
    ('hash', _run(hash: 'hash-next')),
  ]) {
    test(
      'Native isolates pending graph responses when $change changes',
      () async {
        var run = _run();
        final fixture = _GraphFixture(
          overrides: [nativeRun.overrideWith((_) => ThreadWorkflowRun(run))],
        );
        fixture.container.listen(nativeGraph, (_, _) {});
        final old = await fixture.transport.requestAt(0);
        expect(fixture.container.read(nativeGraph).graph.isLoading, isTrue);

        run = nextRun;
        fixture.container.invalidate(nativeRun);
        final current = await fixture.transport.requestAt(1);
        expect(old.threadId, threadId);
        expect(current.threadId, threadId);
        final loading = fixture.container.read(nativeGraph);
        expect(loading.run, nextRun);
        expect(loading.graph.isLoading, isTrue);
        expect(loading.graph.hasValue, isFalse);

        final graph = _graph('current');
        final currentShown = _waitForGraph(
          fixture.container,
          nativeGraph,
          graph,
        );
        current.response.complete(graph);
        await currentShown;
        expect(old.response.isCompleted, isFalse);

        old.response.complete(_graph('old'));
        await Future<void>.value();
        await fixture.container.pump();
        expect(fixture.container.read(nativeGraph).graph.requireValue, graph);
        expect(fixture.container.read(nativeGraph).run, nextRun);
      },
    );
  }

  test(
    'Native surfaces an RPC failure and retries the current graph',
    () async {
      final run = _run();
      final fixture = _GraphFixture(
        overrides: [nativeRun.overrideWith((_) => ThreadWorkflowRun(run))],
      );
      final error = StateError('Could not read workflow graph');
      final failed = Completer<WorkflowGraphReadout>();
      fixture.container.listen(nativeGraph, (_, next) {
        if (next.graph.asError?.error == error && !failed.isCompleted) {
          failed.complete(next);
        }
      });
      final initial = await fixture.transport.requestAt(0);
      initial.response.completeError(error);
      final state = await failed.future;
      expect(state.run, run);
      expect(fixture.transport.requests, hasLength(1));

      state.retry!();
      final retried = await fixture.transport.requestAt(1);
      expect(retried.threadId, threadId);
      expect(fixture.container.read(nativeGraph).graph.isLoading, isTrue);
      final graph = _graph('recovered');
      final shown = _waitForGraph(fixture.container, nativeGraph, graph);
      retried.response.complete(graph);
      await shown;
      expect(fixture.container.read(nativeGraph).run, run);
    },
  );

  test(
    'Native retries a failed run field before looking up its graph',
    () async {
      final error = StateError('Could not read workflow run');
      final run = _run();
      var recover = false;
      final fixture = _GraphFixture(
        overrides: [
          nativeRun.overrideWith(
            (_) => recover ? ThreadWorkflowRun(run) : throw error,
          ),
        ],
      );
      final subscription = fixture.container.listen(nativeGraph, (_, _) {});
      final failed = subscription.read();
      expect(failed.graph.asError?.error, same(error));
      expect(failed.run, isNull);
      expect(fixture.transport.requests, isEmpty);

      recover = true;
      failed.retry!();
      final request = await fixture.transport.requestAt(0);
      expect(subscription.read().run, run);
      final graph = _graph('workflow-stage');
      final shown = _waitForGraph(fixture.container, nativeGraph, graph);
      request.response.complete(graph);
      await shown;
    },
  );

  test('ACP isolates a detached thread fallback and a fallback replaced by canonical data', () async {
    const oldThread = 'acp-old';
    const currentThread = 'acp-current';
    const missingGraph = AcpWorkflowStateView(modeId: 'mode.auto');
    final port = ControlledAcpBusinessPort();
    final fixture = _GraphFixture(acpPort: port);
    await fixture.openAcp(oldThread, missingGraph);
    final (owner, source) = await fixture.openAcp(currentThread, missingGraph);

    final oldSubscription = fixture.container.listen(
      acpWorkflowGraphProvider(oldThread),
      (_, _) {},
    );
    final old = await fixture.transport.requestAt(0);
    expect(old.threadId, oldThread);

    oldSubscription.close();
    final currentProvider = acpWorkflowGraphProvider(currentThread);
    final subscription = fixture.container.listen(currentProvider, (_, _) {});
    final fallback = await fixture.transport.requestAt(1);
    expect(fallback.threadId, currentThread);
    expect(subscription.read().graph.isLoading, isTrue);

    final canonical = _graph('canonical');
    final workflow = AcpWorkflowStateView(
      modeId: 'mode.auto',
      graph: canonical,
    );
    final shown = _waitForGraph(fixture.container, currentProvider, canonical);
    await source.waitingForFrame.future;
    source.read!.complete(
      AcpEventFrameView(AcpWorkflowStateUpdatedEventView(workflow)),
    );
    await owner.source.waitFor((state) => state.workflowState == workflow);
    await shown;
    expect(subscription.read().retry, isNull);

    old.response.complete(_graph('old'));
    fallback.response.completeError(StateError('Retired ACP fallback'));
    await Future<void>.value();
    await fixture.container.pump();
    expect(subscription.read().graph.requireValue, canonical);
    expect(fixture.transport.requests, hasLength(2));
  });
}

Future<void> _waitForGraph(
  ProviderContainer container,
  ProviderListenable<WorkflowGraphReadout> provider,
  WorkflowRuntimeGraphSnapshotView graph,
) async {
  final arrived = Completer<void>();
  final subscription = container.listen(provider, (_, next) {
    if (next.graph.asData?.value == graph && !arrived.isCompleted) {
      arrived.complete();
    }
  }, fireImmediately: true);
  try {
    await arrived.future;
  } finally {
    subscription.close();
  }
}

WorkflowRunView _run({
  String mode = 'mode.auto',
  int revision = 1,
  String hash = 'hash',
}) => WorkflowRunView(
  lineageId: 'graph-lineage',
  runId: 'graph-run',
  modeId: mode,
  graphRevision: revision,
  graphHash: hash,
  currentStateId: 'workflow-stage',
  terminal: false,
  startedAt: DateTime.utc(2025),
  updatedAt: DateTime.utc(2025),
);

WorkflowRuntimeGraphSnapshotView _graph(String id) =>
    WorkflowRuntimeGraphSnapshotView(
      modeId: 'mode.auto',
      modeDisplayName: 'Auto',
      modeDeleted: false,
      initialStateId: id,
      states: [
        WorkflowRuntimeGraphStateView(
          id: id,
          title: id,
          kind: WorkflowStateKind.atomic,
        ),
      ],
      edges: const [],
    );

final class _GraphFixture {
  _GraphFixture({List<Override> overrides = const [], this.acpPort}) {
    graph = testAppGraph(
      transport: transport,
      clientId: 'workflow-query',
      statisticsFeed: const TestStatisticsFeedPort(),
      acpBusinessPort: acpPort,
    );
    container = ProviderContainer(
      overrides: [appGraphProvider.overrideWithValue(graph), ...overrides],
    );
    addTearDown(() async {
      container.dispose();
      for (final request in transport.requests) {
        if (!request.response.isCompleted) request.response.complete(null);
      }
      final report = await graph.close(budget: testCloseBudget());
      expect(report.complete, isTrue, reason: describeTestCloseReport(report));
    });
  }

  final ControlledAcpBusinessPort? acpPort;
  final transport = _GraphTransport();
  late final AppGraph graph;
  late final ProviderContainer container;

  Future<(AcpConversationSession, ControlledAcpObservation)> openAcp(
    String threadId,
    AcpWorkflowStateView workflowState,
  ) async {
    final remoteSessionId = AcpRemoteSessionId('remote-$threadId');
    final source = ControlledAcpObservation([
      AcpAcceptedFrameView(
        target: AcpSessionTargetView(
          sessionId: 'session-$threadId',
          agentId: 'agent-$threadId',
          threadId: threadId,
          instance: BigInt.one,
        ),
        hasObservation: true,
        workflowState: workflowState,
      ),
      AcpEventFrameView(
        AcpReadyEventView(
          AcpNewSessionResponseView(sessionId: remoteSessionId),
        ),
      ),
      const AcpSettledFrameView(AcpSuccessView<void>(null)),
    ]);
    acpPort!.sources.add(source);
    final owner = await graph.client.acpSessions.openConversation(
      OpenAcpSessionRequestView(
        accountId: 'account',
        expectedConnectionRevision: BigInt.one,
        workspaceId: 'workspace',
        threadId: threadId,
        intent: AcpLoadIntentView(remoteSessionId),
      ),
    );
    await owner.source.waitFor((state) => state.workflowState == workflowState);
    return (owner, source);
  }
}

typedef _Request = ({
  String threadId,
  Completer<WorkflowRuntimeGraphSnapshotView?> response,
});

final class _GraphTransport extends RecordingDemoTransport {
  final requests = <_Request>[];
  final _pending = <int, Completer<_Request>>{};

  Future<_Request> requestAt(int index) => index < requests.length
      ? Future.value(requests[index])
      : (_pending[index] ??= Completer()).future;

  @override
  Future<WorkflowRuntimeGraphSnapshotView?> getThreadWorkflowGraph(
    String threadId,
  ) {
    final response = Completer<WorkflowRuntimeGraphSnapshotView?>();
    final request = (threadId: threadId, response: response);
    requests.add(request);
    _pending.remove(requests.length - 1)?.complete(request);
    return response.future;
  }
}
