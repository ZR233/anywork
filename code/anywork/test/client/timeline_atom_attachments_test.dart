import 'dart:typed_data';

import 'package:anywork/src/features/conversation/timeline/connectors/timeline_media_connector.dart';
import 'package:anywork/src/features/conversation/timeline/state/timeline_entry.dart';
import 'package:anywork/src/features/conversation/timeline/state/timeline_image_resources.dart';
import 'package:anywork/src/features/conversation/timeline/widgets/timeline_entry_view.dart';
import 'package:anywork/src/l10n/app_localizations.dart';
import 'package:anywork_client/models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

ConversationItem _tool(String name, List<ThreadAttachmentView> attachments) =>
    ConversationItem(
      header: const ConversationItemHeader(
        id: 'tool',
        threadId: 'thread',
        turnId: 'turn',
        appendSeq: 1,
      ),
      descriptor: ConversationToolDescriptor(
        invocation: ConversationToolInvocation(toolCallId: 'call', name: name),
        state: ConversationToolSucceeded(
          completedAt: DateTime.utc(2026),
          output: ConversationToolOutputDescriptor(attachments: attachments),
        ),
      ),
      source: const ConversationContentSource(),
      fields: const [],
    );

Widget _app(Widget child) => MaterialApp(
  locale: const Locale('zh'),
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: Scaffold(
    body: SingleChildScrollView(
      child: Center(child: SizedBox(width: 220, child: child)),
    ),
  ),
);

void main() {
  testWidgets('file and video metadata wrap without reading attachment bytes', (
    tester,
  ) async {
    final filename = '${'a_very_long_filename_' * 8}.txt';
    final item = _tool('exec', [
      ThreadAttachmentView(
        id: 'file',
        modality: AttachmentModalityView.file,
        mediaType: 'text/plain',
        byteSize: 123,
        filename: filename,
      ),
      const ThreadAttachmentView(
        id: 'video',
        modality: AttachmentModalityView.video,
        mediaType: 'video/mp4',
        byteSize: 456,
      ),
    ]);
    final resources = TimelineImageResources(threadId: 'thread');
    addTearDown(resources.release);
    var reads = 0;
    await tester.pumpWidget(
      _app(
        TimelineGroupMediaConnector(
          item: item,
          resources: resources,
          readAttachment: (_) async {
            reads++;
            return Uint8List(0);
          },
          isActive: () => true,
          onDetail: (_, _) {},
        ),
      ),
    );
    expect(find.text(filename), findsOneWidget);
    expect(find.text('文件 · text/plain · 123 B'), findsOneWidget);
    expect(find.text('视频'), findsOneWidget);
    expect(find.text('视频 · video/mp4 · 456 B'), findsOneWidget);
    for (final tile in tester.widgetList<ListTile>(find.byType(ListTile))) {
      expect(tile.onTap, isNull);
    }
    for (final card in find.byType(Card).evaluate()) {
      expect(
        tester.getSize(find.byWidget(card.widget)).width,
        lessThanOrEqualTo(220),
      );
    }
    expect(reads, 0);
    expect(tester.takeException(), isNull);
  });

  for (final name in ['exec', 'show_image']) {
    testWidgets(
      '$name keeps file media inside the original atom exactly once',
      (tester) async {
        final item = _tool(name, const [
          ThreadAttachmentView(
            id: 'file',
            modality: AttachmentModalityView.file,
            mediaType: 'text/plain',
            byteSize: 12,
            filename: 'report.txt',
          ),
        ]);
        final entry = TimelineEntry(
          id: 'entry',
          kind: TimelineEntryKind.activity,
          anchorItemId: item.id,
        )..appendMembers([item]);
        entry.toggle();
        addTearDown(entry.dispose);
        final resources = TimelineImageResources(threadId: 'thread');
        addTearDown(resources.release);
        var reads = 0;
        final mediaItems = <ConversationItem>[];
        await tester.pumpWidget(
          _app(
            TimelineEntryView(
              entry: entry,
              bodyBuilder: (_, text) => Text(text),
              onDetail: (_, _) {},
              mediaBuilder: (value) {
                mediaItems.add(value);
                return TimelineGroupMediaConnector(
                  item: value,
                  resources: resources,
                  readAttachment: (_) async {
                    reads++;
                    return Uint8List(0);
                  },
                  isActive: () => true,
                  onDetail: (_, _) {},
                );
              },
            ),
          ),
        );
        expect(find.text('report.txt'), findsOneWidget);
        expect(find.byType(TimelineGroupMediaConnector), findsOneWidget);
        expect(mediaItems, isNotEmpty);
        expect(mediaItems.every((value) => identical(value, item)), isTrue);
        expect(entry.length, 1);
        expect(reads, 0);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
