import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:anywork/src/app/app_graph.dart';
import 'package:anywork/src/app/theme/material3_theme.dart';
import 'package:anywork/src/features/conversation/timeline/connectors/file_reading_panel.dart';
import 'package:anywork/src/features/conversation/timeline/connectors/timeline_connector.dart';
import 'package:anywork/src/features/conversation/timeline/connectors/timeline_media_connector.dart';
import 'package:anywork/src/features/conversation/timeline/widgets/timeline_markdown.dart';
import 'package:anywork/src/features/shell/studio_shell.dart';
import 'package:anywork/src/l10n/app_localizations.dart';
import 'package:anywork_client/conversation.dart';
import 'package:anywork_client/studio_client.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/chat_fixtures.dart';
import '../support/display_fixtures.dart';
import '../support/pump_client_future.dart';
import '../support/recording_demo_transport.dart';
import '../support/test_statistics_feed.dart';

class _AttachmentTransport extends RecordingDemoTransport {
  final reads = <(String, String)>[];
  final bytes = Completer<Uint8List>();

  @override
  Future<Uint8List> readThreadAttachment(String threadId, String attachmentId) {
    reads.add((threadId, attachmentId));
    return bytes.future;
  }
}

ChatAtom _markdownFile() => chatEnvelope(
  'files-call',
  type: 'tool',
  data: {
    'invocation': {
      'toolCallId': 'files-call',
      'name': 'show_files',
      'presentationContract': 'builtin.show_files@1',
    },
    'state': {
      'kind': 'succeeded',
      'output': {'attachments': <Object?>[]},
    },
  },
  bodies: [
    inlineBody('tool.arguments', '{"files":[]}'),
    inlineBody(
      'tool.output-artifacts',
      jsonEncode([
        {
          'kind': 'opaque',
          'payload': {
            'format': 'pl.tool.files',
            'version': 1,
            'content': jsonEncode({
              'files': [
                {
                  'status': 'ready',
                  'filename': 'notes.md',
                  'modality': 'file',
                  'resource': {
                    'id': 'notes',
                    'contentDigest': 'sha256:${'0' * 64}',
                    'byteLen': 8,
                    'mediaType': 'text/markdown',
                  },
                  'origin': {'kind': 'archive'},
                },
              ],
            }),
          },
        },
      ]),
    ),
  ],
);

void main() {
  for (final revokeDuringRead in [false, true]) {
    testWidgets(
      revokeDuringRead
          ? 'switching Thread revokes a pending production attachment read'
          : 'file reading keeps the timeline mounted across split/full/narrow and outlives its source row',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(1200, 900));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final transport = _AttachmentTransport();
        final graph = AppGraph(
          statisticsFeed: const TestStatisticsFeedPort(),
          transport: transport,
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
        var threadId = 'thread-main';
        late StateSetter resize;
        await tester.pumpWidget(
          ProviderScope(
            overrides: [appGraphProvider.overrideWithValue(graph)],
            child: MaterialApp(
              theme: pureStudioTheme(),
              locale: const Locale('zh'),
              localizationsDelegates: [
                AppLocalizations.delegate,
                ...GlobalMaterialLocalizations.delegates,
              ],
              supportedLocales: AppLocalizations.supportedLocales,
              home: StatefulBuilder(
                builder: (context, setState) {
                  resize = setState;
                  return Scaffold(
                    body: SizedBox(
                      width: width,
                      height: 720,
                      child: AgentWorkspacePane(threadId: threadId),
                    ),
                  );
                },
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final feed = transport.timelineFeeds.last;
        final filePosition =
            graph.timeline.lease('thread-main')!.live.value!.historyThrough + 1;
        feed.emitTimeline(
          displayBatch(
            [
              displaySingle(
                statusItem(_markdownFile(), completionSeq: 5),
                historyPos: filePosition,
              ),
            ],
            placement: ChatPlacement.append,
            from: filePosition - 1,
          ),
        );
        await pumpClientUntil(
          tester,
          () => find.text('notes.md').evaluate().isNotEmpty,
          'production file card',
        );
        final timeline = tester.element(find.byType(TimelineConnector));
        final sourceFinder = find.ancestor(
          of: find.text('notes.md'),
          matching: find.byType(TimelineAttachmentsConnector),
        );
        expect(sourceFinder, findsOneWidget);
        final source = tester.state(sourceFinder);
        final read = tester
            .widget<TimelineAttachmentsConnector>(sourceFinder)
            .readAttachment!;
        await tester.tap(find.text('notes.md'));
        await tester.pump();
        await tester.pump();
        expect(find.textContaining('ancestor'), findsNothing);
        expect(transport.reads, [('thread-main', 'notes')]);
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
        // New completions move the original file row outside the virtual window.
        resize(() => width = 1100);
        await tester.pump();
        feed.emitTimeline(
          displayBatch(
            [
              displaySingle(
                chatMessage(
                  'after-file',
                  completionSeq: 6,
                  body: List.generate(
                    100,
                    (index) => 'Later paragraph $index',
                  ).join('\n\n'),
                ),
                historyPos: filePosition + 1,
              ),
            ],
            placement: ChatPlacement.append,
            from: filePosition,
          ),
        );
        await pumpClientUntil(
          tester,
          () => !source.mounted,
          'source row virtualized',
        );
        Future<void>? revokedRead;
        if (revokeDuringRead) {
          // This is the original production callback, retained after its source
          // row has unmounted. It still admits reads under the same live lease.
          revokedRead = expectLater(
            read('notes'),
            throwsA(isA<StaleConversationScope>()),
          );
          await pumpClientUntil(
            tester,
            () => transport.reads.length == 2,
            'second read admitted under original lease',
          );
          await pumpClientFuture(
            tester,
            graph.client.directoryCommands.selectThread('thread-alt'),
            'switch during read',
          );
          resize(() => threadId = 'thread-alt');
          await tester.pump();
          expect(find.byType(FileReadingPanel), findsNothing);
        }
        transport.bytes.complete(
          Uint8List.fromList(utf8.encode('# Read after row unmount')),
        );
        await tester.pump();
        await tester.pump();
        if (revokedRead != null) {
          await pumpClientFuture(tester, revokedRead, 'late bytes rejected');
          expect(find.byType(FileReadingPanel), findsNothing);
          expect(find.textContaining('Read after row unmount'), findsNothing);
        } else {
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
          expect(
            tester.element(find.byType(TimelineConnector)),
            same(timeline),
          );
        }
        expect(tester.takeException(), isNull);
        // Retiring the real Thread lease revokes the retained production reader.
        await pumpClientFuture(
          tester,
          graph.client.directoryCommands.selectThread('thread-alt'),
          'switch thread',
        );
        await pumpClientFuture(
          tester,
          expectLater(read('notes'), throwsA(isA<StaleConversationScope>())),
          'retired attachment read',
        );
        expect(
          transport.reads,
          List.filled(revokeDuringRead ? 2 : 1, ('thread-main', 'notes')),
        );
        await tester.pumpWidget(const SizedBox());
        await pumpClientFuture(
          tester,
          graph.close(deadline: DateTime.now().add(const Duration(seconds: 5))),
          'graph close',
        );
      },
    );
  }
}
