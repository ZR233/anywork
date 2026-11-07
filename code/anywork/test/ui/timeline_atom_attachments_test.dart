import 'dart:typed_data';

import 'package:anywork/src/features/conversation/timeline/connectors/timeline_media_connector.dart';
import 'package:anywork/src/features/conversation/timeline/state/chat_item_presentation.dart';
import 'package:anywork/src/features/conversation/timeline/state/timeline_image_resources.dart';
import 'package:anywork/src/features/conversation/timeline/widgets/chat_item_view.dart';
import 'package:anywork/src/l10n/app_localizations.dart';
import 'package:anywork_client/models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/chat_fixtures.dart';

ChatItemPresentation _tool(
  String name,
  List<ThreadAttachmentView> attachments,
) => ChatItemPresentation.decode(
  chatEnvelope(
    'tool',
    type: 'tool',
    data: {
      'invocation': {
        'toolCallId': 'call',
        'name': name,
        'presentationContract': 'generic@1',
      },
      'state': {
        'kind': 'succeeded',
        'completedAt': 0,
        'output': {
          'attachments': [
            for (final attachment in attachments)
              {
                'id': attachment.id,
                'modality': attachment.modality.name,
                'mediaType': attachment.mediaType,
                'byteSize': attachment.byteSize,
                if (attachment.filename != null)
                  'filename': attachment.filename,
              },
          ],
        },
      },
    },
    bodies: [inlineBody('tool.arguments', '{}')],
  ),
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
        TimelineAttachmentsConnector(
          item: item,
          resources: resources,
          readAttachment: (_) async {
            reads++;
            return Uint8List(0);
          },
          isActive: () => true,
        ),
      ),
    );
    expect(find.text(filename), findsOneWidget);
    expect(find.text('text/plain · 123 B'), findsOneWidget);
    expect(find.text('视频'), findsOneWidget);
    expect(find.text('video/mp4 · 456 B'), findsOneWidget);
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
        final resources = TimelineImageResources(threadId: 'thread');
        addTearDown(resources.release);
        var reads = 0;
        final mediaItems = <ChatItemPresentation>[];
        await tester.pumpWidget(
          _app(
            ChatItemView(
              item: item,
              bodyBuilder: (_, text) => Text(text),
              attachmentBuilder: (value) {
                mediaItems.add(value);
                return TimelineAttachmentsConnector(
                  item: value,
                  resources: resources,
                  readAttachment: (_) async {
                    reads++;
                    return Uint8List(0);
                  },
                  isActive: () => true,
                );
              },
            ),
          ),
        );
        expect(mediaItems, isEmpty);
        expect(reads, 0);
        await tester.tap(
          find.byKey(const ValueKey('timeline-tool-details:tool')),
        );
        await tester.pump(const Duration(milliseconds: 300));
        expect(find.text('report.txt'), findsOneWidget);
        expect(find.byType(TimelineAttachmentsConnector), findsOneWidget);
        expect(mediaItems, isNotEmpty);
        expect(mediaItems.every((value) => identical(value, item)), isTrue);
        expect(reads, 0);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
