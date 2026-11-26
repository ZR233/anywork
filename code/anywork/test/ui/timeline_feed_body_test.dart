import 'dart:async';

import 'package:anywork/src/app/theme/material3_theme.dart';
import 'package:anywork/src/features/conversation/timeline/connectors/timeline_feed_body_connector.dart';
import 'package:anywork/src/l10n/app_localizations.dart';
import 'package:anywork/src/shared/studio_driver_keys.dart';
import 'package:anywork_client/studio_client.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../support/chat_fixtures.dart';
import '../support/pump_client_future.dart';
import '../support/recording_demo_transport.dart';
import '../support/test_app_lifecycle.dart';
import '../support/test_statistics_feed.dart';

const _reference = BodyRef(
  databaseId: 'database',
  bodyId: 'body',
  ownerEventId: 'event',
  bodyKey: 'body',
  role: 'body',
  byteLength: 7,
);

void main() {
  testWidgets(
    'body opens on demand, retries the same range and advances by bytes',
    (tester) async {
      final transport = RecordingDemoTransport();
      final graph = testAppGraph(
        transport: transport,
        clientId: 'timeline-body-feed',
        statisticsFeed: const TestStatisticsFeedPort(),
      );
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        final report = await pumpClientFuture(
          tester,
          graph.close(budget: testCloseBudget()),
          'close body Feed',
        );
        expect(report.complete, isTrue);
      });
      await pumpClientFuture(tester, graph.client.bootstrap(), 'bootstrap');
      graph.timeline.updateReadDemand(chatDemand);
      graph.setConversationPageVisible(true);
      await pumpClientFuture(
        tester,
        graph.client.directoryCommands.selectThread('thread-main'),
        'open thread',
      );
      await pumpClientFuture(
        tester,
        timelineReady(graph.timeline, 'thread-main'),
        'initial reset',
      );
      final feed = transport.feedFor('thread-main');
      var requests = 0;
      feed.onReadBody = (_, offset, _) async {
        requests++;
        if (requests == 1) {
          throw StateError('body temporarily unavailable');
        }
        if (requests == 2) {
          return const BodyWindow(
            offset: 0,
            text: '你',
            totalBytes: 7,
            eof: true,
          );
        }
        return offset == 0
            ? const BodyWindow(offset: 0, text: '你', totalBytes: 7, eof: false)
            : const BodyWindow(
                offset: 3,
                text: 'tail',
                totalBytes: 7,
                eof: true,
              );
      };
      final lease = graph.timeline.lease('thread-main')!;
      await tester.pumpWidget(
        MaterialApp(
          theme: pureStudioTheme(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: TimelineFeedContent(
              identity: lease,
              isActive: () => lease.canRead,
              readBodyWindow: lease.readBodyWindow,
              child: TimelineFeedBodyConnector(
                itemId: 'row',
                reference: _reference,
                label: 'Deferred body',
                witness: (_, child) => child,
              ),
            ),
          ),
        ),
      );
      expect(feed.bodyRequests, isEmpty);
      await tester.tap(
        find.byKey(StudioDriverKeys.timelineContentOpen('row', 'body')),
      );
      await tester.pumpAndSettle();
      expect(feed.bodyRequests.single.reference, _reference);
      expect(feed.bodyRequests.single.offset, 0);
      expect(
        find.textContaining('body temporarily unavailable'),
        findsOneWidget,
      );
      final disclosure = find.text('Deferred body');
      await tester.tap(disclosure);
      await tester.pumpAndSettle();
      await tester.tap(disclosure);
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Body window does not match its fixed reference'),
        findsOneWidget,
      );
      expect(find.text('你'), findsNothing);
      await tester.tap(disclosure);
      await tester.pumpAndSettle();
      await tester.tap(disclosure);
      await tester.pumpAndSettle();
      expect(find.text('你'), findsOneWidget);
      String? copied;
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String;
        }
        return null;
      });
      addTearDown(
        () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
      );
      await tester.tap(
        find.byKey(StudioDriverKeys.timelineContentCopyWindow('row', 'body')),
      );
      await tester.pump();
      expect(copied, '你');

      final next = find.byKey(
        StudioDriverKeys.timelineContentNextWindow('row', 'body'),
      );
      await tester.tap(next);
      await tester.pumpAndSettle();
      expect(find.text('tail'), findsOneWidget);
      expect(next, findsNothing);
      expect(feed.bodyRequests, [
        (reference: _reference, offset: 0, maxBytes: 64 * 1024),
        (reference: _reference, offset: 0, maxBytes: 64 * 1024),
        (reference: _reference, offset: 0, maxBytes: 64 * 1024),
        (reference: _reference, offset: 3, maxBytes: 64 * 1024),
      ]);

      final late = Completer<BodyWindow>();
      feed.onReadBody = (_, _, _) => late.future;
      final pending = lease.readBodyWindow(
        _reference,
        offset: 0,
        maxBytes: 64 * 1024,
      );
      final rejected = expectLater(
        pending,
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            contains('retired'),
          ),
        ),
      );
      await pumpClientFuture(
        tester,
        graph.client.directoryCommands.selectThread('thread-alt'),
        'retire original Feed',
      );
      expect(lease.isRetired, isTrue);
      late.complete(
        const BodyWindow(offset: 0, text: 'retired', totalBytes: 7, eof: true),
      );
      await pumpClientFuture(tester, rejected, 'retired read rejected');
      expect(find.text('retired'), findsNothing);
    },
  );
}
