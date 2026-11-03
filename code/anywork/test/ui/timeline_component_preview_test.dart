import 'dart:ui' as ui;

import 'package:anywork/src/features/conversation/timeline/previews/timeline_component_previews.dart';
import 'package:anywork/src/features/conversation/timeline/previews/timeline_preview_fixtures.dart';
import 'package:anywork/src/shared/studio_driver_keys.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'public component previews mount production widgets without a runtime',
    (tester) async {
      for (final preview in [
        timelineMarkdownPreview,
        timelinePlainTextPreview,
        timelineActivityRowPreview,
        timelineToolDetailsPreview,
        timelineWebSearchPreview,
        timelineWaitPanelPreview,
        timelineWaitDetailsPreview,
        timelineChildrenPreview,
      ]) {
        await tester.pumpWidget(preview());
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      }
    },
  );

  testWidgets('content preview uses production ExpansionTile state', (
    tester,
  ) async {
    await tester.pumpWidget(timelineContentWindowPreview());
    await tester.pumpAndSettle();
    final disclosure = find.byKey(
      StudioDriverKeys.timelineContentOpen('preview-deferred', 'payload'),
    );
    expect(disclosure, findsOneWidget);
    final tile = find.descendant(
      of: disclosure,
      matching: find.byType(ExpansionTile),
    );
    expect(tile, findsOneWidget);

    ExpansibleController controller() {
      final title = find.byWidget(tester.widget<ExpansionTile>(tile).title);
      expect(title, findsOneWidget);
      return ExpansibleController.of(tester.element(title));
    }

    expect(controller().isExpanded, isTrue);
    expect(find.text('复制当前段'), findsOneWidget);
    await tester.tap(find.text('按需查看原文 · 196608 字节'));
    await tester.pumpAndSettle();
    expect(controller().isExpanded, isFalse);
    expect(find.text('复制当前段'), findsNothing);
    await tester.tap(find.text('按需查看原文 · 196608 字节'));
    await tester.pumpAndSettle();
    expect(controller().isExpanded, isTrue);
    expect(find.text('复制当前段'), findsOneWidget);
  });

  testWidgets(
    'synthetic PNG preview decodes at its declared size and opens production dialog',
    (tester) async {
      // Engine image decoding is real asynchronous work, outside fake time.
      await tester.runAsync(() async {
        final codec = await ui.instantiateImageCodec(
          TimelinePreviewFixtures.imageBytes,
        );
        try {
          final frame = await codec.getNextFrame();
          try {
            expect(
              (frame.image.width, frame.image.height),
              (
                TimelinePreviewFixtures.imageWidth,
                TimelinePreviewFixtures.imageHeight,
              ),
            );
          } finally {
            frame.image.dispose();
          }
        } finally {
          codec.dispose();
        }
      });
      await tester.pumpWidget(timelineImagePreview());
      await tester.pumpAndSettle();
      final thumbnail = find.byKey(
        StudioDriverKeys.viewImageThumbnail('preview-image'),
      );
      expect(tester.getSize(thumbnail).width, greaterThan(100));
      expect(tester.getSize(thumbnail).height, greaterThan(100));
      await tester.tap(thumbnail);
      await tester.pumpAndSettle();
      expect(
        find.byKey(StudioDriverKeys.timelineImageDialog('preview-image')),
        findsOneWidget,
      );
      expect(find.text('synthetic-landscape-320x180.png'), findsOneWidget);
      await tester.tap(find.byKey(StudioDriverKeys.timelineImageClose));
      await tester.pumpAndSettle();
      expect(find.byType(Dialog), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
