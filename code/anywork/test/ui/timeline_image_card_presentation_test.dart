import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:anywork/src/app/theme/material3_theme.dart';
import 'package:anywork/src/features/conversation/timeline/connectors/timeline_media_connector.dart';
import 'package:anywork/src/features/conversation/timeline/state/chat_item_presentation.dart';
import 'package:anywork/src/features/conversation/timeline/state/timeline_image_resources.dart';
import 'package:anywork/src/features/conversation/timeline/widgets/chat_item_view.dart';
import 'package:anywork/src/features/conversation/timeline/widgets/timeline_attachments_view.dart';
import 'package:anywork/src/features/conversation/timeline/widgets/timeline_image_view.dart';
import 'package:anywork/src/l10n/app_localizations.dart';
import 'package:anywork/src/shared/studio_driver_keys.dart';
import 'package:anywork_client/models.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
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
      var mediaGeneration = 0;
      final reply = Completer<Uint8List>();
      final items = [imageItem('first')];
      Widget build() => imageApp(
        Column(
          children: [
            for (final item in items)
              ChatItemView(
                key: ValueKey(item.id),
                item: item,
                attachmentBuilder: (value) => TimelineAttachmentsConnector(
                  key: ValueKey((mediaGeneration, value.id)),
                  item: value,
                  resources: resources,
                  readAttachment: (id) {
                    expect(id, 'shared-image');
                    reads++;
                    return reply.future;
                  },
                  isActive: () => true,
                ),
              ),
          ],
        ),
      );
      await tester.pumpWidget(build());
      expect(reads, 0);
      await tester.tap(
        find.byKey(const ValueKey('timeline-tool-details:first')),
      );
      await tester.pump(const Duration(milliseconds: 300));
      final originalResource = resources.borrow('shared-image');
      final originalState = tester.state(find.byType(TimelineImageConnector));
      items[0] = imageItem('first');
      await tester.pumpWidget(build());
      expect(
        tester.state(find.byType(TimelineImageConnector)),
        same(originalState),
      );
      expect(resources.borrow('shared-image'), same(originalResource));
      expect(reads, 1);
      // A replacement row mounts before Flutter disposes its old subtree.
      // The retiring mount must not release the replacement's shared read.
      mediaGeneration++;
      await tester.pumpWidget(build());
      expect(resources.borrow('shared-image'), same(originalResource));
      expect(reads, 1);
      items.add(imageItem('second'));
      await tester.pumpWidget(build());
      await tester.tap(
        find.byKey(const ValueKey('timeline-tool-details:second')),
      );
      await tester.pump(const Duration(milliseconds: 300));
      reply.complete(_png);
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
        await tester.tap(
          find.byKey(const ValueKey(('item-disclosure', 'unknown'))),
        );
        await tester.pump(const Duration(milliseconds: 300));
        await pumpClientUntil(
          tester,
          () => find.byType(Image).evaluate().isNotEmpty,
          'unknown-tool attachment',
        );
        expect(find.textContaining('未知展示格式'), findsOneWidget);
        expect(
          find.text(
            marker == null
                ? '未提供 presentationContract'
                : '不支持的 presentationContract：$marker',
          ),
          findsOneWidget,
        );
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
    '390 / 160% image errors expose every glyph and retry tail while thumbnails retain bounded Wrap cells',
    (tester) async {
      tester.view.physicalSize = const Size(390, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final scroll = ScrollController();
      addTearDown(scroll.dispose);
      const shortMarker = '短错尾标-END';
      const longMarker = '长错尾标-END';
      const shortError = '合成读取失败：$shortMarker';
      final longError = '长错误开始：${'读取结果仍不可用，需要完整保留原始诊断。' * 24}$longMarker';
      final errors = {'short-error': shortError, 'long-error': longError};
      final attachments = [
        for (final id in ['image-0', 'image-1', 'image-2', ...errors.keys])
          ThreadAttachmentView(
            id: id,
            modality: AttachmentModalityView.image,
            mediaType: 'image/png',
            byteSize: _png.length,
            filename: '$id.png',
          ),
      ];
      var retries = 0;
      const scrollKey = ValueKey('image-error-layout-scroll');
      Widget scene({
        bool loaded = true,
        bool active = true,
        bool retryAvailable = true,
      }) => MaterialApp(
        theme: pureStudioTheme(locale: const Locale('zh')),
        locale: const Locale('zh'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: const TextScaler.linear(1.6)),
          child: child!,
        ),
        home: Scaffold(
          body: SingleChildScrollView(
            key: scrollKey,
            controller: scroll,
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: TimelineAttachmentsView(
                attachments: attachments,
                imageBuilder: (attachment) => TimelineImageView(
                  key: ValueKey('layout:${attachment.id}'),
                  itemId: 'layout-tool',
                  attachment: attachment,
                  isTool: true,
                  active: active,
                  imageIdentity: ('layout-tool', attachment.id),
                  bytes: loaded && !errors.containsKey(attachment.id)
                      ? _png
                      : null,
                  width: 1,
                  height: 1,
                  error: errors[attachment.id],
                  onRetry: retryAvailable ? () => retries++ : null,
                ),
              ),
            ),
          ),
        ),
      );
      String displayId(String id) =>
          StudioDriverKeys.toolImageEntryId('layout-tool', id);
      Finder thumbnail(String id) =>
          find.byKey(StudioDriverKeys.viewImageThumbnail(displayId(id)));
      Finder retry(String id) =>
          find.byKey(StudioDriverKeys.timelineImageRetry(displayId(id)));

      List<Rect> expectErrorGeometry(String id, String reason, String marker) {
        final text = '图片读取失败：$reason，重试';
        final paragraph = tester.renderObject<RenderParagraph>(
          find.descendant(
            of: retry(id),
            matching: find.byWidgetPredicate(
              (widget) =>
                  widget is RichText && widget.text.toPlainText() == text,
            ),
          ),
        );
        expect(paragraph.didExceedMaxLines, isFalse);
        final buttonBounds = tester.getRect(retry(id));
        final attachmentBounds = tester.getRect(
          find.byType(TimelineAttachmentsView),
        );
        final glyphs = paragraph.getBoxesForSelection(
          TextSelection(baseOffset: 0, extentOffset: text.length),
        );
        expect(glyphs, isNotEmpty);
        for (final glyph in glyphs) {
          final local = glyph.toRect();
          expect(local.left, greaterThanOrEqualTo(-1));
          expect(local.top, greaterThanOrEqualTo(-1));
          expect(local.right, lessThanOrEqualTo(paragraph.size.width + 1));
          expect(local.bottom, lessThanOrEqualTo(paragraph.size.height + 1));
          final global = local.shift(paragraph.localToGlobal(Offset.zero));
          expect(buttonBounds.inflate(1).contains(global.topLeft), isTrue);
          expect(buttonBounds.inflate(1).contains(global.bottomRight), isTrue);
          expect(attachmentBounds.inflate(1).contains(global.topLeft), isTrue);
          expect(
            attachmentBounds.inflate(1).contains(global.bottomRight),
            isTrue,
          );
        }
        // Semantic presence is not enough: both the diagnostic tail and the
        // final retry glyphs must have actual, unclipped text layout boxes.
        final tail = paragraph.getBoxesForSelection(
          TextSelection(
            baseOffset: text.indexOf(marker),
            extentOffset: text.length,
          ),
        );
        final retryGlyphs = paragraph.getBoxesForSelection(
          TextSelection(baseOffset: text.length - 2, extentOffset: text.length),
        );
        expect(tail, isNotEmpty);
        expect(retryGlyphs, isNotEmpty);
        return [
          for (final glyph in tail)
            glyph.toRect().shift(paragraph.localToGlobal(Offset.zero)),
        ];
      }

      await tester.pumpWidget(scene(loaded: false));
      for (var index = 0; index < 3; index++) {
        expect(
          tester.getSize(find.byKey(ValueKey('layout:image-$index'))),
          const Size(120, 120),
        );
      }
      await tester.pumpWidget(scene());
      await tester.pumpAndSettle();
      for (var index = 0; index < 3; index++) {
        expect(tester.getSize(thumbnail('image-$index')), const Size(120, 120));
      }
      final first = tester.getRect(thumbnail('image-0'));
      final second = tester.getRect(thumbnail('image-1'));
      final third = tester.getRect(thumbnail('image-2'));
      expect(second.top, closeTo(first.top, 0.1));
      expect(second.left, greaterThanOrEqualTo(first.right + 8));
      expect(third.left, closeTo(first.left, 0.1));
      expect(third.top, greaterThanOrEqualTo(first.bottom + 8));
      expect(tester.takeException(), isNull);
      await tester.tap(thumbnail('image-0'));
      await tester.pumpAndSettle();
      expect(
        find.byKey(StudioDriverKeys.viewImageDialog(displayId('image-0'))),
        findsOneWidget,
      );
      await tester.tap(find.byKey(StudioDriverKeys.timelineImageClose));
      await tester.pumpAndSettle();
      final viewport = tester.getRect(find.byKey(scrollKey));
      final shortTail = expectErrorGeometry(
        'short-error',
        shortError,
        shortMarker,
      );
      for (final glyph in shortTail) {
        expect(viewport.inflate(1).contains(glyph.topLeft), isTrue);
        expect(viewport.inflate(1).contains(glyph.bottomRight), isTrue);
      }
      final longTail = expectErrorGeometry('long-error', longError, longMarker);
      expect(longTail.last.bottom, greaterThan(viewport.bottom));
      expect(tester.getSize(retry('long-error')).height, greaterThan(120));
      expect(retries, 0, reason: 'Layout and image errors do not retry reads');
      await tester.tap(retry('short-error'));
      await tester.pump();
      expect(retries, 1);
      expect(scroll.position.maxScrollExtent, greaterThan(0));
      scroll.jumpTo(scroll.position.maxScrollExtent);
      await tester.pumpAndSettle();
      final visibleTail = expectErrorGeometry(
        'long-error',
        longError,
        longMarker,
      );
      for (final glyph in visibleTail) {
        expect(viewport.inflate(1).contains(glyph.topLeft), isTrue);
        expect(viewport.inflate(1).contains(glyph.bottomRight), isTrue);
      }
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(scene(active: false));
      for (final id in errors.keys) {
        expect(tester.widget<TextButton>(retry(id)).onPressed, isNull);
      }
      expect(
        tester.widget<GestureDetector>(thumbnail('image-0')).onTap,
        isNull,
      );
      await tester.pumpWidget(scene(retryAvailable: false));
      for (final id in errors.keys) {
        expect(tester.widget<TextButton>(retry(id)).onPressed, isNull);
      }
      expect(retries, 1);
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
