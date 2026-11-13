import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:anywork/src/app/theme/material3_theme.dart';
import 'package:anywork/src/domain/models/timeline_commands.dart';
import 'package:anywork/src/features/conversation/timeline/connectors/timeline_content_connector.dart';
import 'package:anywork/src/features/conversation/timeline/connectors/timeline_media_connector.dart';
import 'package:anywork/src/features/conversation/timeline/state/chat_item_presentation.dart';
import 'package:anywork/src/features/conversation/timeline/state/timeline_display_diagnostics.dart';
import 'package:anywork/src/features/conversation/timeline/state/timeline_image_resources.dart';
import 'package:anywork/src/features/conversation/timeline/state/timeline_ui_controllers.dart';
import 'package:anywork/src/features/conversation/timeline/state/timeline_view_state.dart';
import 'package:anywork/src/features/conversation/timeline/view_models/timeline_message_controller.dart';
import 'package:anywork/src/features/conversation/timeline/views/timeline_view.dart';
import 'package:anywork/src/features/conversation/timeline/widgets/chat_item_view.dart';
import 'package:anywork/src/features/conversation/timeline/widgets/timeline_content_range_view.dart';
import 'package:anywork/src/features/conversation/timeline/widgets/timeline_markdown.dart';
import 'package:anywork/src/features/conversation/timeline/widgets/timeline_tool_blocks.dart';
import 'package:anywork/src/l10n/app_localizations.dart';
import 'package:anywork/src/shared/studio_driver_keys.dart';
import 'package:anywork_client/models.dart' as sdk;
import 'package:material_ui/material_ui.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_chat_core/flutter_chat_core.dart';
import 'package:flutter_chat_ui/flutter_chat_ui.dart';
import 'package:flutter_test/flutter_test.dart';

sdk.ChatAtom _fixtureAtom({
  required String id,
  required sdk.PayloadData payload,
}) => sdk.ChatAtom(
  id: id,
  completionItemId: id,
  source: sdk.ReceiptChatSource(receiptId: id),
  sourceOrder: null,
  kind: sdk.ChatAtomKind.receipt,
  delivery: sdk.ChatDeliveryKind.independent,
  lifecycle: const sdk.TerminalChatAtom(
    started: null,
    ended: null,
    outcome: sdk.ChatTerminalOutcome.completed,
  ),
  contents: const [],
  payload: payload,
);

sdk.ChatAtom _text(String id, String text) => _fixtureAtom(
  id: id,
  payload: sdk.InlinePayload(
    bytes: utf8.encode(
      jsonEncode({
        'contract': 'anywork.chat/1',
        'type': 'text',
        'data': {'channel': 'final'},
        'bodies': [
          {
            'key': 'body',
            'byteLength': utf8.encode(text).length,
            'inline': utf8.encode(text),
          },
        ],
      }),
    ),
  ),
);

sdk.ChatAtom _unknown(String id, {String? marker}) => _fixtureAtom(
  id: id,
  payload: sdk.InlinePayload(
    bytes: utf8.encode(
      jsonEncode({
        'contract': 'anywork.chat/1',
        'type': 'tool',
        'data': {
          'invocation': {'name': 'exec', 'presentationContract': marker},
        },
        'bodies': [
          {
            'key': 'tool.arguments',
            'byteLength': 7,
            'inline': utf8.encode('PRIVATE'),
          },
        ],
      }),
    ),
  ),
);

void main() {
  testWidgets(
    'skill record reads canonical activation and rejects the retired flat name',
    (tester) async {
      ChatItemView skill(String id, Map<String, Object?> data) => ChatItemView(
        item: ChatItemPresentation.decode(
          _fixtureAtom(
            id: id,
            payload: sdk.InlinePayload(
              bytes: utf8.encode(
                jsonEncode({
                  'contract': 'anywork.chat/1',
                  'type': 'skill',
                  'data': data,
                  'bodies': const [],
                }),
              ),
            ),
          ),
        ),
      );
      await tester.pumpWidget(
        _rowHost(
          Column(
            children: [
              skill('canonical-skill', {
                'activation': {
                  'name': '规范技能 · 保留原调用',
                  'source': 'project',
                  'providerId': 'builtin',
                  'resourceBase': {
                    'kind': 'directory',
                    'path': '/synthetic/skills/canonical',
                  },
                  'turnId': 'turn-243',
                  'cause': {'kind': 'tool', 'toolCallId': 'call-skill-243'},
                  'activatedAt': 123,
                },
              }),
              skill('bad-skill', {'name': 'retired-flat-name'}),
            ],
          ),
        ),
      );
      expect(find.text('规范技能 · 保留原调用'), findsOneWidget);
      expect(find.text('retired-flat-name'), findsNothing);
      expect(find.text('内容格式错误'), findsOneWidget);
      await tester.tap(find.text('规范技能 · 保留原调用'));
      await tester.pumpAndSettle();
      final publicMetadata = tester
          .widgetList<SelectableText>(find.byType(SelectableText))
          .map((text) => text.data ?? text.textSpan!.toPlainText())
          .join('\n');
      expect(publicMetadata, contains('"activation"'));
      expect(publicMetadata, contains('"toolCallId": "call-skill-243"'));
      expect(find.text('公开原始记录'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  for (final (label, clipped, cached, resizeViewport) in const [
    ('viewport', false, false, false),
    ('clip', true, false, false),
    ('cached clip', true, true, false),
    ('viewport resize', false, false, true),
  ]) {
    testWidgets(
      'content layout witness uses glyph boxes rather than mixed paragraph bounds ($label)',
      (tester) async {
        final samples = <(String, int)>[];
        final scroll = ScrollController();
        final previousClient = debugNetworkImageHttpClientProvider;
        var requests = 0;
        var clock = 444;
        debugNetworkImageHttpClientProvider = () => _ImageHttpClient((_) {
          requests++;
          return Future.error(const HttpException('No image read expected'));
        });
        try {
          final item = ChatItemPresentation.decode(
            _text(
              'mixed-geometry',
              '![](https://example.invalid/viewport.png) **${clipped ? '😀ACTUAL_BODY' : 'ACTUAL_BODY'}**',
            ),
          );
          final row = ChatItemView(
            item: item,
            bodyBuilder: (id, text) => TimelineMarkdown(
              id: id,
              text: text,
              onLink: (_) {},
              isSafeLink: (_) => false,
              imageBuilder: (_, url) => TimelineRemoteImageConnector(url: url),
            ),
            monotonicMicros: () => clock,
            onContentLayout: (id, stamp) => samples.add((id, stamp)),
            isDisplayActive: () => true,
          );
          const clipKey = ValueKey('content-clip');
          late StateSetter resize;
          var clipHeight = 10.0;
          var viewportHeight = 400.0;
          Widget viewport() => ListView(
            controller: scroll,
            children: [
              SizedBox(height: resizeViewport ? 390 : 590),
              row,
              const SizedBox(height: 600),
            ],
          );
          await tester.pumpWidget(
            _rowHost(
              clipped
                  ? StatefulBuilder(
                      builder: (_, setState) {
                        resize = setState;
                        return Align(
                          alignment: Alignment.topLeft,
                          child: ClipRect(
                            key: clipKey,
                            child: SizedBox(
                              height: clipHeight,
                              child: OverflowBox(
                                alignment: Alignment.topLeft,
                                minHeight: 0,
                                maxHeight: double.infinity,
                                child: cached
                                    ? RepaintBoundary(child: row)
                                    : row,
                              ),
                            ),
                          ),
                        );
                      },
                    )
                  : resizeViewport
                  ? StatefulBuilder(
                      builder: (_, setState) {
                        resize = setState;
                        return Align(
                          alignment: Alignment.topLeft,
                          child: SizedBox(
                            height: viewportHeight,
                            child: viewport(),
                          ),
                        );
                      },
                    )
                  : viewport(),
            ),
          );
          await tester.pumpAndSettle();
          final originalState = tester.state(find.byType(ChatItemView));
          final boundary = tester.getRect(
            clipped ? find.byKey(clipKey) : find.byType(ListView),
          );
          final paragraph = tester
              .renderObjectList<RenderParagraph>(find.byType(RichText))
              .singleWhere(
                (render) => render.text.toPlainText().contains('ACTUAL_BODY'),
              );
          final source = paragraph.text.toPlainText(
            includeSemanticsLabels: false,
          );
          final actual = clipped ? '😀ACTUAL_BODY' : 'ACTUAL_BODY';
          final start = source.indexOf(actual);
          List<Rect> glyphs() => paragraph
              .getBoxesForSelection(
                TextSelection(
                  baseOffset: start,
                  extentOffset: start + actual.length,
                ),
              )
              .map(
                (box) =>
                    box.toRect().shift(paragraph.localToGlobal(Offset.zero)),
              )
              .toList();
          expect(glyphs(), isNotEmpty);
          expect(
            glyphs().every((rect) => !rect.overlaps(boundary)),
            isTrue,
            reason:
                'Every actual body glyph must be beyond the visible boundary',
          );
          expect(find.text('加载外部图片 · example.invalid'), findsOneWidget);
          expect(find.byType(Image), findsNothing);
          expect(requests, 0);
          expect(
            samples,
            isEmpty,
            reason:
                'Visible WidgetSpan/paragraph padding is not visible body text',
          );
          clock = 555;
          if (clipped) {
            resize(() => clipHeight = 200);
          } else if (resizeViewport) {
            expect(scroll.offset, 0);
            resize(() => viewportHeight = 500);
          } else {
            scroll.jumpTo(80);
          }
          await tester.pumpAndSettle();
          final revealedBoundary = tester.getRect(
            clipped ? find.byKey(clipKey) : find.byType(ListView),
          );
          expect(
            glyphs().any((rect) => rect.overlaps(revealedBoundary)),
            isTrue,
          );
          expect(tester.state(find.byType(ChatItemView)), same(originalState));
          expect(
            tester.widget<ChatItemView>(find.byType(ChatItemView)).item,
            same(item),
          );
          expect(samples, isNotEmpty);
          expect(
            samples.every((sample) => sample == ('mixed-geometry', 555)),
            isTrue,
          );
          expect(requests, 0);
          if (resizeViewport) expect(scroll.offset, 0);
          expect(find.byType(Image), findsNothing);
          expect(tester.binding.hasScheduledFrame, isFalse);
          await tester.pumpWidget(const SizedBox());
        } finally {
          debugNetworkImageHttpClientProvider = previousClient;
          scroll.dispose();
        }
      },
    );
  }

  testWidgets(
    'content layout witness rejects lazy and failed image-only Markdown',
    (tester) async {
      final controls = _Controls();
      final samples = <(String, int)>[];
      final request = Completer<HttpClientRequest>();
      var requests = 0;
      final previousClient = debugNetworkImageHttpClientProvider;
      debugNetworkImageHttpClientProvider = () => _ImageHttpClient((_) {
        requests++;
        return request.future;
      });
      try {
        await controls.adapter.applyTimeline(
          _mainBatch(
            placement: sdk.ChatPlacement.set,
            entries: ([
              _text(
                'image-only',
                '![](https://example.invalid/only-image.png)',
              ),
            ]).map(_mainEntry).toList(),
          ),
        );
        await tester.pumpWidget(
          _host(
            controls,
            clock: () => 123,
            isActive: () => true,
            onLayout: (id, stamp) => samples.add((id, stamp)),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('加载外部图片 · example.invalid'), findsOneWidget);
        expect(find.byType(Image), findsNothing);
        expect(requests, 0);
        expect(
          samples,
          isEmpty,
          reason: 'A WidgetSpan containing only the image-load control is not body text',
        );
        await tester.tap(find.text('加载外部图片 · example.invalid'));
        await tester.pump();
        expect(
          requests,
          1,
          reason: 'Image IO starts only after the explicit tap',
        );
        expect(
          tester
              .renderObjectList<RenderImage>(find.byType(RawImage))
              .every((render) => render.image == null),
          isTrue,
        );
        expect(samples, isEmpty, reason: 'An undecoded Image is not content');
        request.completeError(const HttpException('image read failed'));
        await tester.pumpAndSettle();
        expect(find.text('外部图片加载失败'), findsOneWidget);
        expect(find.byType(RawImage), findsNothing);
        expect(
          samples,
          isEmpty,
          reason: 'Image error text is not body content',
        );
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        await tester.runAsync(controls.dispose);
      } finally {
        debugNetworkImageHttpClientProvider = previousClient;
      }
    },
  );

  testWidgets(
    'content layout witness accepts actual Markdown text beside a lazy image without IO',
    (tester) async {
      final controls = _Controls();
      final samples = <(String, int)>[];
      var requests = 0;
      final previousClient = debugNetworkImageHttpClientProvider;
      debugNetworkImageHttpClientProvider = () => _ImageHttpClient((_) {
        requests++;
        return Future.error(const HttpException('No image read expected'));
      });
      try {
        await controls.adapter.applyTimeline(
          _mainBatch(
            placement: sdk.ChatPlacement.set,
            entries: ([
              _text(
                'text-and-image',
                '**实际正文** ![](https://example.invalid/lazy.png)',
              ),
            ]).map(_mainEntry).toList(),
          ),
        );
        await tester.pumpWidget(
          _host(
            controls,
            clock: () => 456,
            isActive: () => true,
            onLayout: (id, stamp) => samples.add((id, stamp)),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.textContaining('实际正文', findRichText: true), findsWidgets);
        expect(find.text('加载外部图片 · example.invalid'), findsOneWidget);
        expect(find.byType(Image), findsNothing);
        expect(requests, 0);
        expect(samples, isNotEmpty);
        expect(
          samples.every((sample) => sample == ('text-and-image', 456)),
          isTrue,
        );
        expect(tester.binding.hasScheduledFrame, isFalse);
        await tester.pumpWidget(const SizedBox());
        await tester.runAsync(controls.dispose);
      } finally {
        debugNetworkImageHttpClientProvider = previousClient;
      }
    },
  );

  testWidgets(
    'content layout witness accepts an actual decoded Markdown Image',
    (tester) async {
      final image = MemoryImage(
        base64Decode(
          // Synthetic opaque red 2x2 PNG with valid CRCs.
          'iVBORw0KGgoAAAANSUhEUgAAAAIAAAACCAYAAABytg0kAAAAEUlEQVR4nGP4z8DwH4QZYAwAR8oH+WdZbrcAAAAASUVORK5CYII=',
        ),
      );
      final samples = <(String, int)>[];
      await tester.pumpWidget(_rowHost(const SizedBox()));
      await tester.runAsync(
        () => precacheImage(image, tester.element(find.byType(Scaffold))),
      );
      await tester.pumpWidget(
        _rowHost(
          ChatItemView(
            item: ChatItemPresentation.decode(
              _text(
                'decoded-image',
                '![](https://example.invalid/decoded.png)',
              ),
            ),
            bodyBuilder: (id, text) => TimelineMarkdown(
              id: id,
              text: text,
              onLink: (_) {},
              isSafeLink: (_) => false,
              imageBuilder: (_, _) => Image(image: image, height: 120),
            ),
            monotonicMicros: () => 789,
            onContentLayout: (id, stamp) => samples.add((id, stamp)),
            isDisplayActive: () => true,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(Image), findsOneWidget);
      expect(
        tester.renderObject<RenderImage>(find.byType(RawImage)).image,
        isNotNull,
      );
      expect(samples, isNotEmpty);
      expect(
        samples.every((sample) => sample == ('decoded-image', 789)),
        isTrue,
      );
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'content layout witness measures actual Flyer body layout, not placeholder or callback arrival',
    (tester) async {
      final controls = _Controls();
      final samples = <(String, int, int)>[];
      var clock = 500;
      await controls.adapter.applyTimeline(
        _mainBatch(
          placement: sdk.ChatPlacement.set,
          entries: ([_unknown('placeholder')]).map(_mainEntry).toList(),
        ),
      );
      await tester.pumpWidget(
        _host(
          controls,
          clock: () {
            final captured = clock;
            tester.binding.addPostFrameCallback((_) => clock = 999);
            return captured;
          },
          onLayout: (id, micros) => samples.add((id, micros, clock)),
          isActive: () => true,
        ),
      );
      await tester.pumpAndSettle();
      expect(samples, isEmpty);
      expect(clock, 500, reason: 'No witness surrounds a placeholder/title');
      await controls.adapter.applyTimeline(
        _mainBatch(
          placement: sdk.ChatPlacement.append,
          startSeq: 10001,
          entries: ([
            _text('actual-body', '正文布局见证'),
            _text('empty-body', ''),
          ]).map(_mainEntry).toList(),
        ),
      );
      await tester.pumpAndSettle();
      expect(samples, isNotEmpty);
      expect(
        samples.first,
        ('actual-body', 500, 999),
        reason: 'Layout timestamp must precede the earlier queued post-frame clock change',
      );
      expect(samples.every((sample) => sample.$1 == 'actual-body'), isTrue);
      expect(tester.binding.hasScheduledFrame, isFalse);
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(controls.dispose);
    },
  );

  testWidgets(
    'content layout witness rejects offstage, transparent, off-viewport and retired bodies',
    (tester) async {
      final item = ChatItemPresentation.decode(_text('body', '可见正文'));
      final samples = <int>[];
      var active = true;
      var layouts = 0;
      Widget body(String key) => ChatItemView(
        key: ValueKey(key),
        item: item,
        monotonicMicros: () {
          layouts++;
          return 123;
        },
        onContentLayout: (_, stamp) => samples.add(stamp),
        isDisplayActive: () => active,
      );
      await tester.pumpWidget(
        _rowHost(Offstage(offstage: true, child: body('offstage'))),
      );
      await tester.pump();
      expect(samples, isEmpty);
      await tester.pumpWidget(
        _rowHost(Opacity(opacity: 0, child: body('transparent'))),
      );
      await tester.pump();
      expect(samples, isEmpty);
      await tester.pumpWidget(
        _rowHost(
          ChatItemView(
            item: item,
            bodyBuilder: (_, _) => const Text.rich(
              TextSpan(text: ' \t\n', semanticsLabel: '仅辅助语义，不是可见正文'),
            ),
            monotonicMicros: () => 123,
            onContentLayout: (_, stamp) => samples.add(stamp),
            isDisplayActive: () => active,
          ),
        ),
      );
      await tester.pump();
      expect(
        samples,
        isEmpty,
        reason: 'Whitespace and semantics labels are not glyph content',
      );
      layouts = 0;
      await tester.pumpWidget(
        _rowHost(
          ListView(
            children: [const SizedBox(height: 650), body('off-viewport')],
          ),
        ),
      );
      await tester.pump();
      expect(
        layouts,
        greaterThan(0),
        reason: 'The cached off-viewport body really completed layout',
      );
      expect(samples, isEmpty);
      tester.binding.addPostFrameCallback((_) => active = false);
      await tester.pumpWidget(_rowHost(body('retired-after-layout')));
      expect(samples, isEmpty);
      active = true;
      await tester.pumpWidget(_rowHost(body('current')));
      expect(samples, [
        123,
      ], reason: 'The visibility guard must not simply suppress all samples');
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'bounded range witness exposes explicit next and copies only the displayed decoded window',
    (tester) async {
      final controls = _Controls();
      sdk.ChatAtom message(String database) => _fixtureAtom(
        id: 'window',
        payload: sdk.DeferredPayload(
          reference: sdk.ContentRef(
            databaseId: database,
            target: const sdk.ItemPayloadTarget(itemId: 'window'),
          ),
          byteLength: 100000,
        ),
      );
      final copied = <String>[];
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.setData') {
          copied.add((call.arguments as Map)['text'] as String);
        }
        return null;
      });
      addTearDown(
        () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
      );
      final reads = <(String, int, int)>[];
      final lateOld = Completer<sdk.ContentWindow>();
      final samples = <String>[];
      await controls.adapter.applyTimeline(
        _mainBatch(
          placement: sdk.ChatPlacement.set,
          entries: ([message('old')]).map(_mainEntry).toList(),
        ),
      );
      await tester.pumpWidget(
        _host(
          controls,
          clock: () => 1,
          isActive: () => true,
          onLayout: (id, _) => samples.add(id),
          read: (reference, range) async {
            reads.add((reference.databaseId, range.offset, range.maxBytes));
            if (reference.databaseId == 'old' && range.offset > 2) {
              return lateOld.future;
            }
            final bytes = reference.databaseId == 'old'
                ? range.offset == 0
                      ? [0xe4, 0xbd]
                      : utf8.encode('第二段')
                : utf8.encode('新的当前段');
            return sdk.ContentWindow(
              offset: range.offset,
              bytes: bytes,
              generation: 'g',
              availableThrough: reference.databaseId == 'old'
                  ? 100000
                  : bytes.length,
              sealed: true,
            );
          },
        ),
      );
      await tester.pumpAndSettle();
      expect(reads, isEmpty);
      expect(
        samples,
        isEmpty,
        reason: 'Deferred open control is not content layout',
      );
      final open = find.byKey(
        StudioDriverKeys.timelineContentOpen('window', 'payload'),
      );
      final text = find.byKey(
        StudioDriverKeys.timelineContentWindow('window', 'payload'),
      );
      final copy = find.byKey(
        StudioDriverKeys.timelineContentCopyWindow('window', 'payload'),
      );
      final next = find.byKey(
        StudioDriverKeys.timelineContentNextWindow('window', 'payload'),
      );
      await tester.tap(open);
      await tester.pumpAndSettle();
      final displayed = tester.widget<Text>(text).data!;
      expect(displayed, '\uFFFD');
      expect(samples, isNotEmpty);
      await tester.tap(copy);
      await tester.pump();
      expect(copied, [displayed]);
      expect(reads, [('old', 0, 64 * 1024)]);
      await tester.tap(next);
      await tester.pumpAndSettle();
      expect(tester.widget<Text>(text).data, '第二段');
      await tester.tap(copy);
      await tester.pump();
      expect(copied, [displayed, '第二段']);
      expect(reads, [('old', 0, 64 * 1024), ('old', 2, 64 * 1024)]);
      await tester.tap(next);
      await tester.pump();
      expect(reads.last, ('old', 2 + utf8.encode('第二段').length, 64 * 1024));
      await controls.adapter.applyTimeline(
        _mainBatch(
          placement: sdk.ChatPlacement.set,
          entries: ([message('new')]).map(_mainEntry).toList(),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(
        chatItemPresentationOf(controls.controller.messages.single)!
            .reference!
            .databaseId,
        'new',
      );
      expect(
        tester
            .widget<ChatItemView>(find.byType(ChatItemView))
            .item
            .reference!
            .databaseId,
        'new',
      );
      expect(text, findsNothing);
      await tester.tap(open);
      await tester.pumpAndSettle();
      expect(tester.widget<Text>(text).data, '新的当前段');
      lateOld.complete(
        sdk.ContentWindow(
          offset: 8,
          bytes: utf8.encode('迟到旧段'),
          generation: 'old',
          availableThrough: 100000,
          sealed: true,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('迟到旧段'), findsNothing);
      await tester.tap(copy);
      await tester.pump();
      expect(copied.last, '新的当前段');
      expect(
        reads.length,
        4,
        reason: 'Neither copy nor diagnostics may read through all ranges',
      );
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(controls.dispose);
    },
  );

  testWidgets(
    'Main tool disclosure owns one automatic bounded read per declared reference',
    (tester) async {
      final controls = _Controls();
      const presentationId = 'status:main-range';
      const contentItemId = 'original-main-result';
      const lastLine = 'bounded-output-line-080';
      final outputText = [
        for (var line = 1; line < 80; line++) 'bounded output line $line',
        lastLine,
      ].join('\n');
      final argumentsText = jsonEncode({'command': 'printf bounded output'});
      const argumentsRef = sdk.ContentRef(
        databaseId: 'main-range-db',
        target: sdk.BodyContentTarget(
          owner: sdk.ItemContentOwner(itemId: contentItemId),
          key: 'tool.arguments',
        ),
      );
      const outputRef = sdk.ContentRef(
        databaseId: 'main-range-db',
        target: sdk.BodyContentTarget(
          owner: sdk.ItemContentOwner(itemId: contentItemId),
          key: 'tool.result',
        ),
      );
      final item = sdk.ChatAtom(
        id: presentationId,
        completionItemId: presentationId,
        sourceOrder: null,
        source: const sdk.BackgroundResultChatSource(messageId: 'result'),
        kind: sdk.ChatAtomKind.toolCall,
        delivery: sdk.ChatDeliveryKind.independent,
        lifecycle: const sdk.TerminalChatAtom(
          started: null,
          ended: null,
          outcome: sdk.ChatTerminalOutcome.completed,
        ),
        turnId: 'original-turn',
        contents: const [
          sdk.ChatAtomContent(
            role: sdk.ChatContentRole.toolArguments,
            reference: argumentsRef,
          ),
          sdk.ChatAtomContent(
            role: sdk.ChatContentRole.toolOutput,
            reference: outputRef,
          ),
        ],
        payload: sdk.InlinePayload(
          bytes: utf8.encode(
            jsonEncode({
              'contract': 'anywork.chat/1',
              'type': 'tool',
              'data': {
                'invocation': {
                  'toolCallId': 'main-call',
                  'name': 'exec',
                  'presentationContract': 'builtin.exec@2',
                },
                'state': {
                  'kind': 'succeeded',
                  'completedAt': 12,
                  'output': {'exitCode': 0, 'attachments': []},
                },
              },
              'bodies': [
                for (final (key, text) in [
                  ('tool.arguments', argumentsText),
                  ('tool.result', outputText),
                ])
                  {
                    'key': key,
                    'byteLength': utf8.encode(text).length,
                    'inline': utf8.encode(text),
                  },
              ],
            }),
          ),
        ),
      );
      final output = Completer<sdk.ContentWindow>();
      final reads = <(sdk.ContentRef, int, int)>[];
      final accepted = sdk.ContentWindow(
        bytes: utf8.encode(outputText),
        offset: 0,
        generation: 'original-output',
        availableThrough: utf8.encode(outputText).length,
        sealed: true,
      );
      await tester.binding.setSurfaceSize(const Size(1280, 420));
      try {
        await controls.adapter.applyTimeline(
          _mainBatch(
            placement: sdk.ChatPlacement.set,
            entries: [_mainEntry(item)],
          ),
        );
        await tester.pumpWidget(
          _host(
            controls,
            isActive: () => !controls.isRetired,
            read: (reference, range) {
              reads.add((reference, range.offset, range.maxBytes));
              if (identical(reference, outputRef)) return output.future;
              expect(reference, same(argumentsRef));
              final bytes = utf8.encode(argumentsText);
              return Future.value(
                sdk.ContentWindow(
                  bytes: bytes,
                  offset: 0,
                  generation: 'original-arguments',
                  availableThrough: bytes.length,
                  sealed: true,
                ),
              );
            },
          ),
        );
        await tester.pumpAndSettle();
        final mainController = controls.controller;
        final mainPosition = controls.scrollController.position;
        final generation = controls.adapter.generation;
        expect(mainPosition.axisDirection, AxisDirection.up);
        final details = find.byType(TimelineToolDetails);
        expect(details, findsOneWidget);
        final outer = find.byKey(
          ValueKey(
            'timeline-tool-details:${tester.widget<TimelineToolDetails>(details).item.id}',
          ),
        );
        expect(outer, findsOneWidget);
        final outerTile = tester.element(
          find.descendant(of: outer, matching: find.byType(ExpansionTile)),
        );
        final outerTitle = find.descendant(
          of: outer,
          matching: find.byWidgetPredicate(
            (widget) =>
                widget is ListTile &&
                identical(
                  widget.title,
                  (outerTile.widget as ExpansionTile).title,
                ),
          ),
        );
        expect(outerTitle, findsOneWidget);
        expect(outerTitle.hitTestable(), findsOneWidget);
        expect(reads, isEmpty);
        await tester.tap(outerTitle);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        final connector = find.byWidgetPredicate(
          (widget) =>
              widget is TimelineContentRangeConnector &&
              widget.itemId == presentationId &&
              widget.contentKey == sdk.ChatContentRole.toolOutput.name,
        );
        expect(connector, findsOneWidget);
        final originalState = tester.state(connector);
        final owner = originalState as TimelineCurrentWindowDisplay;
        expect(owner.reference, same(outputRef));
        expect(
          tester
              .element(connector)
              .getInheritedWidgetOfExactType<TimelineBodyReadIntent>(),
          isNotNull,
        );
        final rangeView = find.descendant(
          of: connector,
          matching: find.byType(TimelineContentRangeView),
        );
        final disclosure = find.descendant(
          of: connector,
          matching: find.byKey(
            StudioDriverKeys.timelineContentOpen(
              presentationId,
              sdk.ChatContentRole.toolOutput.name,
            ),
          ),
        );
        final pending = tester.widget<TimelineContentRangeView>(rangeView);
        expect(pending.initiallyExpanded, isTrue);
        expect(
          (pending.loading, pending.active, pending.canRead),
          (true, true, true),
        );
        expect(pending.disclosed, isTrue);
        expect(
          disclosure,
          findsNothing,
          reason: 'The outer tool is the sole body disclosure',
        );
        expect(owner.window, isNull);
        expect(owner.error, isNull);
        expect(reads, [
          (argumentsRef, 0, 64 * 1024),
          (outputRef, 0, 64 * 1024),
        ]);
        await Scrollable.ensureVisible(
          tester.element(rangeView),
          alignment: 0.5,
        );
        await tester.pump();
        expect(owner.window, isNull);
        expect(tester.state(connector), same(originalState));
        output.complete(accepted);
        await tester.pumpAndSettle();
        expect(owner.window, same(accepted));
        expect(owner.error, isNull);
        final ready = tester.widget<TimelineContentRangeView>(rangeView);
        expect(ready.initiallyExpanded, isTrue);
        expect(
          (ready.loading, ready.active, ready.canRead),
          (false, true, true),
        );
        expect(ready.window, same(accepted));
        expect(ready.disclosed, isTrue);
        expect(disclosure, findsNothing);
        expect(tester.state(connector), same(originalState));
        expect(owner.reference, same(outputRef));
        expect(controls.controller, same(mainController));
        expect(controls.scrollController.position, same(mainPosition));
        expect(controls.adapter.generation, generation);
        final text = find.byKey(
          StudioDriverKeys.timelineContentWindow(
            presentationId,
            sdk.ChatContentRole.toolOutput.name,
          ),
        );
        expect(tester.widget<Text>(text).data, outputText);
        final rich = find.descendant(of: text, matching: find.byType(RichText));
        expect(rich, findsOneWidget);
        final paragraph = tester.renderObject<RenderParagraph>(rich);
        final boxes = paragraph.getBoxesForSelection(
          TextSelection(
            baseOffset: outputText.indexOf(lastLine),
            extentOffset: outputText.length,
          ),
        );
        expect(boxes, hasLength(1));
        paragraph.showOnScreen(rect: boxes.single.toRect());
        await tester.pump();
        final main = find.byWidgetPredicate(
          (widget) =>
              widget is Scrollable &&
              identical(widget.controller, controls.scrollController),
        );
        expect(main, findsOneWidget);
        final glyph = boxes.single.toRect().shift(
          paragraph.localToGlobal(Offset.zero),
        );
        final viewport = tester.getRect(main).inflate(1);
        expect(viewport.contains(glyph.topLeft), isTrue);
        expect(viewport.contains(glyph.bottomRight), isTrue);
        await Scrollable.ensureVisible(
          tester.element(outerTitle),
          alignment: 0.5,
        );
        await tester.pump();
        expect(outerTitle.hitTestable(), findsOneWidget);
        await tester.tap(outerTitle);
        await tester.pumpAndSettle();
        expect(owner.window, isNull);
        expect(originalState.mounted, isFalse);
        expect(connector, findsNothing);
        expect(text, findsNothing);
        expect(reads, [
          (argumentsRef, 0, 64 * 1024),
          (outputRef, 0, 64 * 1024),
        ]);
        expect(tester.takeException(), isNull);
      } finally {
        if (!output.isCompleted) output.complete(accepted);
        await tester.pumpWidget(const SizedBox());
        await tester.runAsync(controls.dispose);
        await tester.binding.setSurfaceSize(null);
      }
    },
  );

  testWidgets(
    'production Flyer assembly keeps one custom message per item and appends incrementally',
    (tester) async {
      final controls = _Controls();
      final adapter = controls.adapter;
      final operations = <ChatOperation>[];
      final subscription = controls.controller.operationsStream.listen(
        operations.add,
      );
      await adapter.applyTimeline(
        _mainBatch(
          placement: sdk.ChatPlacement.set,
          entries: ([
            _text('text', '正文'),
            _unknown('unknown'),
          ]).map(_mainEntry).toList(),
          before: 'opaque',
        ),
      );
      final first = controls.controller.messages.first;
      await tester.pumpWidget(_host(controls));
      await tester.pumpAndSettle(
        const Duration(milliseconds: 100),
        EnginePhase.sendSemanticsUpdate,
        const Duration(seconds: 3),
      );
      expect(find.byType(Chat), findsOneWidget);
      expect(find.byType(ChatAnimatedListReversed), findsOneWidget);
      expect(find.byType(ChatItemView), findsNWidgets(2));
      expect(controls.controller.messages.map((m) => m.id), [
        'text',
        'unknown',
      ]);
      expect(
        controls.controller.messages.every((m) => m is CustomMessage),
        isTrue,
      );
      expect(chatItemPresentationOf(first)!.createdAt, isNull);
      final unknown = controls.controller.messages.last;
      expect(unknown.authorId, 'unknown');
      expect(unknown.createdAt, isNull);

      await adapter.applyTimeline(
        _mainBatch(
          placement: sdk.ChatPlacement.prepend,
          entries: ([_text('older', '旧页')]).map(_mainEntry).toList(),
        ),
      );
      await adapter.applyTimeline(
        _mainBatch(
          placement: sdk.ChatPlacement.append,
          startSeq: 10002,
          entries: ([_text('new', '新内容')]).map(_mainEntry).toList(),
        ),
      );
      await tester.pumpAndSettle(
        const Duration(milliseconds: 100),
        EnginePhase.sendSemanticsUpdate,
        const Duration(seconds: 3),
      );
      expect(controls.controller.messages.map((m) => m.id), [
        'older',
        'text',
        'unknown',
        'new',
      ]);
      expect(identical(controls.controller.messages[1], first), isTrue);
      expect(
        operations.where((o) => o.type == ChatOperationType.set),
        hasLength(1),
      );
      expect(
        operations.where((o) => o.type == ChatOperationType.insertAll),
        hasLength(2),
      );
      expect(
        operations.where((o) => o.type == ChatOperationType.insert),
        isEmpty,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(() async {
        await subscription.cancel();
        await controls.dispose();
      });
    },
  );

  testWidgets(
    'unknown and deferred rows have height; deferred reads are explicit bounded windows',
    (tester) async {
      final controls = _Controls();
      const reference = sdk.ContentRef(
        databaseId: 'database',
        target: sdk.ItemPayloadTarget(itemId: 'deferred'),
      );
      await controls.adapter.applyTimeline(
        _mainBatch(
          placement: sdk.ChatPlacement.set,
          entries: ([
            _unknown('unknown', marker: 'builtin.exec@1'),
            _fixtureAtom(
              id: 'deferred',
              payload: sdk.DeferredPayload(
                reference: reference,
                byteLength: 900000,
              ),
            ),
          ]).map(_mainEntry).toList(),
        ),
      );
      final requests = <sdk.ContentRange>[];
      await tester.pumpWidget(
        _host(
          controls,
          read: (actual, range) async {
            expect(identical(actual, reference), isTrue);
            requests.add(range);
            return sdk.ContentWindow(
              offset: range.offset,
              bytes: utf8.encode('公开原文'),
              generation: '1',
              availableThrough: 900000,
              sealed: true,
            );
          },
        ),
      );
      await tester.pumpAndSettle(
        const Duration(milliseconds: 100),
        EnginePhase.sendSemanticsUpdate,
        const Duration(seconds: 3),
      );
      expect(requests, isEmpty);
      for (final row in tester.widgetList<ChatItemView>(
        find.byType(ChatItemView),
      )) {
        expect(tester.getSize(find.byWidget(row)).height, greaterThan(0));
      }
      expect(find.text('执行命令'), findsNothing);
      await tester.tap(find.text('exec · 未知展示格式'));
      await tester.pumpAndSettle(
        const Duration(milliseconds: 100),
        EnginePhase.sendSemanticsUpdate,
        const Duration(seconds: 3),
      );
      expect(
        find.text('不支持的 presentationContract：builtin.exec@1'),
        findsOneWidget,
      );
      expect(requests, isEmpty);
      await tester.tap(find.text('按需查看原文 · 900000 字节'));
      await tester.pumpAndSettle(
        const Duration(milliseconds: 100),
        EnginePhase.sendSemanticsUpdate,
        const Duration(seconds: 3),
      );
      expect(requests, hasLength(1));
      expect(requests.single.offset, 0);
      expect(requests.single.maxBytes, 64 * 1024);
      expect(find.text('公开原文'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(controls.dispose);
    },
  );

  testWidgets(
    'real viewport fills past eight unchanged layouts without operations until explicit EOF',
    (tester) async {
      final controls = _Controls();
      await controls.adapter.applyTimeline(
        _mainBatch(
          placement: sdk.ChatPlacement.set,
          entries: ([_unknown('initial')]).map(_mainEntry).toList(),
        ),
      );
      var loads = 0;
      String? cursor = 'page:0';
      var operations = 0;
      final subscription = controls.controller.operationsStream.listen(
        (_) => operations++,
      );
      addTearDown(subscription.cancel);
      late StateSetter update;
      await tester.pumpWidget(
        StatefulBuilder(
          builder: (context, setState) {
            update = setState;
            return _host(
              controls,
              view: TimelineSessionViewState(
                threadId: 'thread',
                generation: 1,
                mode: TimelineDisplayMode.live,
                connection: TimelineConnectionPhase.ready,
                hasOlder: cursor != null,
                olderCursor: cursor,
              ),
              onLoadOlder: () async {
                loads++;
                // A page may only contribute to an existing collapsed item:
                // no operation, no added height, but a new atomic boundary.
                update(() => cursor = loads == 12 ? null : 'page:$loads');
              },
            );
          },
        ),
      );
      await tester.pumpAndSettle();
      expect(loads, 12);
      expect(operations, 0);
      expect(controls.controller.messages, hasLength(1));
      final position = controls.scrollController.position;
      expect(position.maxScrollExtent, position.minScrollExtent);
      expect(position.viewportDimension, greaterThan(0));
      await tester.pump(const Duration(seconds: 1));
      expect(
        loads,
        12,
        reason: 'Explicit EOF may leave whitespace; no frame polling follows',
      );
      await tester.pumpWidget(const SizedBox());
      final disposing = controls.dispose();
      await tester.pump();
      await disposing;
    },
  );

  testWidgets(
    'no-progress older page stops fill; resize and append do not fabricate user reading intent',
    (tester) async {
      final controls = _Controls();
      await controls.adapter.applyTimeline(
        _mainBatch(
          placement: sdk.ChatPlacement.set,
          entries: ([_unknown('initial')]).map(_mainEntry).toList(),
        ),
      );
      var loads = 0;
      var intents = 0;
      final view = const TimelineSessionViewState(
        threadId: 'thread',
        generation: 1,
        mode: TimelineDisplayMode.live,
        connection: TimelineConnectionPhase.ready,
        hasOlder: true,
        olderCursor: 'same-cursor',
      );
      Widget host() => _host(
        controls,
        view: view,
        onLoadOlder: () async {
          loads++;
        },
        onEnterHistory: () => intents++,
      );
      await tester.pumpWidget(host());
      await tester.pumpAndSettle();
      expect(loads, 1);
      await controls.adapter.applyTimeline(
        _mainBatch(
          placement: sdk.ChatPlacement.append,
          startSeq: 10001,
          entries: ([for (var i = 0; i < 40; i++) _text('long:$i', '正文 $i')])
              .map(_mainEntry)
              .toList(),
        ),
      );
      await tester.pumpAndSettle();
      expect(intents, 0);
      tester.view.physicalSize = const Size(700, 400);
      addTearDown(tester.view.resetPhysicalSize);
      await tester.pumpWidget(host());
      await tester.pumpAndSettle();
      expect(intents, 0);
      expect(loads, 1);
      await tester.drag(
        find.byType(ChatAnimatedListReversed),
        const Offset(0, 350),
      );
      await tester.pumpAndSettle();
      expect(intents, greaterThan(0));
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(controls.dispose);
    },
  );
}

Widget _host(
  _Controls controls, {
  ChatContentRead? read,
  TimelineSessionViewState? view,
  Future<void> Function()? onLoadOlder,
  VoidCallback? onEnterHistory,
  int Function()? clock,
  void Function(String, int)? onLayout,
  bool Function()? isActive,
}) => MaterialApp(
  theme: pureStudioTheme(),
  locale: const Locale('zh'),
  localizationsDelegates: [
    AppLocalizations.delegate,
    ...GlobalMaterialLocalizations.delegates,
  ],
  supportedLocales: AppLocalizations.supportedLocales,
  home: Scaffold(
    body: TimelineView(
      threadId: 'thread',
      view:
          view ??
          const TimelineSessionViewState(
            threadId: 'thread',
            generation: 1,
            mode: TimelineDisplayMode.live,
            connection: TimelineConnectionPhase.ready,
          ),
      controls: controls,
      onLoadOlder: onLoadOlder ?? () async {},
      onRetryOlder: () async {},
      onReturnLive: () async {},
      onEnterHistory: onEnterHistory ?? () {},
      onRetryConnection: () {},
      onLink: (_) {},
      isSafeLink: (_) => false,
      remoteImageBuilder: (_, url) => TimelineRemoteImageConnector(url: url),
      contentRangeBuilder: read == null
          ? null
          : (itemId, contentKey, label, reference, witness) =>
                TimelineContentRangeConnector(
                  itemId: itemId,
                  contentKey: contentKey,
                  label: label,
                  reference: reference,
                  witness: witness,
                  readContent: read,
                  isDisplayActive: isActive,
                ),
      monotonicMicros: clock,
      onContentLayout: onLayout,
      isDisplayActive: isActive,
    ),
  ),
);

Widget _rowHost(Widget child) => MaterialApp(
  theme: pureStudioTheme(),
  locale: const Locale('zh'),
  localizationsDelegates: [
    AppLocalizations.delegate,
    ...GlobalMaterialLocalizations.delegates,
  ],
  supportedLocales: AppLocalizations.supportedLocales,
  home: Scaffold(body: child),
);

final class _ImageHttpClient implements HttpClient {
  _ImageHttpClient(this.read);
  final Future<HttpClientRequest> Function(Uri) read;

  @override
  Future<HttpClientRequest> getUrl(Uri url) => read(url);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _Controls implements TimelineUiControllers {
  @override
  final InMemoryChatController controller = InMemoryChatController();
  @override
  final scrollController = ScrollController();
  final images = TimelineImageResources(threadId: 'thread');
  late final adapter = TimelineMessageController(controller, generation: 1);
  @override
  Key get chatKey => const ValueKey('chat');
  @override
  bool get isRetired => false;
  @override
  void bind() {}
  @override
  Future<void> unbind() async {}
  Future<void> dispose() async {
    final ended = Completer<void>();
    controller.operationsStream.listen((_) {}, onDone: ended.complete);
    adapter.dispose();
    images.release();
    controller.dispose();
    scrollController.dispose();
    await ended.future;
  }
}

// Every envelope in these component stories is an explicitly independent Main
// status/text item. This helper does not classify, join or reorder atoms.
sdk.CompletedEntry _mainEntry(sdk.ChatAtom atom) => sdk.CompletedEntry(
  recordId: atom.completionItemId ?? atom.id,
  completionSeq: 1,
  run: const sdk.CompletionRunPosition(startSeq: 1, ordinal: 1),
  mainPresentation: sdk.MainPresentation.single,
  atom: atom,
);

// Explicit synthetic completion positions for these rendering stories. They
// never classify/group payloads or create a second product reducer.
sdk.TimelineBatch _mainBatch({
  required sdk.ChatPlacement placement,
  required List<sdk.CompletedEntry> entries,
  String? before,
  int? startSeq,
}) {
  final start =
      startSeq ??
      switch (placement) {
        sdk.ChatPlacement.set => 10000,
        sdk.ChatPlacement.prepend => 100,
        sdk.ChatPlacement.append => 20000,
      };
  return sdk.TimelineBatch(
    presentationVersion: sdk.presentationVersion,
    placement: placement,
    before: before,
    fromPos: placement == sdk.ChatPlacement.append ? start - 1 : null,
    throughPos: placement == sdk.ChatPlacement.prepend
        ? 10000
        : start + entries.length - 1,
    blocks: [
      for (final (i, entry) in entries.indexed)
        sdk.DisplayBlock(
          id: entry.recordId,
          historyPos: start + i,
          body: sdk.SingleDisplayBlock(
            visibility: sdk.SingleVisibility.content,
            record: sdk.DisplayRecord(
              atom: entry.atom,
              contentSource: sdk.CompletedOriginal(
                completionId: entry.recordId,
              ),
            ),
          ),
        ),
    ],
  );
}
