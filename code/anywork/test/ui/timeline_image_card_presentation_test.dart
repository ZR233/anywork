import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:anywork/src/features/conversation/timeline/connectors/timeline_media_connector.dart';
import 'package:anywork/src/features/conversation/timeline/state/chat_item_presentation.dart';
import 'package:anywork/src/features/conversation/timeline/state/timeline_image_resources.dart';
import 'package:anywork/src/features/conversation/timeline/widgets/chat_item_view.dart';
import 'package:anywork/src/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/chat_fixtures.dart';
import '../support/pump_client_future.dart';

final _png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aL1sAAAAASUVORK5CYII=',
);
ChatItemPresentation imageItem(
  String id, {
  String? marker = 'generic@1',
  bool attachment = true,
}) => ChatItemPresentation.decode(
  chatEnvelope(
    id,
    type: 'tool',
    data: {
      'invocation': {
        'toolCallId': id,
        'name': 'show_image',
        'presentationContract': ?marker,
      },
      'state': {
        'kind': 'succeeded',
        'output': {
          'attachments': [
            if (attachment)
              {
                'id': 'shared-image',
                'modality': 'image',
                'mediaType': 'image/png',
                'byteSize': _png.length,
                'filename': 'terrace.png',
              },
          ],
        },
      },
    },
    bodies: [inlineBody('tool.arguments', '{"caption":"not a guessed card"}')],
  ),
);

Widget imageApp(Widget child) => MaterialApp(
  locale: const Locale('zh'),
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: Scaffold(body: SingleChildScrollView(child: child)),
);

void main() {
  testWidgets(
    'two producer image messages keep distinct rows while sharing one authorized byte read',
    (tester) async {
      final resources = TimelineImageResources(threadId: 'thread');
      addTearDown(resources.release);
      var reads = 0;
      final items = [imageItem('first'), imageItem('second')];
      await tester.pumpWidget(
        imageApp(
          Column(
            children: [
              for (final item in items)
                ChatItemView(
                  key: ValueKey(item.id),
                  item: item,
                  attachmentBuilder: (value) => TimelineAttachmentsConnector(
                    item: value,
                    resources: resources,
                    readAttachment: (id) async {
                      expect(id, 'shared-image');
                      reads++;
                      return _png;
                    },
                    isActive: () => true,
                  ),
                ),
            ],
          ),
        ),
      );
      expect(reads, 0);
      for (final item in items) {
        await tester.tap(find.byKey(ValueKey('timeline-tool-details:${item.id}')));
        await tester.pump(const Duration(milliseconds: 300));
      }
      await pumpClientUntil(
        tester,
        () => find.byType(Image).evaluate().length == 2,
        'two authorized image thumbnails',
      );
      expect(find.byType(ChatItemView), findsNWidgets(2));
      expect(find.byType(TimelineImageConnector), findsNWidgets(2));
      expect(reads, 1);
      expect(
        tester
            .widgetList<TimelineImageConnector>(
              find.byType(TimelineImageConnector),
            )
            .map((widget) => widget.itemId),
        ['first', 'second'],
      );
      expect(
        find.text('not a guessed card'),
        findsNothing,
        reason: 'generic marker never invokes a historical name-based caption parser',
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      expect(() => resources.borrow('shared-image'), throwsStateError);
    },
  );

  for (final marker in <String?>[null, 'unknown-image@7']) {
    testWidgets(
      'unknown marker $marker keeps its explicit attachment without guessing show_image contract',
      (tester) async {
        final resources = TimelineImageResources(threadId: 'thread');
        addTearDown(resources.release);
        var reads = 0;
        await tester.pumpWidget(
          imageApp(
            ChatItemView(
              item: imageItem('unknown', marker: marker),
              attachmentBuilder: (value) => TimelineAttachmentsConnector(
                item: value,
                resources: resources,
                readAttachment: (_) async {
                  reads++;
                  return _png;
                },
                isActive: () => true,
              ),
            ),
          ),
        );
        expect(reads, 0);
        await tester.tap(find.byKey(const ValueKey(('item-disclosure', 'unknown'))));
        await tester.pump(const Duration(milliseconds: 300));
        await pumpClientUntil(
          tester,
          () => find.byType(Image).evaluate().isNotEmpty,
          'unknown-tool attachment',
        );
        expect(find.textContaining('未知展示格式'), findsOneWidget);
        expect(reads, 1);
        expect(find.text('not a guessed card'), findsNothing);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }

  testWidgets(
    'missing image attachment performs no byte read or fabricated thumbnail',
    (tester) async {
      final resources = TimelineImageResources(threadId: 'thread');
      addTearDown(resources.release);
      var reads = 0;
      await tester.pumpWidget(
        imageApp(
          ChatItemView(
            item: imageItem('empty', attachment: false),
            attachmentBuilder: (value) => TimelineAttachmentsConnector(
              item: value,
              resources: resources,
              readAttachment: (_) async {
                reads++;
                return _png;
              },
              isActive: () => true,
            ),
          ),
        ),
      );
      expect(find.byType(TimelineImageConnector), findsNothing);
      expect(reads, 0);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'shared image failure is visible and explicit retry replaces the attempt for every mounted row',
    (tester) async {
      final resources = TimelineImageResources(threadId: 'thread');
      addTearDown(resources.release);
      var reads = 0;
      var fail = true;
      Future<Uint8List> read(String id) async {
        reads++;
        if (fail) throw StateError('authorized read failed');
        return _png;
      }

      await tester.pumpWidget(
        imageApp(
          Column(
            children: [
              for (final item in [imageItem('a'), imageItem('b')])
                TimelineAttachmentsConnector(
                  item: item,
                  resources: resources,
                  readAttachment: read,
                  isActive: () => true,
                ),
            ],
          ),
        ),
      );
      await tester.pump();
      expect(find.textContaining('authorized read failed'), findsNWidgets(2));
      expect(reads, 1);
      fail = false;
      await tester.tap(find.textContaining('authorized read failed').first);
      await pumpClientUntil(
        tester,
        () => find.byType(Image).evaluate().length == 2,
        'shared explicit image retry',
      );
      expect(reads, 2);
      expect(find.textContaining('authorized read failed'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'retirement during an attachment await cannot publish a thumbnail or enable retry',
    (tester) async {
      final resources = TimelineImageResources(threadId: 'thread');
      addTearDown(resources.release);
      var active = true;
      final reply = Completer<Uint8List>();
      final item = imageItem('retiring');
      Widget build() => imageApp(
        TimelineAttachmentsConnector(
          item: item,
          resources: resources,
          readAttachment: (_) => reply.future,
          isActive: () => active,
        ),
      );
      await tester.pumpWidget(build());
      active = false;
      resources.retire();
      reply.complete(_png);
      await tester.pumpWidget(build());
      await tester.pump();
      expect(find.byType(Image), findsNothing);
      final retry = tester.widget<TextButton>(find.byType(TextButton));
      expect(retry.onPressed, isNull);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
