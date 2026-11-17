import 'package:anywork/src/app/app_graph.dart';
import 'package:anywork/src/app/theme/material3_theme.dart';
import 'package:anywork/src/l10n/app_localizations.dart';
import 'package:anywork_client/acp_sessions.dart';
import 'package:anywork_client/studio_client.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../../../anywork_client/test/support/acp_business_port.dart';
import '../../../anywork_client/test/support/timeline_transport.dart'
    show TestConversationTransport;
import '../support/pump_client_future.dart';
import '../support/test_app_lifecycle.dart';
import '../support/test_statistics_feed.dart';
import '../support/unused_account_ports.dart';

const acpRemoteFixture = AcpRemoteSessionId('remote');
const acpBooleanFixture = AcpSessionConfigOptionView(
  id: AcpConfigId('server/boolean'),
  name: '保留引用',
  description: '保留服务器提供的来源',
  category: AcpConfigCategoryView.other('vendor-specific'),
  kind: AcpBooleanConfigView(currentValue: false),
);

Widget acpTestApp(Widget child) => MaterialApp(
  locale: const Locale('zh'),
  theme: pureStudioTheme(),
  localizationsDelegates: [
    AppLocalizations.delegate,
    ...GlobalMaterialLocalizations.delegates,
  ],
  supportedLocales: AppLocalizations.supportedLocales,
  home: Scaffold(body: child),
);

void expectAcpPrimaryGeometry(WidgetTester tester, Finder button) {
  final surface = find.descendant(
    of: button,
    matching: find.byWidgetPredicate(
      (widget) => widget is Material && widget.shape is CircleBorder,
    ),
  );
  expect(surface, findsOneWidget);
  final surfaceRect = tester.getRect(surface);
  expect(surfaceRect.size, const Size.square(34));
  final visual = find.descendant(
    of: button,
    matching: find.byWidgetPredicate(
      (widget) => widget is Icon || widget is CircularProgressIndicator,
    ),
  );
  expect(visual, findsOneWidget);
  expect(tester.getCenter(visual), surfaceRect.center);
}

/// Only controls source frames and records calls. All reduction is production.
final class AcpComponentHarness {
  AcpComponentHarness(
    this.graph,
    this.port,
    this.source,
    this.owner,
    this._transport,
  );
  final AppGraph graph;
  AnyworkClient get client => graph.client;
  final ControlledAcpBusinessPort port;
  final ControlledAcpObservation source;
  final AcpConversationSession owner;
  final TestConversationTransport _transport;

  static Future<AcpComponentHarness> create({
    String threadId = 'thread',
    List<AcpSessionConfigOptionView>? options,
    AcpSessionModeStateView? modes,
    List<AcpSessionUpdateView> updates = const [],
    bool resume = false,
    bool child = false,
  }) async {
    final target = AcpSessionTargetView(
      sessionId: 'session',
      agentId: 'agent',
      threadId: threadId,
      instance: BigInt.from(19),
    );
    final source = ControlledAcpObservation([
      AcpAcceptedFrameView(target: target, hasObservation: true),
      AcpEventFrameView(
        AcpReadyEventView(
          AcpNewSessionResponseView(
            sessionId: acpRemoteFixture,
            configOptions: options,
            modes: modes,
          ),
        ),
      ),
      for (final update in updates)
        AcpEventFrameView(
          AcpUpdateEventView(
            AcpSessionNotificationView(
              sessionId: acpRemoteFixture,
              update: update,
            ),
          ),
        ),
      const AcpSettledFrameView(AcpSuccessView<void>(null)),
    ]);
    final port = ControlledAcpBusinessPort()..sources.add(source);
    final transport = TestConversationTransport()
      ..seedThread(
        SessionDirectoryRow(
          sessionId: 'session',
          agentId: 'agent',
          parentAgentId: child ? 'root-agent' : null,
          threadId: threadId,
          workspaceId: 'workspace',
          title: 'ACP 测试会话',
          mode: null,
          delegationMode: DelegationMode.profile,
          delegationPreference: DelegationPreference.balanced,
          workspacePath: '/project',
          role: child ? 'executor' : 'root',
          backend: const AcpAgentBackendView(
            reference: AcpSessionReferenceView(
              accountId: 'account',
              acpSessionId: 'remote',
              cwd: '/project',
            ),
          ),
          updatedAt: DateTime.utc(2025),
        ),
      );
    final accounts = _AcpComponentAccountPorts();
    final graph = testAppGraph(
      transport: transport,
      statisticsFeed: const TestStatisticsFeedPort(),
      clientId: 'acp-components',
      accountFeed: accounts,
      accountConfiguration: accounts,
      accountModels: accounts,
      accountUsage: accounts,
      acpPort: accounts,
      acpBusinessPort: port,
    );
    final client = graph.client;
    client.project.applyProjectDirectory(
      ProjectDirectoryState(
        revision: 1,
        values: const [
          StudioProject(id: 'workspace', name: '本地项目', path: '/project'),
        ],
      ),
    );
    final owner = await client.acpSessions.openConversation(
      OpenAcpSessionRequestView(
        accountId: 'account',
        expectedConnectionRevision: BigInt.one,
        workspaceId: 'workspace',
        threadId: threadId,
        intent: resume
            ? const AcpResumeIntentView(acpRemoteFixture)
            : const AcpLoadIntentView(acpRemoteFixture),
      ),
    );
    return AcpComponentHarness(graph, port, source, owner, transport);
  }

  Future<({ControlledAcpObservation source, AcpConversationSession owner})>
  openSecondConversation() async {
    const remote = AcpRemoteSessionId('remote-second');
    final target = AcpSessionTargetView(
      sessionId: 'session-second',
      agentId: 'agent-second',
      threadId: 'second',
      instance: BigInt.from(20),
    );
    final source = ControlledAcpObservation([
      AcpAcceptedFrameView(target: target, hasObservation: true),
      AcpEventFrameView(
        AcpReadyEventView(AcpNewSessionResponseView(sessionId: remote)),
      ),
      const AcpSettledFrameView(AcpSuccessView<void>(null)),
    ]);
    _transport.seedThread(
      _transport.directoryThreads[owner.state.target!.threadId]!.copyWith(
        sessionId: target.sessionId,
        agentId: target.agentId,
        threadId: target.threadId,
        parentAgentId: null,
        role: 'root',
        backend: const AcpAgentBackendView(
          reference: AcpSessionReferenceView(
            accountId: 'account',
            acpSessionId: 'remote-second',
            cwd: '/project',
          ),
        ),
      ),
    );
    port.sources.add(source);
    final second = await client.acpSessions.openConversation(
      OpenAcpSessionRequestView(
        accountId: 'account',
        expectedConnectionRevision: BigInt.one,
        workspaceId: 'workspace',
        threadId: target.threadId,
        intent: const AcpLoadIntentView(remote),
      ),
    );
    return (source: source, owner: second);
  }

  Widget scope(Widget child) => ProviderScope(
    overrides: [appGraphProvider.overrideWithValue(graph)],
    child: acpTestApp(child),
  );

  void emit(AcpSessionEventView event) {
    final frame = AcpEventFrameView(event);
    final pending = source.read;
    if (pending != null && !pending.isCompleted) {
      pending.complete(frame);
    } else {
      source.frames.add(frame);
    }
  }

  void update(AcpSessionUpdateView update) => emit(
    AcpUpdateEventView(
      AcpSessionNotificationView(sessionId: acpRemoteFixture, update: update),
    ),
  );

  Future<void> close(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    final budget = testCloseBudget();
    final graphClosing = graph.close(budget: budget);
    final graphReport = await pumpClientFuture(
      tester,
      graphClosing,
      'close ACP component AppGraph',
    );
    // As in application shutdown, join the app subtree before its final root.
    final rootClosing = graph.closeLifecycleRoot(budget);
    final rootReport = await pumpClientFuture(
      tester,
      rootClosing,
      'close ACP component lifecycle root',
    );
    final details =
        'AppGraph:\n${describeTestCloseReport(graphReport)}\n'
        'Lifecycle root:\n${describeTestCloseReport(rootReport)}';
    expect(graphReport.complete, isTrue, reason: details);
    expect(rootReport.complete, isTrue, reason: details);
  }
}

final class _AcpComponentAccountPorts extends UnusedAccountPorts {}
