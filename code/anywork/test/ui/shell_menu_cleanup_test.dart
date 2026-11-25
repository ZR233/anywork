import 'dart:async';
import 'dart:convert';

import 'package:anywork/src/app/app_graph.dart';
import 'package:anywork/src/app/theme/material3_theme.dart';
import 'package:anywork/src/domain/models/studio_models.dart';
import 'package:anywork/src/features/conversation/workspace/deferred_runtime_fields.dart';
import 'package:anywork/src/features/shell/studio_shell.dart';
import 'package:anywork/src/features/status/thread_status_bar.dart';
import 'package:anywork/src/features/status/workflow_graph_panel.dart';
import 'package:anywork/src/features/todo/todo_panel.dart';
import 'package:anywork/src/l10n/app_localizations.dart';
import 'package:anywork/src/platform/host_app_icons.dart';
import 'package:anywork/src/platform/terminal_launcher.dart';
import 'package:anywork/src/platform/vscode_launcher.dart';
import 'package:anywork/src/platform/zed_launcher.dart';
import 'package:anywork/src/shared/studio_driver_keys.dart';
import 'package:anywork_client/acp_sessions.dart';
import 'package:anywork_client/studio_client.dart'
    show ThreadNotificationFrame, ThreadRuntimeUpdate;
import 'package:anywork_client/conversation.dart'
    show ConversationSession, CurrentReader;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../../../anywork_client/test/support/acp_business_port.dart';
import '../support/chat_fixtures.dart';
import '../support/pump_client_future.dart';
import '../support/recording_demo_transport.dart';
import '../support/test_app_lifecycle.dart';
import '../support/test_statistics_feed.dart';

void main() {
  testWidgets('workspace menu restores focus and opens the selected path', (
    tester,
  ) async {
    final graph = testAppGraph(
      transport: RecordingDemoTransport(),
      clientId: 'workspace-menu-shell',
      statisticsFeed: const TestStatisticsFeedPort(),
    );
    addTearDown(() => _closeGraph(tester, graph));
    const project = StudioProject(id: 'project', name: 'Demo', path: '/root');
    final row = SessionDirectoryRow(
      sessionId: 'session',
      agentId: 'root-agent',
      threadId: 'root-thread',
      workspaceId: project.id,
      title: 'Demo session',
      mode: null,
      delegationMode: DelegationMode.automatic,
      delegationPreference: DelegationPreference.fast,
      workspacePath: '/work/session',
      backend: const NativeAgentBackendView(
        config: NativeAgentConfigView(),
        status: ThreadStatusView.idle,
      ),
      updatedAt: DateTime.utc(2025),
    );
    final openedUris = <String>[];
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appGraphProvider.overrideWithValue(graph),
          vsCodeAvailabilityProvider.overrideWith((ref) async => true),
          zedAvailabilityProvider.overrideWith((ref) async => false),
          terminalAvailabilityProvider.overrideWith((ref) async => false),
          hostAppIconProvider.overrideWith((ref, app) async => null),
          vsCodeLauncherProvider.overrideWith(
            (ref) =>
                (uri) async => openedUris.add(uri),
          ),
        ],
        child: MaterialApp(
          theme: pureStudioTheme(),
          localizationsDelegates: [
            AppLocalizations.delegate,
            ...GlobalMaterialLocalizations.delegates,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: SessionHeader(
              state: HeaderView(
                selectedRootRow: row,
                selectedProject: project,
                selectedProjectId: project.id,
                workspaceRows: [row],
                agents: const [],
                selectedThreadId: row.threadId,
                runtime: const ThreadRuntimeView(
                  modelId: '',
                  contextTokens: 0,
                  contextWindow: 0,
                  totalTokens: 0,
                  costLabel: '',
                  activeSkills: [],
                  activeMcpServers: [],
                  activeLspServers: [],
                ),
                sessionCost: null,
                pendingInteractions: const [],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final trigger = find.byKey(StudioDriverKeys.sessionOpenWorkspaceMenu);
    final vsCode = find.byKey(StudioDriverKeys.sessionOpenWorkspaceVsCode);
    final zed = find.byKey(StudioDriverKeys.sessionOpenWorkspaceZed);
    await tester.tap(trigger);
    await tester.pumpAndSettle();
    expect(vsCode, findsOneWidget);
    expect(tester.widget<MenuItemButton>(zed).onPressed, isNull);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(vsCode, findsNothing);
    expect(openedUris, isEmpty);
    expect(tester.widget<TextButton>(trigger).focusNode?.hasFocus, isTrue);

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    await tester.tap(vsCode);
    await tester.pumpAndSettle();
    expect(openedUris, [Uri.directory('/work/session').toString()]);
    expect(vsCode, findsNothing);
  });

  testWidgets(
    'deferred entries resume after lease admission and ignore old errors',
    (tester) async {
      const threadId = 'thread-main';
      final transport = _DeferredRuntimeTransport();
      final graph = testAppGraph(
        transport: transport,
        clientId: 'deferred-runtime-shell',
        statisticsFeed: const TestStatisticsFeedPort(),
      );
      addTearDown(() async {
        if (transport.oldReadStarted.isCompleted &&
            !transport.oldWorkflow.isCompleted) {
          transport.oldWorkflow.completeError(StateError('retired workflow'));
        }
        await _closeGraph(tester, graph);
      });

      final (session, stateReader) = await _openRuntimeState(
        tester,
        graph,
        transport,
        threadId,
      );
      final ownerId = stateReader.metadata.currentOwnerId;
      final todo = transport.field(ownerId, 'todo', '1', {
        'callId': 'todo-call',
        'items': [
          {'step': 'Deferred step', 'status': 'pending'},
        ],
      });
      Future<void> publish(String generation, String title) async {
        final workflow = transport.field(ownerId, 'workflow', generation, {
          'revision': int.parse(generation),
          'currentRun': {
            'lineageId': 'workflow-lineage',
            'runId': 'workflow-run',
            'modeId': 'mode.auto',
            'graphRevision': 1,
            'graphHash': 'frozen-graph',
            'currentStateId': 'triage',
            'currentStateTitle': title,
            'lifecycle': 'active',
            'startedAt': 1,
            'updatedAt': 1,
          },
        });
        _publishRuntime(
          session,
          stateReader,
          session.state.runtime!.copyWith(
            workflow: const WorkflowRuntimeView(revision: 0),
            deferred: [todo, workflow],
          ),
        );
        await pumpClientUntil(
          tester,
          () => session.state.runtime?.deferredField('workflow') == workflow,
          'workflow field $generation enters the SDK state',
        );
      }

      await publish('1', 'First workflow');
      await tester.pumpWidget(
        ProviderScope(
          overrides: [appGraphProvider.overrideWithValue(graph)],
          child: MaterialApp(
            theme: pureStudioTheme(),
            localizationsDelegates: [
              AppLocalizations.delegate,
              ...GlobalMaterialLocalizations.delegates,
            ],
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: Column(
                children: [
                  const ThreadStatusConnector(threadId: threadId),
                  const Expanded(
                    child: ThreadWorkflowGraphPanelConnector(
                      threadId: threadId,
                    ),
                  ),
                  SizedBox(
                    height: 90,
                    child: Consumer(
                      builder: (context, ref, _) {
                        final todo = ref.watch(deferredTodoProvider(threadId));
                        return switch (todo.asData?.value) {
                          final value? => TodoPanel(todo: value),
                          null => const SizedBox.shrink(),
                        };
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(graph.timeline.lease(threadId), isNull);
      expect(find.text('Deferred step'), findsNothing);
      expect(find.text('First workflow'), findsNothing);

      graph.timeline.updateReadDemand(chatDemand);
      await pumpClientUntil(
        tester,
        () =>
            find.text('Deferred step').evaluate().isNotEmpty &&
            find.text('First workflow').evaluate().isNotEmpty,
        'unchanged fields are read after lease admission',
      );
      expect(
        transport.fieldReads
            .where((ref) => ref.contentKey == 'workflow')
            .length,
        1,
      );

      await publish('2', 'Old in-flight workflow');
      await pumpClientUntil(
        tester,
        () => transport.oldReadStarted.isCompleted,
        'old read starts',
      );
      final panel = find.byType(WorkflowGraphPanel);
      expect(tester.widget<WorkflowGraphPanel>(panel).run, isNull);
      await publish('3', 'Latest workflow');
      await pumpClientUntil(
        tester,
        () =>
            find.text('Latest workflow').evaluate().isNotEmpty &&
            tester.widget<WorkflowGraphPanel>(panel).run?.currentStateTitle ==
                'Latest workflow',
        'new generation draws while the old body read is still blocked',
      );
      transport.oldWorkflow.completeError(StateError('retired workflow'));
      await tester.pump();
      expect(find.text('Latest workflow'), findsOneWidget);
      expect(find.text('Old in-flight workflow'), findsNothing);
      expect(tester.widget<WorkflowGraphPanel>(panel).error, isNull);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Native workflow graph ignores a late response for the old run', (
    tester,
  ) async {
    const threadId = 'thread-main';
    const oldId = 'old-stage';
    const currentId = 'editing_documents';
    final transport = _GraphRaceTransport();
    final graph = testAppGraph(
      transport: transport,
      clientId: 'workflow-graph-race-shell',
      statisticsFeed: const TestStatisticsFeedPort(),
    );
    addTearDown(() async {
      transport.completePendingRequests();
      await _closeGraph(tester, graph);
    });

    final (session, stateReader) = await _openRuntimeState(
      tester,
      graph,
      transport,
      threadId,
    );
    void publishRun(int revision, String stateId) {
      _publishRuntime(
        session,
        stateReader,
        session.state.runtime!.copyWith(
          deferred: [],
          workflow: WorkflowRuntimeView(
            revision: revision,
            currentRun: WorkflowRunView(
              lineageId: 'graph-lineage',
              runId: 'graph-run-$revision',
              modeId: 'mode.auto',
              graphRevision: revision,
              graphHash: 'graph-$revision',
              currentStateId: stateId,
              terminal: false,
              startedAt: DateTime.utc(2025),
              updatedAt: DateTime.utc(2025),
            ),
          ),
        ),
      );
    }

    await tester.pumpWidget(
      _graphTestApp(
        graph,
        const ThreadWorkflowGraphPanelConnector(threadId: threadId),
      ),
    );
    final panel = find.byType(WorkflowGraphPanel);
    WorkflowGraphPanel renderedPanel() =>
        tester.widget<WorkflowGraphPanel>(panel);
    await pumpClientUntil(
      tester,
      () => renderedPanel().graph != null,
      'initial graph renders',
    );

    transport.holdRequests = true;
    publishRun(2, oldId);
    await pumpClientUntil(
      tester,
      () => transport.requests.isNotEmpty,
      'old graph request starts',
    );
    expect(renderedPanel().run?.graphRevision, 2);
    expect(renderedPanel().loading, isTrue);
    expect(renderedPanel().graph, isNull);

    publishRun(3, currentId);
    await pumpClientUntil(
      tester,
      () => transport.requests.length >= 2,
      'current graph request starts while the old request is still pending',
    );
    expect(transport.requests.map((request) => request.threadId), [
      threadId,
      threadId,
    ]);
    expect(renderedPanel().run?.graphRevision, 3);
    expect(renderedPanel().graph, isNull);

    transport.requests.last.response.complete(_graphSnapshot(currentId));
    final currentBadge = find.byKey(
      const ValueKey('workflow-graph-current-$currentId'),
    );
    await pumpClientUntil(
      tester,
      () => currentBadge.evaluate().isNotEmpty,
      'current graph and its active node render first',
    );
    expect(transport.requests.first.response.isCompleted, isFalse);

    transport.requests.first.response.complete(_graphSnapshot(oldId));
    await tester.pump();
    expect(renderedPanel().graph?.initialStateId, currentId);
    expect(renderedPanel().run?.graphRevision, 3);
    expect(currentBadge, findsOneWidget);
    expect(
      find.byKey(const ValueKey('workflow-graph-node-$oldId')),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });
  testWidgets('ACP uses its observed graph and isolates a late fallback', (
    tester,
  ) async {
    const oldThread = 'acp-old';
    const currentThread = 'acp-current';
    const missingGraph = AcpWorkflowStateView(modeId: 'mode.auto');
    final transport = _GraphRaceTransport()..holdRequests = true;
    final port = ControlledAcpBusinessPort();
    final graph = testAppGraph(
      transport: transport,
      clientId: 'acp-graph-race-shell',
      statisticsFeed: const TestStatisticsFeedPort(),
      acpBusinessPort: port,
    );
    final selection = ValueNotifier(currentThread);
    addTearDown(selection.dispose);
    addTearDown(() async {
      transport.completePendingRequests();
      await _closeGraph(tester, graph);
    });

    final canonical = _graphSnapshot('canonical-stage');
    final (owner, source) = await _openAcpGraphSession(
      tester,
      graph,
      port,
      currentThread,
      AcpWorkflowStateView(modeId: 'mode.auto', graph: canonical),
    );
    await _openAcpGraphSession(tester, graph, port, oldThread, missingGraph);

    await tester.pumpWidget(
      _graphTestApp(
        graph,
        ValueListenableBuilder(
          valueListenable: selection,
          builder: (context, threadId, _) =>
              AcpWorkflowGraphPanelConnector(threadId: threadId),
        ),
      ),
    );
    final connector = find.byType(AcpWorkflowGraphPanelConnector);
    final element = tester.element(connector);
    final panel = find.byType(WorkflowGraphPanel);
    WorkflowGraphPanel renderedPanel() =>
        tester.widget<WorkflowGraphPanel>(panel);
    await pumpClientUntil(
      tester,
      () => renderedPanel().graph == canonical,
      'observed ACP graph renders without RPC',
    );
    expect(transport.requests, isEmpty);

    selection.value = oldThread;
    await pumpClientUntil(
      tester,
      () => transport.requests.isNotEmpty,
      'old ACP thread falls back when its observed graph is missing',
    );
    expect(transport.requests.single.threadId, oldThread);
    expect(renderedPanel().graph, isNull);
    expect(renderedPanel().loading, isTrue);

    await pumpClientUntil(
      tester,
      () => source.waitingForFrame.isCompleted,
      'ACP observation is ready for a workflow update',
    );
    source.read!.complete(
      const AcpEventFrameView(AcpWorkflowStateUpdatedEventView(missingGraph)),
    );
    await pumpClientUntil(
      tester,
      () => owner.state.workflowState == missingGraph,
      'current ACP thread reports that its graph is missing',
    );
    selection.value = currentThread;
    await pumpClientUntil(
      tester,
      () => transport.requests.length >= 2,
      'current ACP fallback starts before the old request finishes',
    );
    expect(tester.element(connector), same(element));
    expect(transport.requests.map((request) => request.threadId), [
      oldThread,
      currentThread,
    ]);
    expect(renderedPanel().graph, isNull);
    expect(renderedPanel().loading, isTrue);

    final currentGraph = _graphSnapshot('current-stage');
    transport.requests.last.response.complete(currentGraph);
    await pumpClientUntil(
      tester,
      () => renderedPanel().graph == currentGraph,
      'current ACP fallback renders first',
    );
    expect(transport.requests.first.response.isCompleted, isFalse);

    transport.requests.first.response.complete(_graphSnapshot('old-stage'));
    await tester.pump();
    expect(renderedPanel().graph, currentGraph);
    expect(
      find.byKey(const ValueKey('workflow-graph-node-old-stage')),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });
}

Widget _graphTestApp(AppGraph graph, Widget panel) => ProviderScope(
  overrides: [appGraphProvider.overrideWithValue(graph)],
  child: MaterialApp(
    theme: pureStudioTheme(),
    localizationsDelegates: [
      AppLocalizations.delegate,
      ...GlobalMaterialLocalizations.delegates,
    ],
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(body: panel),
  ),
);

Future<(AcpConversationSession, ControlledAcpObservation)> _openAcpGraphSession(
  WidgetTester tester,
  AppGraph graph,
  ControlledAcpBusinessPort port,
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
      AcpReadyEventView(AcpNewSessionResponseView(sessionId: remoteSessionId)),
    ),
    const AcpSettledFrameView(AcpSuccessView<void>(null)),
  ]);
  port.sources.add(source);
  final owner = await pumpClientFuture(
    tester,
    graph.client.acpSessions.openConversation(
      OpenAcpSessionRequestView(
        accountId: 'account',
        expectedConnectionRevision: BigInt.one,
        workspaceId: 'workspace',
        threadId: threadId,
        intent: AcpLoadIntentView(remoteSessionId),
      ),
    ),
    'open ACP conversation $threadId',
  );
  return (owner, source);
}

Future<(ConversationSession, RecordingCurrentReader)> _openRuntimeState(
  WidgetTester tester,
  AppGraph graph,
  RecordingDemoTransport transport,
  String threadId,
) async {
  await pumpClientFuture(tester, graph.client.bootstrap(), 'bootstrap');
  graph.setConversationPageVisible(true);
  await pumpClientFuture(
    tester,
    graph.client.directoryCommands.selectThread(threadId),
    'select thread before the viewport declares demand',
  );
  final session = graph.client.conversations.existingSession(threadId)!;
  await pumpClientUntil(
    tester,
    () => session.state.hasSnapshot,
    'session state',
  );
  final reader = transport.currentReaders.singleWhere(
    (reader) => reader.threadId == threadId && reader.demand.maxItems == 128,
  );
  await pumpClientUntil(
    tester,
    () => reader.watchEntered.isCompleted,
    'state watch ready',
  );
  return (session, reader);
}

void _publishRuntime(
  ConversationSession session,
  RecordingCurrentReader reader,
  ThreadRuntimeView runtime,
) {
  final revision = session.state.revision + 1;
  reader.emitState(
    ThreadNotificationFrame(
      threadId: session.threadId,
      epoch: session.state.streamEpoch ?? 1,
      baseRevision: revision - 1,
      revision: revision,
      update: ThreadRuntimeUpdate(
        runtime: runtime,
        todo: null,
        modelRoute: session.state.modelRoute,
      ),
    ),
  );
}

WorkflowRuntimeGraphSnapshotView _graphSnapshot(String stateId) =>
    WorkflowRuntimeGraphSnapshotView(
      modeId: 'mode.auto',
      modeDisplayName: 'Auto',
      modeDeleted: false,
      initialStateId: stateId,
      states: [
        WorkflowRuntimeGraphStateView(
          id: stateId,
          title: 'Workflow stage',
          kind: WorkflowStateKind.atomic,
        ),
      ],
      edges: const [],
    );

Future<void> _closeGraph(WidgetTester tester, AppGraph graph) async {
  await tester.pumpWidget(const SizedBox.shrink());
  final report = await pumpClientFuture(
    tester,
    graph.close(budget: testCloseBudget()),
    'close shell test graph',
  );
  expect(report.complete, isTrue, reason: describeTestCloseReport(report));
}

final class _GraphRaceTransport extends RecordingDemoTransport {
  bool holdRequests = false;
  final requests =
      <
        ({
          String threadId,
          Completer<WorkflowRuntimeGraphSnapshotView?> response,
        })
      >[];

  void completePendingRequests() {
    for (final request in requests) {
      if (!request.response.isCompleted) request.response.complete(null);
    }
  }

  @override
  Future<WorkflowRuntimeGraphSnapshotView?> getThreadWorkflowGraph(
    String threadId,
  ) {
    if (!holdRequests) return super.getThreadWorkflowGraph(threadId);
    final response = Completer<WorkflowRuntimeGraphSnapshotView?>();
    requests.add((threadId: threadId, response: response));
    return response.future;
  }
}

final class _DeferredRuntimeTransport extends RecordingDemoTransport {
  final _bodies = <CurrentContentRef, List<int>>{};
  final fieldReads = <CurrentContentRef>[];
  final oldReadStarted = Completer<void>();
  final oldWorkflow = Completer<ContentWindow>();

  BodyCurrentStateField field(
    String ownerId,
    String name,
    String generation,
    Map<String, Object> payload,
  ) {
    final bytes = utf8.encode(jsonEncode(payload));
    final ref = CurrentContentRef(
      ownerId: ownerId,
      domain: 'state:runtime',
      entityId: 'state',
      contentKey: name,
      generation: generation,
    );
    _bodies[ref] = bytes;
    return BodyCurrentStateField(
      field: name,
      reference: ref,
      byteLength: bytes.length,
    );
  }

  @override
  Future<CurrentReader> openCurrentReader(
    String threadId, {
    required int currentProtocolVersion,
    required ReadDemand demand,
  }) async {
    final reader = await super.openCurrentReader(
      threadId,
      currentProtocolVersion: currentProtocolVersion,
      demand: demand,
    ) as RecordingCurrentReader;
    reader.onReadBody = (ref, range) async {
      final bytes = _bodies[ref];
      if (bytes == null) {
        return reader.inner.readBody(reference: ref, range: range);
      }
      fieldReads.add(ref);
      if (ref.contentKey == 'workflow' && ref.generation == '2') {
        if (!oldReadStarted.isCompleted) oldReadStarted.complete();
        return oldWorkflow.future;
      }
      return ContentWindow(
        offset: range.offset,
        bytes: bytes.skip(range.offset).take(range.maxBytes).toList(),
        generation: ref.generation,
        availableThrough: bytes.length,
        sealed: true,
      );
    };
    return reader;
  }
}
