import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:anywork/src/app/app_graph.dart';
import 'package:anywork/src/app/theme/material3_theme.dart';
import 'package:anywork/src/features/conversation/timeline/connectors/file_reading_panel.dart';
import 'package:anywork/src/features/conversation/timeline/connectors/timeline_connector.dart';
import 'package:anywork/src/features/conversation/timeline/widgets/timeline_markdown.dart';
import 'package:anywork/src/features/shell/studio_shell.dart';
import 'package:anywork/src/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/chat_fixtures.dart';
import '../support/pump_client_future.dart';
import '../support/recording_demo_transport.dart';
import '../support/test_statistics_feed.dart';

void main() {
  testWidgets(
    'file reading keeps the timeline mounted across split/full/narrow and outlives its source row',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final graph = AppGraph(
        statisticsFeed: const TestStatisticsFeedPort(),
        transport: RecordingDemoTransport(),
        clientId: 'file-reading-workspace',
      );
      await pumpClientFuture(tester, graph.client.bootstrap(), 'bootstrap');
      await pumpClientFuture(
        tester,
        (graph
              ..timeline.updateReadDemand(chatDemand)
              ..setConversationPageVisible(true))
            .client
            .directoryCommands
            .selectThread('thread-main'),
        'select thread',
      );
      await pumpClientUntil(
        tester,
        () =>
            graph.client.conversations
                .existingSession('thread-main')
                ?.state
                .hasSnapshot ==
            true,
        'snapshot',
      );
      var width = 1100.0;
      late StateSetter resize;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [appGraphProvider.overrideWithValue(graph)],
          child: MaterialApp(
            theme: pureStudioTheme(),
            locale: const Locale('zh'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: StatefulBuilder(
              builder: (context, setState) {
                resize = setState;
                return Scaffold(
                  body: SizedBox(
                    width: width,
                    height: 720,
                    child: const AgentWorkspacePane(threadId: 'thread-main'),
                  ),
                );
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final timeline = tester.element(find.byType(TimelineConnector));
      final bytes = Completer<Uint8List>();
      var rowActive = true;
      FileReadingScope.maybeOf(timeline)!.onOpen(
        FileReadingRequest(
          identity: ('thread-main', 'file-call', 'notes'),
          filename: 'notes.md',
          readBytes: () => bytes.future,
          isActive: () => rowActive,
        ),
      );
      await tester.pump();
      final panel = tester.state(find.byType(FileReadingPanel));
      final splitWidth = tester.getSize(find.byType(FileReadingPanel)).width;
      expect(splitWidth, lessThan(width));
      await tester.tap(find.byTooltip('展开阅读'));
      await tester.pump();
      expect(
        tester.getSize(find.byType(FileReadingPanel)).width,
        closeTo(width, 1),
      );
      expect(tester.state(find.byType(FileReadingPanel)), same(panel));
      expect(tester.element(find.byType(TimelineConnector)), same(timeline));
      await tester.tap(find.byTooltip('恢复分栏'));
      await tester.pump();
      expect(
        tester.getSize(find.byType(FileReadingPanel)).width,
        closeTo(splitWidth, 1),
      );
      resize(() => width = 600);
      await tester.pump();
      expect(
        tester.getSize(find.byType(FileReadingPanel)).width,
        closeTo(600, 1),
      );
      expect(tester.element(find.byType(TimelineConnector)), same(timeline));
      expect(tester.state(find.byType(FileReadingPanel)), same(panel));
      rowActive = false;
      bytes.complete(
        Uint8List.fromList(utf8.encode('# Read after row unmount')),
      );
      await tester.pump();
      await tester.pump();
      final document = find.descendant(
        of: find.byType(FileReadingPanel),
        matching: find.byType(TimelineMarkdown),
      );
      expect(
        tester.widget<TimelineMarkdown>(document).text,
        '# Read after row unmount',
      );
      final close = find.descendant(
        of: find.byType(FileReadingPanel),
        matching: find.byIcon(Icons.close),
      );
      await tester.tap(close);
      await tester.pump();
      expect(find.byType(FileReadingPanel), findsNothing);
      expect(tester.element(find.byType(TimelineConnector)), same(timeline));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await pumpClientFuture(
        tester,
        graph.close(deadline: DateTime.now().add(const Duration(seconds: 5))),
        'graph close',
      );
    },
  );
}
