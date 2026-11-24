import '../support/test_app_lifecycle.dart';

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
import 'package:anywork/src/shared/studio_driver_keys.dart';
import 'package:anywork_client/conversation.dart';
import 'package:anywork_client/studio_client.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../anywork_client/test/support/timeline_transport.dart'
    show TestHistoryReader;
import '../support/chat_fixtures.dart';
import '../support/pump_client_future.dart';
import '../support/recording_demo_transport.dart';
import '../support/test_statistics_feed.dart';

class _AttachmentTransport extends RecordingDemoTransport {
  final reads = <(String, String)>[];
  final bytes = Completer<Uint8List>();
  final changed = Completer<HistoryCut>();

  @override
  Future<Uint8List> readThreadAttachment(String threadId, String attachmentId) {
    reads.add((threadId, attachmentId));
    return bytes.future;
  }

  @override
  Future<HistoryReader> openHistoryReader(
    String threadId, {
    required int historyProtocolVersion,
  }) async {
    final reader = _FileHistoryReader(
      threadId: threadId,
      cut: HistoryCut('file-cut:$threadId'),
    );
    reader.onTimeline = (_, _, _) async => HistoryTimelinePage(
      cut: reader.cut,
      items: [
        DividerTimelineItem(
          HistoryEventRecord(
            seq: 5,
            eventId: 'files-call',
            kind: 'tool_completed',
            timelineRole: HistoryTimelineRole.divider,
            recordedAt: 5,
            entityId: 'files-call',
            callId: 'files-call',
            toolName: 'show_files',
            rowKey: 'files-call',
            source: const ReceiptChatSource(receiptId: 'files-call'),
            payloadSchema: 'anywork.event/1',
            payloadJson: jsonEncode({
              'contract': 'anywork.event/1',
              'type': 'tool',
              'meta': {
                'entityId': 'files-call',
                'entityKind': 'receipt',
                'delivery': 'independent',
                'state': {'kind': 'knownTerminal', 'outcome': 'completed'},
                'presentationContract': 'builtin.show_files@1',
                'contentPresent': true,
              },
              'data': {
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
              'bodies': [
                {
                  'key': 'tool.arguments',
                  'role': 'toolArguments',
                  'byteLength': 12,
                  'inlineText': '{"files":[]}',
                },
                {
                  'key': 'tool.output-artifacts',
                  'role': 'attachment',
                  'byteLength': _FileHistoryReader._artifactsJson.length,
                  'inlineText': _FileHistoryReader._artifactsJson,
                },
              ],
            }),
          ),
        ),
      ],
    );
    reader.onWaitChanged = (_) => changed.future;
    return reader;
  }
}

final class _FileHistoryReader extends TestHistoryReader {
  _FileHistoryReader({required super.threadId, required super.cut});

  static final String _artifactsJson = jsonEncode([
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
  ]);

  @override
  Future<HistoryEventRecord> readEvent({
    required String eventId,
    required HistoryDemand demand,
  }) async => (await onTimeline!(
    cut,
    null,
    demand,
  )).items.whereType<DividerTimelineItem>().single.event;
}

void main() {
  for (final revokeDuringRead in [false, true]) {
    testWidgets(
      revokeDuringRead
          ? 'switching Thread revokes a pending production attachment read'
          : 'file reading keeps the timeline mounted across split/full/narrow',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(1200, 900));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final transport = _AttachmentTransport();
        final graph = testAppGraph(
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
              graph.client.conversations.visibleThreadId.value ==
                  'thread-main' &&
              graph.client.conversations
                      .existingSession('thread-main')
                      ?.state
                      .hasSnapshot ==
                  true,
          'visible snapshot',
        );
        await pumpClientFuture(
          tester,
          timelineReady(graph.timeline, 'thread-main'),
          'timeline ready',
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
        await pumpClientUntil(
          tester,
          () => find.text('notes.md').evaluate().isNotEmpty,
          'production file card',
        );
        final timelineFinder = find.byType(
          TimelineConnector,
          skipOffstage: false,
        );
        final timeline = tester.element(timelineFinder);
        final sourceFinder = find.ancestor(
          of: find.text('notes.md'),
          matching: find.byType(TimelineAttachmentsConnector),
        );
        expect(sourceFinder, findsOneWidget);
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
        expect(find.byType(TimelineConnector), findsNothing);
        expect(tester.element(timelineFinder), same(timeline));
        await tester.tap(find.byTooltip('恢复并排'));
        await tester.pump();
        expect(
          tester.getSize(find.byType(FileReadingPanel)).width,
          closeTo(splitWidth, 1),
        );
        resize(() => width = 600);
        await tester.pump();
        expect(
          find.byKey(StudioDriverKeys.rightSidebarOverlayScrim),
          findsOneWidget,
        );
        expect(
          tester.getSize(find.byType(FileReadingPanel)).width,
          closeTo(440, 1),
        );
        expect(tester.element(timelineFinder), same(timeline));
        expect(tester.state(find.byType(FileReadingPanel)), same(panel));
        Future<void>? revokedRead;
        if (revokeDuringRead) {
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
          await tester.tap(find.byKey(StudioDriverKeys.rightSidebarFileClose));
          await tester.pump();
          expect(find.byType(FileReadingPanel), findsNothing);
          expect(tester.element(timelineFinder), same(timeline));
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
          graph.close(budget: ClientCloseBudget(const Duration(seconds: 5))),
          'graph close',
        );
      },
    );
  }
}
