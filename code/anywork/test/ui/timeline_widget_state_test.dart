import 'dart:convert';
import 'dart:typed_data';

import 'package:anywork/src/app/theme/material3_theme.dart';
import 'package:anywork/src/features/conversation/timeline/state/tool_presentation.dart';
import 'package:anywork/src/features/conversation/timeline/widgets/timeline_image_view.dart';
import 'package:anywork/src/features/conversation/timeline/widgets/timeline_activity_row.dart';
import 'package:anywork/src/features/conversation/timeline/widgets/timeline_reasoning_view.dart';
import 'package:anywork/src/features/conversation/timeline/widgets/timeline_tool_blocks.dart';
import 'package:anywork/src/l10n/app_localizations.dart';
import 'package:anywork/src/shared/studio_driver_keys.dart';
import 'package:anywork_client/models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../integration_test/support/timeline_observation.dart';

final _png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aL1sAAAAASUVORK5CYII=',
);

final _attachment = ThreadAttachmentView(
  id: 'image',
  modality: AttachmentModalityView.image,
  mediaType: 'image/png',
  byteSize: _png.length,
  filename: 'image.png',
  width: 1,
  height: 1,
);

Widget _host(Widget child) => MaterialApp(
  theme: pureStudioTheme(),
  locale: const Locale('zh'),
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: Scaffold(body: child),
);

TimelineToolPresentation _tool(String id, {required bool webSearch}) =>
    TimelineToolPresentation(
      id: id,
      toolCallId: 'call-$id',
      name: webSearch ? 'web_search' : 'exec',
      presentationContract: webSearch
          ? 'builtin.web_search@1'
          : 'builtin.exec@2',
      statusString: 'succeeded',
      arguments: webSearch
          ? '{"search_query":[{"q":"query-$id"}]}'
          : '{"command":"command-$id"}',
      output: 'output-$id',
    );

void main() {
  testWidgets('group-title finder follows a clock-rebuilt reasoning summary', (
    tester,
  ) async {
    var taps = 0;
    var headerCandidates = 0;
    final header = find.byElementPredicate((element) {
      headerCandidates++;
      return element.widget is TimelineActivityRow;
    });
    await tester.pumpWidget(
      _host(
        InkWell(
          onTap: () => taps++,
          child: const TimelineReasoningView(
            summary: 'stable reasoning summary',
            startedAt: 0,
            running: true,
          ),
        ),
      ),
    );
    final title = timelineGroupTitleFinder(tester, header);
    headerCandidates = 0;
    expect(title.evaluate(), hasLength(1));
    expect(
      headerCandidates,
      lessThanOrEqualTo(tester.allElements.length * 2),
      reason: 'one title evaluation must not resolve the header per candidate',
    );
    expect(title, findsOneWidget);
    final before = tester.widget<TimelineActivityRow>(header).labelWidget;
    expect(before, isA<TimelineReasoningSummary>());
    expect(title.hitTestable(), findsOneWidget);

    await tester.pump(const Duration(seconds: 1));
    final after = tester.widget<TimelineActivityRow>(header).labelWidget;
    expect(after, isA<TimelineReasoningSummary>());
    expect(after, isNot(same(before)));
    expect(title, findsOneWidget);
    expect(title.hitTestable(), findsOneWidget);
    await tester.tap(title);
    await tester.pump();
    expect(taps, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'image view owns one mutable byte copy per source identity and shares its provider with the dialog',
    (tester) async {
      final sourceA = Uint8List.fromList(_png).asUnmodifiableView();
      final sourceB = Uint8List.fromList(_png).asUnmodifiableView();

      Widget image(Uint8List bytes, Object identity, {bool active = true}) =>
          _host(
            TimelineImageView(
              itemId: 'item',
              attachment: _attachment,
              isTool: false,
              active: active,
              imageIdentity: identity,
              bytes: bytes,
              width: 1,
              height: 1,
            ),
          );

      MemoryImage thumbnailProvider() {
        final thumbnail = find.byKey(
          StudioDriverKeys.viewImageThumbnail('image'),
        );
        final image = tester.widget<Image>(
          find.descendant(of: thumbnail, matching: find.byType(Image)),
        );
        return (image.image as ResizeImage).imageProvider as MemoryImage;
      }

      await tester.pumpWidget(image(sourceA, 'A'));
      await tester.pumpAndSettle();
      final first = thumbnailProvider();
      expect(first.bytes, isNot(same(sourceA)));
      expect(first.bytes, orderedEquals(sourceA));

      await tester.pumpWidget(image(sourceA, 'A', active: false));
      await tester.pump();
      expect(thumbnailProvider(), same(first));

      await tester.pumpWidget(image(sourceA, 'B'));
      await tester.pump();
      final changedIdentity = thumbnailProvider();
      expect(changedIdentity, isNot(same(first)));
      expect(changedIdentity.bytes, isNot(same(sourceA)));

      await tester.pumpWidget(image(sourceB, 'B'));
      await tester.pump();
      final changedBytes = thumbnailProvider();
      expect(changedBytes, isNot(same(changedIdentity)));
      expect(changedBytes.bytes, isNot(same(sourceB)));
      expect(changedBytes.bytes, orderedEquals(sourceB));

      await tester.tap(
        find.byKey(StudioDriverKeys.viewImageThumbnail('image')),
      );
      await tester.pumpAndSettle();
      final dialog = find.byKey(StudioDriverKeys.timelineImageDialog('image'));
      final original = tester.widget<Image>(
        find.descendant(of: dialog, matching: find.byType(Image)),
      );
      expect(original.image, same(changedBytes));
      expect(tester.takeException(), isNull);
    },
  );

  for (final webSearch in [false, true]) {
    testWidgets(
      '${webSearch ? 'web search' : 'tool details'} retires official expansion state when item identity changes',
      (tester) async {
        final changes = <bool>[];
        Widget tool(String id, {required bool initiallyExpanded}) {
          final item = _tool(id, webSearch: webSearch);
          final Widget child = webSearch
              ? TimelineWebSearchToolCard(
                  item: item,
                  initiallyExpanded: initiallyExpanded,
                  onExpansionChanged: changes.add,
                )
              : TimelineToolDetails(
                  item: item,
                  initiallyExpanded: initiallyExpanded,
                  onExpansionChanged: changes.add,
                );
          return _host(
            KeyedSubtree(key: const ValueKey('reuse'), child: child),
          );
        }

        ExpansibleController controller() {
          final tile = find.byType(ExpansionTile);
          final title = find.byWidget(tester.widget<ExpansionTile>(tile).title);
          return ExpansibleController.of(tester.element(title));
        }

        await tester.pumpWidget(tool('A', initiallyExpanded: false));
        expect(controller().isExpanded, isFalse);
        expect(
          tester
              .widget<TimelineActivityRow>(find.byType(TimelineActivityRow))
              .expandable,
          isTrue,
        );
        expect(find.byIcon(Icons.chevron_right_rounded), findsOneWidget);
        expect(find.byIcon(Icons.keyboard_arrow_down_rounded), findsNothing);
        expect(find.byIcon(Icons.expand_more), findsNothing);
        await tester.tap(
          find.byWidget(
            tester.widget<ExpansionTile>(find.byType(ExpansionTile)).title,
          ),
        );
        await tester.pumpAndSettle();
        expect(controller().isExpanded, isTrue);
        expect(find.textContaining('output-A'), findsWidgets);
        expect(changes, [true]);

        await tester.pumpWidget(tool('B', initiallyExpanded: false));
        await tester.pumpAndSettle();
        expect(controller().isExpanded, isFalse);
        expect(find.textContaining('output-A'), findsNothing);
        expect(find.textContaining('output-B'), findsNothing);
        expect(changes, [true]);

        await tester.pumpWidget(tool('C', initiallyExpanded: true));
        await tester.pumpAndSettle();
        expect(controller().isExpanded, isTrue);
        expect(find.textContaining('output-C'), findsWidgets);
        expect(changes, [true]);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('tool without real details has no arrow or expansion action', (
    tester,
  ) async {
    final changes = <bool>[];
    final item = TimelineToolPresentation(
      id: 'empty',
      toolCallId: 'call-empty',
      name: 'exec',
      presentationContract: 'builtin.exec@2',
      statusString: 'succeeded',
      arguments: '',
      output: '',
    );
    await tester.pumpWidget(
      _host(TimelineToolDetails(item: item, onExpansionChanged: changes.add)),
    );
    final tile = find.byType(ExpansionTile);
    final expansion = tester.widget<ExpansionTile>(tile);
    final title = find.byWidget(expansion.title);
    final controller = ExpansibleController.of(tester.element(title));
    expect(expansion.enabled, isFalse);
    expect(expansion.showTrailingIcon, isFalse);
    expect(
      tester
          .widget<TimelineActivityRow>(find.byType(TimelineActivityRow))
          .expandable,
      isFalse,
    );
    expect(find.byIcon(Icons.expand_more), findsNothing);
    expect(find.byIcon(Icons.chevron_right_rounded), findsNothing);
    expect(controller.isExpanded, isFalse);
    expect(changes, isEmpty);
  });
}
