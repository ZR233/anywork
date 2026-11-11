import 'dart:async';

import 'package:anywork/src/app/theme/material3_theme.dart';
import 'package:anywork/src/features/conversation/acp/acp_views.dart';
import 'package:anywork/src/features/conversation/acp/connectors/acp_status_bar_connector.dart';
import 'package:anywork/src/features/conversation/acp/view_models/acp_external_history_view_model.dart';
import 'package:anywork/src/features/conversation/acp/view_models/acp_session_view_model.dart'
    show acpConversationOwnerProvider;
import 'package:anywork/src/l10n/app_localizations.dart';
import 'package:anywork/src/presentation/providers/client_provider.dart';
import 'package:anywork_client/acp_sessions.dart';
import 'package:anywork_client/studio_client.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../../../anywork_client/test/support/acp_business_port.dart';
import '../../../anywork_client/test/support/timeline_transport.dart'
    show TestConversationTransport;

Finder _historyTrigger() => find.byKey(
  ValueKey(AcpViewKeyValues.externalHistoryButton('thread-source')),
);

void main() {
  testWidgets('仅打开面板显式读取一次，列表显示对端原值', (tester) async {
    final harness = await _HistoryHarness.create(listSessions: true);
    addTearDown(harness.close);
    harness.port.listValue = AcpListSessionsResponseView(
      sessions: [
        AcpSessionInfoView(
          sessionId: const AcpRemoteSessionId('peer/session-7'),
          cwd: '/raw/workdir',
          title: '原始对端标题',
          updatedAt: 'raw-time-value',
        ),
      ],
      nextCursor: 'page-2',
    );
    await tester.pumpWidget(harness.scope(operations: harness.operations()));
    await tester.pumpAndSettle();
    expect(harness.listCalls, isEmpty);
    expect(
      tester.widget<ButtonStyleButton>(_historyTrigger()).onPressed,
      isNotNull,
    );

    await tester.tap(find.text('外部会话'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('外部 ACP 会话'), findsOneWidget);
    expect(harness.listCalls, hasLength(1));
    expect(find.text('原始对端标题'), findsOneWidget);
    expect(find.textContaining('peer/session-7'), findsOneWidget);
    expect(find.textContaining('/raw/workdir'), findsOneWidget);
    expect(find.textContaining('raw-time-value'), findsOneWidget);

    await tester.tap(find.text('关闭'));
    await tester.pumpAndSettle();
    expect(
      harness.port.calls.where((call) => call.$1 == 'closeMember'),
      isEmpty,
    );
  });

  testWidgets('无 listSessions 能力不请求；未知能力说明可见', (tester) async {
    final harness = await _HistoryHarness.create(listSessions: false);
    addTearDown(harness.close);
    await tester.pumpWidget(harness.scope(operations: harness.operations()));
    await tester.pumpAndSettle();
    expect(
      tester.widget<ButtonStyleButton>(_historyTrigger()).onPressed,
      isNull,
    );
    expect(find.byTooltip('此 ACP 服务不支持列出会话'), findsOneWidget);
    expect(harness.listCalls, isEmpty);
  });

  testWidgets('owner初始未就绪时按钮订阅状态，Ready后启用但不自动读取', (tester) async {
    final harness = await _HistoryHarness.create(
      listSessions: true,
      initialize: false,
    );
    addTearDown(harness.close);
    await tester.pumpWidget(harness.scope(operations: harness.operations()));
    await tester.pumpAndSettle();
    expect(
      tester.widget<ButtonStyleButton>(_historyTrigger()).onPressed,
      isNull,
    );
    expect(find.byTooltip('ACP 服务能力尚未确认'), findsOneWidget);

    harness.emit(
      const AcpInitializedEventView(
        AcpAgentCapabilitiesView(
          image: false,
          audio: false,
          embeddedContext: false,
          loadSession: true,
          listSessions: true,
          resumeSession: true,
        ),
      ),
    );
    await tester.pump();
    expect(
      tester.widget<ButtonStyleButton>(_historyTrigger()).onPressed,
      isNull,
    );

    harness.emit(
      AcpReadyEventView(
        AcpNewSessionResponseView(
          sessionId: const AcpRemoteSessionId('owner-remote'),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    expect(
      tester.widget<ButtonStyleButton>(_historyTrigger()).onPressed,
      isNotNull,
    );
    expect(harness.listCalls, isEmpty);
  });

  testWidgets('Owner Provider异步完成后按钮启用但不自动读取', (tester) async {
    final harness = await _HistoryHarness.create(listSessions: true);
    addTearDown(harness.close);
    final owner = Completer<AcpConversationSession>();
    await tester.pumpWidget(
      harness.scope(
        ownerFuture: owner.future,
        operations: harness.operations(),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      tester.widget<ButtonStyleButton>(_historyTrigger()).onPressed,
      isNull,
    );

    owner.complete(harness.owner);
    await tester.pumpAndSettle();
    expect(
      tester.widget<ButtonStyleButton>(_historyTrigger()).onPressed,
      isNotNull,
    );
    expect(harness.listCalls, isEmpty);
  });

  testWidgets('透传远端 session ID 与分页 cursor，分页失败保留已读条目', (tester) async {
    await tester.binding.setSurfaceSize(const Size(960, 720));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final harness = await _HistoryHarness.create(listSessions: true);
    addTearDown(harness.close);
    harness.port.listValue = AcpListSessionsResponseView(
      sessions: [
        AcpSessionInfoView(
          sessionId: const AcpRemoteSessionId('remote/exact-id'),
          cwd: '/first',
          title: '保留的条目',
        ),
      ],
      nextCursor: 'cursor/exact-page-2',
    );
    final operations = AcpExternalHistoryOperations(
      list: harness.list,
      open: (threadId, remoteSessionId, {resume = false, cwd}) async {
        harness.openCalls.add((threadId, remoteSessionId, resume, cwd));
        throw StateError('simulated uncertain open outcome');
      },
    );
    await tester.pumpWidget(harness.scope(operations: operations));
    await tester.pumpAndSettle();
    await tester.tap(find.text('外部会话'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    final loadButton = find.byKey(
      ValueKey(AcpViewKeyValues.externalHistoryLoad('remote/exact-id')),
    );
    await tester.tap(loadButton);
    await tester.pumpAndSettle();
    expect(harness.openCalls, hasLength(1));
    expect(harness.openCalls.single.$1, 'thread-source');
    expect(
      harness.openCalls.single.$2,
      const AcpRemoteSessionId('remote/exact-id'),
    );
    expect(harness.openCalls.single.$3, isFalse);
    expect(harness.openCalls.single.$4, '/first');
    expect(find.textContaining('打开结果未知'), findsOneWidget);
    expect(loadButton, findsNothing);
    expect(harness.openCalls, hasLength(1));

    await tester.tap(find.text('关闭'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('外部会话'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.textContaining('打开结果未知'), findsOneWidget);
    expect(loadButton, findsNothing);
    harness.port.commandError = StateError('page unavailable');
    await tester.tap(find.text('加载更多'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(harness.listCalls.last.$2, 'cursor/exact-page-2');
    expect(find.text('保留的条目'), findsOneWidget);
    expect(find.textContaining('page unavailable'), findsOneWidget);
  });
}

final class _HistoryHarness {
  _HistoryHarness(this.client, this.port, this.owner, this.source);

  final AnyworkClient client;
  final ControlledAcpBusinessPort port;
  final AcpConversationSession owner;
  final ControlledAcpObservation source;
  final openCalls = <(String, AcpRemoteSessionId, bool, String?)>[];
  final listCalls = <(String, String?)>[];

  Future<AcpListSessionsResponseView> list(
    String threadId, {
    String? cursor,
  }) async {
    listCalls.add((threadId, cursor));
    final error = port.commandError;
    if (error != null) throw error;
    return port.listValue;
  }

  AcpExternalHistoryOperations operations({bool failOpen = false}) =>
      AcpExternalHistoryOperations(
        list: list,
        open: (threadId, remoteSessionId, {resume = false, cwd}) async {
          openCalls.add((threadId, remoteSessionId, resume, cwd));
          if (failOpen) throw StateError('simulated uncertain open outcome');
          return owner;
        },
      );

  static Future<_HistoryHarness> create({
    required bool listSessions,
    bool initialize = true,
  }) async {
    final target = AcpSessionTargetView(
      sessionId: 'owner-session',
      agentId: 'agent',
      threadId: 'thread-source',
      instance: BigInt.from(42),
    );
    const remoteId = AcpRemoteSessionId('owner-remote');
    final source = ControlledAcpObservation([
      AcpAcceptedFrameView(target: target, hasObservation: true),
      if (initialize) ...[
        AcpEventFrameView(
          AcpInitializedEventView(
            AcpAgentCapabilitiesView(
              image: false,
              audio: false,
              embeddedContext: false,
              loadSession: true,
              listSessions: listSessions,
              resumeSession: true,
            ),
          ),
        ),
        AcpEventFrameView(
          AcpReadyEventView(AcpNewSessionResponseView(sessionId: remoteId)),
        ),
        const AcpSettledFrameView(AcpSuccessView<void>(null)),
      ],
    ]);
    final port = ControlledAcpBusinessPort()..sources.add(source);
    final client = AnyworkClient(
      transport: TestConversationTransport(),
      clientId: 'external-history-test',
      acpBusinessPort: port,
    );
    final owner = await client.acpSessions.openConversation(
      OpenAcpSessionRequestView(
        accountId: 'account',
        expectedConnectionRevision: BigInt.one,
        workspaceId: 'workspace',
        threadId: 'thread-source',
        intent: AcpLoadIntentView(remoteId),
      ),
    );
    if (initialize) {
      await owner.source.waitFor(
        (state) => state.ready || state.error != null || state.observationEnded,
      );
    }
    return _HistoryHarness(client, port, owner, source);
  }

  void emit(AcpSessionEventView event) {
    final pending = source.read;
    if (pending != null && !pending.isCompleted) {
      pending.complete(AcpEventFrameView(event));
    } else {
      source.frames.add(AcpEventFrameView(event));
    }
  }

  Widget scope({
    AcpExternalHistoryOperations? operations,
    Future<AcpConversationSession>? ownerFuture,
  }) => ProviderScope(
    overrides: [
      anyworkClientProvider.overrideWithValue(client),
      if (ownerFuture != null)
        acpConversationOwnerProvider.overrideWith(
          (ref, threadId) => ownerFuture,
        ),
      if (operations != null)
        acpExternalHistoryOperationsProvider.overrideWithValue(operations),
    ],
    child: MaterialApp(
      locale: const Locale('zh'),
      theme: pureStudioTheme(),
      localizationsDelegates: [
        AppLocalizations.delegate,
        ...GlobalMaterialLocalizations.delegates,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      home: const Scaffold(
        body: Align(
          alignment: Alignment.bottomCenter,
          child: AcpStatusBarConnector(threadId: 'thread-source'),
        ),
      ),
    ),
  );

  void close() => source.requestClose();
}
