import 'dart:async';

import 'package:anywork/src/app/app_graph.dart';
import 'package:anywork/src/app/theme/material3_theme.dart';
import 'package:anywork/src/features/conversation/timeline/connectors/timeline_connector.dart';
import 'package:anywork/src/features/conversation/timeline/live_status/live_status_bar.dart';
import 'package:anywork/src/features/conversation/timeline/widgets/completion_run_view.dart';
import 'package:anywork/src/l10n/app_localizations.dart';
import 'package:anywork_client/studio_client.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../support/conversation_feed_fixtures.dart';
import '../support/pump_client_future.dart';
import '../support/recording_demo_transport.dart';
import '../support/test_app_lifecycle.dart';
import '../support/test_statistics_feed.dart';

const _threadId = 'thread-main';

void main() {
  testWidgets(
    'live work and streaming text leave sealed timeline rows intact',
    (tester) async {
      final transport = RecordingDemoTransport()
        ..onFeedOpened = (feed) {
          feed.mapReset = (reset) => TimelineReset(
            items: [feedUser('msg:1', 1, 'First prompt', inputId: 'input-1')],
            hasMoreOlder: false,
            revision: reset.revision,
          );
        };
      final graph = testAppGraph(
        transport: transport,
        statisticsFeed: const TestStatisticsFeedPort(),
        clientId: 'timeline-live-feed',
      );
      await tester.binding.setSurfaceSize(const Size(850, 850));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        final report = await pumpClientFuture(
          tester,
          graph.close(budget: testCloseBudget()),
          'close live status fixture',
        );
        expect(report.complete, isTrue);
      });
      await pumpClientFuture(tester, graph.client.bootstrap(), 'bootstrap');
      await tester.pumpWidget(
        ProviderScope(
          overrides: [appGraphProvider.overrideWithValue(graph)],
          child: MaterialApp(
            theme: pureStudioTheme(),
            locale: const Locale('en'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: const Scaffold(
              body: Column(
                children: [
                  Expanded(child: TimelineConnector(threadId: _threadId)),
                  LiveStatusBar(threadId: _threadId),
                ],
              ),
            ),
          ),
        ),
      );
      graph.setConversationPageVisible(true);
      await pumpClientFuture(
        tester,
        graph.client.directoryCommands.selectThread(_threadId),
        'open conversation',
      );
      await pumpClientFuture(
        tester,
        timelineReady(graph.timeline, _threadId),
        'initial reset',
      );
      final lease = graph.timeline.lease(_threadId)!;
      final feed = transport.feedFor(_threadId);
      final input = lease.controller.messages.single;
      var revision = 10;
      void status(LiveStatusPhase phase, {bool suppressed = false}) =>
          feed.emit(
            ConversationLiveStatus(
              snapshot: LiveStatusSnapshot(
                revision: revision++,
                phase: phase,
                attentions: const [],
                suppressedByInteraction: suppressed,
              ),
            ),
          );
      Finder liveText(String text) => find.descendant(
        of: find.byType(LiveStatusBar),
        matching: find.text(text, findRichText: true),
      );

      status(
        LiveStatusWorking(
          items: const [
            LiveWorkItem(
              id: 'work:2',
              callId: 'call-2',
              kind: 'tool',
              toolName: 'read_file',
              status: 'running',
              summary: 'Reading a.txt',
            ),
          ],
        ),
      );
      final liveWork = find.byKey(
        const ValueKey('completion-run-header:live-work:thread-main'),
      );
      await pumpClientUntil(
        tester,
        () => liveWork.evaluate().isNotEmpty,
        'working status',
      );
      expect(liveText('Reading a.txt'), findsNothing);
      await tester.tap(liveWork);
      await pumpClientUntil(
        tester,
        () => liveText('Reading a.txt').evaluate().isNotEmpty,
        'working status',
      );
      expect(lease.controller.messages.single, same(input));
      expect(feed.memberRequests, isEmpty);

      const streaming = LiveStatusStreamingText(
        attemptId: 'attempt-1',
        itemId: 'stream-1',
        text: 'Streaming draft',
      );
      status(streaming);
      await pumpClientUntil(
        tester,
        () => liveText('Streaming draft').evaluate().isNotEmpty,
        'streaming status',
      );
      expect(
        find.descendant(
          of: find.byType(TimelineConnector),
          matching: find.text('Streaming draft'),
        ),
        findsNothing,
      );
      expect(lease.controller.messages.single, same(input));
      expect(feed.bodyRequests, isEmpty);

      status(streaming, suppressed: true);
      await pumpClientUntil(
        tester,
        () => liveText('Streaming draft').evaluate().isEmpty,
        'interaction suppresses the live surface',
      );
      expect(lease.controller.messages.single, same(input));

      final member = Completer<List<WorkGroupMember>>();
      addTearDown(() {
        if (!member.isCompleted) member.complete(const []);
      });
      feed.onLoadMembers = (_, _) => member.future;
      feed.emit(
        ConversationTimeline(
          patch: TimelineAppend(
            items: [
              const TimelineWorkGroup(
                id: 'work:2',
                firstSeq: 2,
                lastSeq: 3,
                afterBoundarySeq: 1,
                beforeBoundarySeq: 4,
                memberCount: 1,
                summary: 'Completed work',
                status: WorkGroupStatus.completed,
              ),
              feedAssistant(
                'msg:4',
                4,
                'Final answer from turn 1',
                turnId: 'turn-1',
              ),
            ],
          ),
        ),
      );
      status(const LiveStatusIdle());
      await pumpClientUntil(
        tester,
        () => find.byType(CompletionRunView).evaluate().isNotEmpty,
        'sealed work rendered',
      );
      expect(lease.controller.messages.map((row) => row.id), [
        'msg:1',
        'work:2',
        'msg:4',
      ]);
      expect(lease.controller.messages.first, same(input));
      expect(lease.appliedSets, 1);
      expect(feed.memberRequests, isEmpty);

      final disclosure = find.byKey(
        const ValueKey('completion-run-header:work:2'),
      );
      await tester.tap(disclosure);
      await pumpClientUntil(
        tester,
        () => feed.memberRequests.isNotEmpty,
        'work group disclosed',
      );
      expect(feed.memberRequests, [(afterSeq: 1, beforeSeq: 4)]);
      await tester.tap(disclosure);
      await tester.pump();
      member.complete(const [
        WorkGroupReasoning(
          id: 'stale',
          seq: 2,
          text: 'Retired body',
          summary: 'Retired summary',
          outcome: 'completed',
        ),
      ]);
      await tester.pumpAndSettle();
      expect(find.text('Retired summary', findRichText: true), findsNothing);

      feed.onLoadMembers = (_, _) async => const [
        WorkGroupReasoning(
          id: 'reasoning-2',
          seq: 2,
          text: 'Sealed body',
          summary: 'Sealed reasoning',
          outcome: 'completed',
        ),
      ];
      await tester.tap(disclosure);
      await pumpClientUntil(
        tester,
        () => find
            .text('Sealed reasoning', findRichText: true)
            .evaluate()
            .isNotEmpty,
        'fresh work member visible',
      );
      expect(feed.memberRequests, [
        (afterSeq: 1, beforeSeq: 4),
        (afterSeq: 1, beforeSeq: 4),
      ]);
      expect(
        find.text('Final answer from turn 1', findRichText: true),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );
}
