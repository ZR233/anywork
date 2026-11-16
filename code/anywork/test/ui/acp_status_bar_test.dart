import 'package:anywork/src/features/conversation/acp/acp_views.dart';
import 'package:anywork/src/features/conversation/acp/connectors/acp_status_bar_connector.dart';
import 'package:anywork/src/features/conversation/acp/view_models/acp_external_history_view_model.dart';
import 'package:anywork/src/features/conversation/acp/view_models/acp_status_bar_view_model.dart';
import 'package:anywork/src/shared/studio_context_usage_ring.dart';
import 'package:anywork_client/acp_sessions.dart';
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
  testWidgets('unknown, real zero, ratio, zero capacity and missing cost', (
    tester,
  ) async {
    final h = await AcpComponentHarness.create();
    addTearDown(() => h.close(tester));
    final semantics = tester.ensureSemantics();
    try {
      await tester.pumpWidget(
        h.scope(const AcpStatusBarConnector(threadId: 'thread')),
      );
      await tester.pumpAndSettle();
      expect(find.byType(ContextUsageRing), findsNothing);
      expect(find.textContaining('USD'), findsNothing);

      h.update(_usage(0, 100, amount: 0));
      await tester.pumpAndSettle();
      expect(
        tester.widget<ContextUsageRing>(find.byType(ContextUsageRing)).progress,
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
        tester.widget<ContextUsageRing>(find.byType(ContextUsageRing)).progress,
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

      h.update(_usage(25, 100));
      await tester.pumpAndSettle();
      expect(find.textContaining('USD'), findsNothing);
      expect(find.byType(ContextUsageRing), findsOneWidget);

      h.update(_usage(25, 0, amount: 2));
      await tester.pumpAndSettle();
      expect(find.byType(ContextUsageRing), findsNothing);
      expect(find.bySemanticsLabel('上下文'), findsNothing);
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
        tester.widget<ContextUsageRing>(find.byType(ContextUsageRing)).progress,
        1,
      );
      expect(tester.takeException(), isNull);
    } finally {
      semantics.dispose();
    }
  });

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
    final changes = [0, 0, 0, 0];
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
    expectChanges([0, 0, 0, 0]);
    h.update(_usage(25, 100, amount: 2));
    await tester.pumpAndSettle();
    expectChanges([0, 0, 1, 0]);
    h.update(_usage(50, 100, amount: 2));
    await tester.pumpAndSettle();
    expectChanges([0, 1, 0, 0]);
    h.update(_usage(50, 100));
    await tester.pumpAndSettle();
    expectChanges([0, 0, 1, 0]);
    h.update(_usage(50, 100, amount: 2));
    await tester.pumpAndSettle();
    expectChanges([0, 0, 1, 0]);
    h.update(_usage(50, 0, amount: 2));
    await tester.pumpAndSettle();
    expectChanges([0, 1, 0, 0]);
    h.update(_usage(50, 100, amount: 2));
    await tester.pumpAndSettle();
    expectChanges([0, 1, 0, 0]);
    h.emit(const AcpInitializedEventView(_capabilities));
    await tester.pumpAndSettle();
    expectChanges([0, 0, 0, 1]);

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
    expectChanges([0, 0, 0, 0]);

    final run = AcpRunIdView(instance: BigInt.one, sequence: BigInt.one);
    h.port.run = run;
    await h.owner.send(const [AcpTextContentView(text: 'question')]);
    await tester.pumpAndSettle();
    expectChanges([1, 0, 0, 0]);
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
    expectChanges([1, 0, 0, 0]);
    expect(
      tester
          .widget<AcpConnectionStatusView>(find.byType(AcpConnectionStatusView))
          .state
          .stopReason,
      AcpStopReasonKind.maxTokens,
    );
    h.emit(const AcpGapEventView(AcpObservationGapView.windowExceeded));
    await tester.pumpAndSettle();
    expectChanges([1, 1, 1, 1]);
    expect(find.byType(ContextUsageRing), findsNothing);
    expect(find.textContaining('USD'), findsNothing);
    expect(h.port.calls.where((call) => call.$1 == 'open'), hasLength(1));
  });

  for (final end in ['eof', 'failure']) {
    testWidgets('$end hides unreliable usage', (tester) async {
      final h = await AcpComponentHarness.create(
        updates: [_usage(25, 100, amount: 1)],
      );
      addTearDown(() => h.close(tester));
      await tester.pumpWidget(
        h.scope(const AcpStatusBarConnector(threadId: 'thread')),
      );
      await tester.pumpAndSettle();
      expect(find.byType(ContextUsageRing), findsOneWidget);
      if (end == 'eof') {
        h.source.read!.complete(null);
      } else {
        h.source.read!.completeError(StateError('disconnected'));
      }
      await tester.pumpAndSettle();
      expect(find.byType(ContextUsageRing), findsNothing);
      expect(find.textContaining('USD'), findsNothing);
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
    expect(find.byType(ContextUsageRing), findsNothing);
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
                state: (used: BigInt.one, size: BigInt.two),
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
}
