import 'package:anywork/src/features/conversation/acp/acp_views.dart';
import 'package:anywork/src/features/conversation/acp/connectors/acp_status_bar_connector.dart';
import 'package:anywork/src/features/conversation/acp/view_models/acp_external_history_view_model.dart';
import 'package:anywork/src/features/conversation/acp/view_models/acp_status_bar_view_model.dart';
import 'package:anywork/src/features/status/status_bar_item.dart';
import 'package:anywork/src/shared/studio_context_usage_ring.dart';
import 'package:anywork_client/acp_sessions.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'acp_components_support.dart';

AcpUsageUpdateView _usage(int used, int size, {double? amount}) =>
    AcpUsageUpdateView(
      used: BigInt.from(used),
      size: BigInt.from(size),
      cost: amount == null
          ? null
          : AcpCostView(amount: amount, currency: 'USD'),
    );

const _capabilities = AcpAgentCapabilitiesView(
  image: false,
  audio: false,
  embeddedContext: false,
  loadSession: true,
  listSessions: true,
  resumeSession: true,
);

void main() {
  testWidgets(
    'unknown ring shows neutral fallback, retains cost across omitted cost, and avoids u64 overflow',
    (tester) async {
      final h = await AcpComponentHarness.create();
      addTearDown(() => h.close(tester));
      final semantics = tester.ensureSemantics();
      try {
        await tester.pumpWidget(
          h.scope(const AcpStatusBarConnector(threadId: 'thread')),
        );
        await tester.pumpAndSettle();
        expect(find.byType(ContextUsageRing), findsOneWidget);
        expect(
          tester
              .widget<ContextUsageRing>(find.byType(ContextUsageRing))
              .progress,
          isNull,
        );
        expect(
          tester.getSemantics(find.bySemanticsLabel('上下文')).value,
          '对端暂未报告上下文占用',
        );
        expect(find.textContaining('USD'), findsNothing);

        h.update(_usage(0, 100, amount: 0));
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<ContextUsageRing>(find.byType(ContextUsageRing))
              .progress,
          0,
        );
        expect(find.text('0.0 USD'), findsOneWidget);
        expect(find.bySemanticsLabel('上下文'), findsOneWidget);
        expect(
          tester.getSemantics(find.bySemanticsLabel('上下文')).value,
          contains('0%'),
        );

        h.update(_usage(25, 100, amount: 1.5));
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<ContextUsageRing>(find.byType(ContextUsageRing))
              .progress,
          0.25,
        );
        expect(find.text('1.5 USD'), findsOneWidget);
        expect(
          tester.getSemantics(find.bySemanticsLabel('上下文')).value,
          contains('25%'),
        );

        h.update(_usage(1, 1000));
        await tester.pumpAndSettle();
        expect(
          tester.getSemantics(find.bySemanticsLabel('上下文')).value,
          contains('<1%'),
        );
        h.update(_usage(999, 1000));
        await tester.pumpAndSettle();
        expect(
          tester.getSemantics(find.bySemanticsLabel('上下文')).value,
          contains('<100%'),
        );

        // Omitting cost on later usage updates retains the last valid cost.
        h.update(_usage(25, 100));
        await tester.pumpAndSettle();
        expect(find.text('1.5 USD'), findsOneWidget);
        expect(find.byType(ContextUsageRing), findsOneWidget);

        // Zero capacity falls back to a neutral ring rather than disappearing.
        h.update(_usage(25, 0, amount: 2));
        await tester.pumpAndSettle();
        expect(find.byType(ContextUsageRing), findsOneWidget);
        expect(
          tester
              .widget<ContextUsageRing>(find.byType(ContextUsageRing))
              .progress,
          isNull,
        );
        expect(find.bySemanticsLabel('上下文'), findsOneWidget);
        expect(find.text('2.0 USD'), findsOneWidget);

        h.update(
          AcpUsageUpdateView(
            used: BigInt.parse('18446744073709551615'),
            size: BigInt.one,
          ),
        );
        await tester.pumpAndSettle();
        expect(
          tester.getSemantics(find.bySemanticsLabel('上下文')).value,
          contains('1844674407370955161500%'),
        );
        expect(
          tester
              .widget<ContextUsageRing>(find.byType(ContextUsageRing))
              .progress,
          1,
        );
        expect(tester.takeException(), isNull);
      } finally {
        semantics.dispose();
      }
    },
  );

  testWidgets('independent VM notifications and component rebuilds', (
    tester,
  ) async {
    final h = await AcpComponentHarness.create(
      updates: [_usage(25, 100, amount: 1)],
    );
    addTearDown(() => h.close(tester));
    await tester.pumpWidget(
      h.scope(const AcpStatusBarConnector(threadId: 'thread')),
    );
    await tester.pumpAndSettle();
    final container = ProviderScope.containerOf(
      tester.element(find.byType(AcpStatusBarConnector)),
    );
    final changes = [0, 0, 0, 0, 0];
    final subscriptions = [
      container.listen(
        acpStatusBarViewModelProvider('thread'),
        (_, _) => changes[0]++,
      ),
      container.listen(
        acpContextUsageViewModelProvider('thread'),
        (_, _) => changes[1]++,
      ),
      container.listen(
        acpCostViewModelProvider('thread'),
        (_, _) => changes[2]++,
      ),
      container.listen(
        acpExternalHistoryButtonViewModelProvider('thread'),
        (_, _) => changes[3]++,
      ),
      container.listen(
        acpThroughputViewModelProvider('thread'),
        (_, _) => changes[4]++,
      ),
    ];
    addTearDown(() {
      for (final subscription in subscriptions) {
        subscription.close();
      }
    });
    List<Widget> readouts() => [
      tester.widget(find.byType(AcpConnectionStatusView)),
      tester.widget(find.byType(AcpContextUsageView)),
      tester.widget(find.byType(AcpCostReadoutView)),
      tester.widget(find.byType(AcpExternalHistoryButtonView)),
      tester.widget(find.byType(TokenThroughputReadout)),
    ];
    var before = readouts();
    final layout = tester.widget(find.byType(AcpStatusBarView));
    void expectChanges(List<int> expected) {
      expect(changes, expected);
      final after = readouts();
      for (var i = 0; i < expected.length; i++) {
        expect(
          identical(after[i], before[i]),
          expected[i] == 0,
          reason: 'Only dependent component $i may rebuild',
        );
        changes[i] = 0;
      }
      before = after;
      expect(tester.widget(find.byType(AcpStatusBarView)), same(layout));
    }

    h.update(
      const AcpAgentMessageChunkView(
        AcpContentChunkView(content: AcpTextContentView(text: 'text')),
      ),
    );
    await tester.pumpAndSettle();
    expectChanges([0, 0, 0, 0, 0]);
    expect(find.byType(AcpContextDetailView), findsNothing);
    h.update(_usage(25, 100, amount: 2));
    await tester.pumpAndSettle();
    expectChanges([0, 0, 1, 0, 0]);
    h.update(_usage(50, 100, amount: 2));
    await tester.pumpAndSettle();
    expectChanges([0, 1, 0, 0, 0]);
    h.update(_usage(50, 100));
    await tester.pumpAndSettle();
    // Cost is retained when omitted on usage update.
    expectChanges([0, 0, 0, 0, 0]);
    h.update(_usage(50, 100, amount: 2));
    await tester.pumpAndSettle();
    expectChanges([0, 0, 0, 0, 0]);
    h.update(_usage(50, 0, amount: 2));
    await tester.pumpAndSettle();
    expectChanges([0, 1, 0, 0, 0]);
    h.update(_usage(50, 100, amount: 2));
    await tester.pumpAndSettle();
    expectChanges([0, 1, 0, 0, 0]);
    h.emit(const AcpInitializedEventView(_capabilities));
    await tester.pumpAndSettle();
    expectChanges([0, 0, 0, 1, 0]);

    // Equal metric values and unrelated capability changes do not notify.
    h.update(_usage(50, 100, amount: 2));
    h.emit(
      const AcpInitializedEventView(
        AcpAgentCapabilitiesView(
          image: true,
          audio: true,
          embeddedContext: true,
          loadSession: true,
          listSessions: true,
          resumeSession: true,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expectChanges([0, 0, 0, 0, 0]);

    final run = AcpRunIdView(instance: BigInt.one, sequence: BigInt.one);
    h.port.run = run;
    await h.owner.send(const [AcpTextContentView(text: 'question')]);
    await tester.pumpAndSettle();
    expectChanges([1, 0, 0, 0, 0]);
    h.emit(
      const AcpUpdateEventView(
        AcpSessionNotificationView(
          sessionId: acpRemoteFixture,
          update: AcpAgentMessageChunkView(
            AcpContentChunkView(content: AcpTextContentView(text: 'answer')),
          ),
        ),
        textPerformance: (estimatedOutputTokens: 4, responseMillis: 100),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('≈ 40 词元/秒'), findsOneWidget);
    expectChanges([0, 0, 0, 0, 1]);
    h.emit(
      const AcpUpdateEventView(
        AcpSessionNotificationView(
          sessionId: acpRemoteFixture,
          update: AcpAgentMessageChunkView(
            AcpContentChunkView(content: AcpTextContentView(text: ' more')),
          ),
        ),
        textPerformance: (estimatedOutputTokens: 8, responseMillis: 200),
      ),
    );
    await tester.pumpAndSettle();
    expectChanges([0, 0, 0, 0, 0]);
    h.emit(
      AcpCompletedEventView(
        AcpCompletedRunView(
          run: run,
          completionSequence: BigInt.one,
          result: const AcpSuccessView(
            AcpPromptResponseView(stopReason: AcpStopReasonView.maxTokens),
          ),
          summary: 'done',
          truncated: false,
        ),
      ),
    );
    await tester.pumpAndSettle();
    // Completing without a textPerformance override retains last valid speed.
    expectChanges([1, 0, 0, 0, 0]);
    expect(find.text('≈ 40 词元/秒'), findsOneWidget);
    expect(
      tester
          .widget<AcpConnectionStatusView>(find.byType(AcpConnectionStatusView))
          .state
          .stopReason,
      AcpStopReasonKind.maxTokens,
    );
    h.emit(const AcpGapEventView(AcpObservationGapView.windowExceeded));
    await tester.pumpAndSettle();
    expectChanges([1, 1, 0, 1, 0]);
    expect(find.byType(ContextUsageRing), findsOneWidget);
    expect(
      tester.widget<ContextUsageRing>(find.byType(ContextUsageRing)).progress,
      0.5,
    );
    expect(find.text('2.0 USD'), findsOneWidget);
    expect(find.text('≈ 40 词元/秒'), findsOneWidget);
    expect(h.port.calls.where((call) => call.$1 == 'open'), hasLength(1));
  });

  for (final end in ['eof', 'failure']) {
    testWidgets('$end retains last valid metrics in status bar', (
      tester,
    ) async {
      final h = await AcpComponentHarness.create(
        updates: [_usage(25, 100, amount: 1)],
      );
      addTearDown(() => h.close(tester));
      await tester.pumpWidget(
        h.scope(const AcpStatusBarConnector(threadId: 'thread')),
      );
      await tester.pumpAndSettle();
      h.emit(
        const AcpUpdateEventView(
          AcpSessionNotificationView(
            sessionId: acpRemoteFixture,
            update: AcpAgentMessageChunkView(
              AcpContentChunkView(content: AcpTextContentView(text: 'hi')),
            ),
          ),
          textPerformance: (estimatedOutputTokens: 12, responseMillis: 200),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(ContextUsageRing), findsOneWidget);
      expect(find.text('1.0 USD'), findsOneWidget);
      expect(find.text('≈ 60 词元/秒'), findsOneWidget);
      if (end == 'eof') {
        h.source.read!.complete(null);
      } else {
        h.source.read!.completeError(StateError('disconnected'));
      }
      await tester.pumpAndSettle();
      expect(find.byType(ContextUsageRing), findsOneWidget);
      expect(
        tester.widget<ContextUsageRing>(find.byType(ContextUsageRing)).progress,
        0.25,
      );
      expect(find.text('1.0 USD'), findsOneWidget);
      expect(find.text('≈ 60 词元/秒'), findsOneWidget);
    });
  }

  testWidgets('thread switching borrows owners and never inherits usage', (
    tester,
  ) async {
    final first = await AcpComponentHarness.create(
      updates: [_usage(25, 100, amount: 1)],
    );
    addTearDown(() => first.close(tester));
    final second = await first.openSecondConversation();
    final thread = ValueNotifier('thread');
    addTearDown(thread.dispose);
    await tester.pumpWidget(
      first.scope(
        ValueListenableBuilder<String>(
          valueListenable: thread,
          builder: (context, id, _) => AcpStatusBarConnector(threadId: id),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('1.0 USD'), findsOneWidget);
    expect(
      tester.widget<ContextUsageRing>(find.byType(ContextUsageRing)).progress,
      0.25,
    );
    thread.value = 'second';
    await tester.pumpAndSettle();
    expect(
      tester.widget<ContextUsageRing>(find.byType(ContextUsageRing)).progress,
      isNull,
    );
    expect(find.textContaining('USD'), findsNothing);
    second.source.read!.complete(
      AcpEventFrameView(
        AcpUpdateEventView(
          AcpSessionNotificationView(
            sessionId: const AcpRemoteSessionId('remote-second'),
            update: _usage(80, 100, amount: 3),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('3.0 USD'), findsOneWidget);
    expect(
      tester.widget<ContextUsageRing>(find.byType(ContextUsageRing)).progress,
      0.8,
    );
    thread.value = 'thread';
    await tester.pumpAndSettle();
    expect(find.text('1.0 USD'), findsOneWidget);
    expect(
      tester.widget<ContextUsageRing>(find.byType(ContextUsageRing)).progress,
      0.25,
    );
    expect(first.source.closeSignals, 0);
    expect(second.source.closeSignals, 0);
    expect(first.source.closes, 0);
    expect(second.source.closes, 0);
    expect(
      first.client.acpSessions.conversationForThread('thread'),
      first.owner,
    );
    expect(
      first.client.acpSessions.conversationForThread('second'),
      second.owner,
    );
    final opens = first.port.calls
        .where((call) => call.$1 == 'open')
        .map((call) => (call.$2 as OpenAcpSessionRequestView).threadId);
    expect(opens, ['thread', 'second']);
  });

  testWidgets('narrow status bar scrolls horizontally without overflow', (
    tester,
  ) async {
    await tester.pumpWidget(
      acpTestApp(
        Center(
          child: SizedBox(
            width: 150,
            child: AcpStatusBarView(
              status: const AcpConnectionStatusView(
                state: AcpStatusBarViewState(
                  phase: AcpSessionStatusPhase.completed,
                  stopReason: AcpStopReasonKind.maxTokens,
                  provenance: AcpHistoryOriginKind.loadReplay,
                ),
              ),
              contextUsage: AcpContextUsageView(
                state: (used: BigInt.one, size: BigInt.two, isLive: true),
              ),
              cost: const AcpCostReadoutView(
                state: (amount: 12, currency: 'USD'),
              ),
              externalHistory: AcpExternalHistoryButtonView(
                threadId: 'thread',
                state: const AcpExternalHistoryButtonState(
                  status: AcpExternalHistoryAvailability.available,
                ),
                onOpen: () {},
              ),
            ),
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    final scroll = tester.state<ScrollableState>(find.byType(Scrollable));
    expect(scroll.position.maxScrollExtent, greaterThan(0));
    await tester.drag(
      find.byType(SingleChildScrollView),
      const Offset(-600, 0),
    );
    await tester.pumpAndSettle();
    expect(
      find
          .byKey(ValueKey(AcpViewKeyValues.externalHistoryButton('thread')))
          .hitTestable(),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'hovering ACP context ring mounts rich detail popover and switches badge on disconnect',
    (tester) async {
      final h = await AcpComponentHarness.create();
      addTearDown(() => h.close(tester));
      await tester.pumpWidget(
        h.scope(const AcpStatusBarConnector(threadId: 'thread')),
      );
      await tester.pumpAndSettle();
      expect(find.byType(AcpContextDetailView), findsNothing);

      h.emit(
        const AcpInitializedEventView(
          AcpAgentCapabilitiesView(
            image: true,
            audio: false,
            embeddedContext: true,
            loadSession: true,
            listSessions: true,
            resumeSession: true,
          ),
          serverInfo: AcpServerInfoView(
            name: 'codex-acp',
            version: '0.9.4',
            title: 'Codex CLI',
          ),
        ),
      );
      h.update(
        AcpConfigOptionsUpdateView(
          configOptions: [
            AcpSessionConfigOptionView(
              id: const AcpConfigId('model'),
              name: '模型',
              kind: AcpSelectConfigView(
                currentValue: const AcpConfigValueId('gpt-5'),
                options: AcpUngroupedOptionsView(const [
                  AcpSelectOptionView(
                    value: AcpConfigValueId('gpt-5'),
                    name: 'GPT-5',
                  ),
                ]),
              ),
            ),
            acpBooleanFixture,
          ],
        ),
      );
      h.update(_usage(50000, 200000, amount: 0.2));
      h.update(_usage(64500, 200000, amount: 0.42));
      final run = AcpRunIdView(instance: BigInt.one, sequence: BigInt.one);
      h.port.run = run;
      await h.owner.send(const [AcpTextContentView(text: 'hi')]);
      h.emit(
        AcpCompletedEventView(
          AcpCompletedRunView(
            run: run,
            completionSequence: BigInt.one,
            result: const AcpSuccessView(
              AcpPromptResponseView(stopReason: AcpStopReasonView.endTurn),
            ),
            summary: 'ok',
            truncated: false,
            textPerformance: (estimatedOutputTokens: 320, responseMillis: 4000),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(AcpContextDetailView), findsNothing);

      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      addTearDown(mouse.removePointer);
      await mouse.addPointer(location: Offset.zero);
      await mouse.moveTo(
        tester.getCenter(
          find.byKey(ValueKey(AcpViewKeyValues.contextUsage('thread'))),
        ),
      );
      await tester.pump(const Duration(milliseconds: 160));
      await tester.pumpAndSettle();

      expect(
        find.byKey(ValueKey(AcpViewKeyValues.contextUsageDetail('thread'))),
        findsOneWidget,
      );
      expect(find.text('实时'), findsOneWidget);
      expect(find.text('64.5k / 200k'), findsOneWidget);
      expect(find.text('32%'), findsOneWidget);
      expect(find.text('+14.5k'), findsOneWidget);
      expect(find.text('精确 64,500 / 200,000 词元'), findsOneWidget);
      expect(find.text('剩余可用 135.5k'), findsOneWidget);
      expect(find.text('80 词元/秒'), findsOneWidget);
      expect(find.text('≈ 320 词元 · 4.0s'), findsOneWidget);
      expect(find.text(r'$0.42'), findsOneWidget);
      expect(find.text('1 轮'), findsOneWidget);
      expect(find.text('Codex CLI'), findsOneWidget);
      expect(find.text('v0.9.4'), findsOneWidget);
      expect(find.text('GPT-5'), findsOneWidget);
      expect(find.text('关闭'), findsOneWidget);
      expect(find.text('图片输入'), findsOneWidget);
      expect(find.text('加载历史'), findsOneWidget);
      expect(find.text('恢复会话'), findsOneWidget);
      expect(find.text(acpRemoteFixture.value), findsOneWidget);

      h.emit(const AcpGapEventView(AcpObservationGapView.disconnected));
      await tester.pumpAndSettle();
      expect(find.text('上次快照'), findsOneWidget);
      expect(find.text('64.5k / 200k'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'AcpContextDetailView handles narrow width, 1.3x scale, over-capacity, and negative delta cleanly',
    (tester) async {
      await tester.pumpWidget(
        acpTestApp(
          MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(1.3)),
            child: Center(
              child: SizedBox(
                width: 280,
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: AcpContextDetailView(
                    state: AcpContextDetailViewState(
                      used: BigInt.from(215000),
                      size: BigInt.from(200000),
                      previousUsed: BigInt.from(220000),
                      isLive: false,
                      tokensPerSecond: 62.5,
                      estimatedOutputTokens: 250,
                      responseMillis: 4000,
                      serviceName: 'Workstation Enterprise ACP Proxy Long Name',
                      serverName: 'claude-agent-acp',
                      serverVersion: 'v2.4.1',
                      remoteSessionId: 'session_01JXYZLONGIDENTIFIER99887766',
                      phase: AcpSessionStatusPhase.disconnected,
                      lastStopReason: AcpStopReasonKind.maxTokens,
                      completedTurns: 6,
                      updatedAt: DateTime.utc(2026, 11, 23, 8, 15, 30),
                      configItems: const [
                        AcpConfigReadoutItem(
                          label: '',
                          value: 'Plan Mode',
                          useModeFallbackLabel: true,
                        ),
                      ],
                      capabilities: const [
                        AcpCapabilityKind.image,
                        AcpCapabilityKind.loadSession,
                        AcpCapabilityKind.resumeSession,
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('上次快照'), findsOneWidget);
      expect(find.text('-5k'), findsOneWidget);
      expect(find.text('超出容量 15k'), findsOneWidget);
      expect(find.text('6 轮'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
