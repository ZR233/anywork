// Opt-in 组件行为证明（默认门禁不运行）。
//
// 唯一列表路线是公开 `Chat` + 原生 `ChatAnimatedListReversed` + stock
// `InMemoryChatController`；这里证明生产 `TimelineView` 的真实绑定、真实用户意图才进入
// History、视口自动补齐/重试、以及全文查看器只读当前 lease 的详情引用。
// 算法层覆盖由 test/client/timeline_display_lease_test.dart 与
// timeline_session_owner_test.dart 承担，不在这里重复。
import 'dart:async';
import 'dart:convert';

import 'package:anywork/src/app/theme/material3_theme.dart';
import 'package:anywork/src/app/app_graph.dart';
import 'package:anywork/src/domain/models/timeline_commands.dart';
import 'package:anywork/src/features/conversation/timeline/connectors/timeline_connector.dart';
import 'package:anywork/src/features/conversation/timeline/connectors/timeline_detail_connector.dart';
import 'package:anywork/src/features/conversation/timeline/connectors/timeline_media_connector.dart';
import 'package:anywork/src/features/conversation/timeline/state/timeline_entry.dart';
import 'package:anywork/src/features/conversation/timeline/view_models/timeline_view_model.dart';
import 'package:anywork/src/features/conversation/timeline/widgets/timeline_activity_row.dart';
import 'package:anywork/src/features/conversation/timeline/widgets/timeline_activity_group_adapter.dart';
import 'package:anywork/src/features/conversation/timeline/widgets/timeline_activity_group_views.dart';
import 'package:anywork/src/features/conversation/timeline/widgets/timeline_entry_view.dart';
import 'package:anywork/src/features/conversation/timeline/widgets/timeline_markdown.dart';
import 'package:anywork/src/l10n/app_localizations.dart';
import 'package:anywork/src/presentation/providers/client_provider.dart';
import 'package:anywork/src/presentation/view_models/timeline_session_owner.dart';
import 'package:anywork/src/shared/studio_code_block.dart';
import 'package:anywork/src/shared/studio_driver_key_values.dart';
import 'package:anywork/src/shared/studio_driver_keys.dart';
import 'package:anywork/src/shared/studio_chrome.dart';
import 'package:anywork/src/shared/studio_driver_projection.dart';
import 'package:anywork/src/shared/studio_driver_state.dart';
import 'package:anywork_client/accounts_ports.dart';
import 'package:anywork_client/studio_client.dart';
import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_chat_core/flutter_chat_core.dart';
import 'package:flutter_chat_ui/flutter_chat_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flyer_chat_image_message/flyer_chat_image_message.dart';
import 'package:gpt_markdown/gpt_markdown.dart';

import '../../client/support/conversation_fixtures.dart';
import '../../client/support/mapped_conversation_feed.dart';
import '../../client/support/pump_client_future.dart';
import '../../client/support/unused_account_ports.dart';
import '../../client/support/recording_demo_transport.dart';
import '../../client/support/test_statistics_feed.dart';
import 'support/timeline_component_fixtures.dart';

void main() {
  ConversationItem textItem(
    String id, {
    required int appendSeq,
    String body = '正文',
    int? totalBytes,
  }) => componentText(
    id,
    appendSeq: appendSeq,
    body: body,
    totalBytes: totalBytes,
  );

  ConversationItem toolItem(
    String id, {
    int appendSeq = 1,
    String name = 'exec_command',
    required String arguments,
  }) =>
      componentTool(id, appendSeq: appendSeq, name: name, arguments: arguments);

  ConversationItem imageToolItem(
    String id, {
    required int appendSeq,
    String attachmentId = 'att-shared',
    String name = 'view_image',
    String result = 'ok',
    int? totalResultBytes,
  }) => componentTool(
    id,
    appendSeq: appendSeq,
    name: name,
    arguments: '{"path":"/workspace/images/shot.png"}',
    result: result,
    totalResultBytes: totalResultBytes,
    attachments: [
      ThreadAttachmentView(
        id: attachmentId,
        modality: AttachmentModalityView.image,
        mediaType: 'image/png',
        byteSize: _onePixelPng.length,
        filename: 'shot.png',
        width: 1,
        height: 1,
      ),
    ],
  );

  Future<TimelineDisplayLease> leaseFor(
    WidgetTester tester, {
    required List<ConversationItem> items,
    String? before,
    bool hasOlder = false,
  }) async {
    final (_, owner, transport) = await _openDetailSession(
      tester,
      baseline: componentBaseline(
        items.take(32).toList(),
        before: before,
        hasOlder: hasOlder,
      ),
    );
    final lease = owner.lease('thread')!;
    _fixtures[lease] = (owner, transport);
    for (var start = 32; start < items.length; start += 32) {
      await _appendCompleted(
        tester,
        lease,
        items.skip(start).take(32).toList(),
      );
    }
    return lease;
  }

  TimelineSessionViewState viewState({
    TimelineDisplayMode mode = TimelineDisplayMode.live,
    bool hasOlder = false,
    bool isLoadingOlder = false,
    Object? olderError,
    bool hasNewOutput = false,
    TimelineConnectionPhase connection = TimelineConnectionPhase.ready,
    Object? connectionError,
  }) => TimelineSessionViewState(
    threadId: 'thread',
    generation: 1,
    mode: mode,
    connection: connection,
    connectionError: connectionError,
    olderCursor: hasOlder ? 'cursor' : null,
    hasOlder: hasOlder,
    isLoadingOlder: isLoadingOlder,
    olderError: olderError,
    hasNewOutput: hasNewOutput,
  );

  /// 需要真实 Client 的用例（附件字节等）在这里注入 override。
  Widget host(
    Widget child, {
    Size size = const Size(900, 700),
    AnyworkClient? client,
    TimelineSessionOwner? owner,
  }) => MediaQuery(
    data: MediaQueryData(size: size),
    child: Directionality(
      textDirection: TextDirection.ltr,
      child: ProviderScope(
        overrides: [
          if (client != null) anyworkClientProvider.overrideWithValue(client),
          if (owner != null)
            timelineSessionOwnerProvider.overrideWithValue(owner),
        ],
        child: MaterialApp(
          theme: pureStudioTheme(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(body: SizedBox.expand(child: child)),
        ),
      ),
    ),
  );

  testWidgets('生产 Timeline 使用公开 Chat + ChatAnimatedListReversed 并真实绑卸载', (
    tester,
  ) async {
    final lease = await leaseFor(
      tester,
      items: [textItem('item-a', appendSeq: 1)],
    );
    await tester.pumpWidget(
      host(
        componentTimeline(
          threadId: 'thread',
          view: viewState(),
          lease: lease,
          onLoadOlder: () async {},
          onRetryOlder: () async {},
          onReturnLive: () async {},
          onEnterHistory: () {},
          onRetryConnection: () async {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(Chat), findsOneWidget);
    expect(find.byType(ChatAnimatedListReversed), findsOneWidget);
    expect(lease.controller.messages.single, isA<TextMessage>());
    expect(
      timelineEntryOf(lease.controller.messages.single),
      same(lease.presentationFor('item-a')),
    );
    expect(
      find.byKey(
        StudioDriverKeys.timelineRow(lease.presentationFor('item-a')!.id),
      ),
      findsOneWidget,
    );
    expect(lease.isMounted, isTrue);

    final owner = _fixtures[lease]!.$1;
    final closing = await pumpClientFuture(
      tester,
      owner.close(deadline: DateTime.utc(2000)),
      'mounted Chat close report',
    );
    expect(closing.complete, isFalse);
    expect(closing.unresolved.single.owner, 'timeline-display:thread');
    expect(lease.isReleased, isFalse, reason: 'close 不能把仍挂载的 Chat 当作已释放');
    // 真实子树卸载后 lease 才能释放 controller。
    await tester.pumpWidget(host(const SizedBox.shrink()));
    await tester.pumpAndSettle();
    expect(lease.isMounted, isFalse);
    await pumpClientFuture(
      tester,
      owner.close(),
      'unmounted Chat lease release',
    );
    expect(lease.isReleased, isTrue);

    // 已释放的代次明确拒绝再次挂载，而不是把已销毁 controller 交给子树。
    expect(lease.bind, throwsStateError);
  });

  testWidgets('真实 Flyer 普通正文复制保留缩进、邮箱和尾随换行', (tester) async {
    const body = '    raw paragraph: user@example.test\n\nlast line  \r\n';
    String? copied;
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        copied = (call.arguments as Map)['text'] as String;
      }
      return null;
    });
    addTearDown(
      () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
    );
    final lease = await leaseFor(
      tester,
      items: [textItem('raw-short', appendSeq: 1, body: body)],
    );
    await tester.pumpWidget(
      host(
        componentTimeline(
          threadId: 'thread',
          view: viewState(),
          lease: lease,
          onLoadOlder: () async {},
          onRetryOlder: () async {},
          onReturnLive: () async {},
          onEnterHistory: () {},
          onRetryConnection: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(Chat), findsOneWidget);
    expect(find.byType(ChatAnimatedListReversed), findsOneWidget);
    final text = find.byKey(const ValueKey('plain-text-raw-short'));
    expect(tester.widget<Text>(text).data, body);
    bool interactive(InlineSpan span) =>
        span is TextSpan &&
        (span.recognizer != null || (span.children?.any(interactive) ?? false));
    final rich = tester.widget<RichText>(
      find.descendant(of: text, matching: find.byType(RichText)),
    );
    expect(interactive(rich.text), isFalse);
    final selection = tester.state<SelectableRegionState>(
      find.byType(SelectableRegion),
    );
    selection.selectAll(SelectionChangedCause.keyboard);
    await tester.pump();
    final copy = selection.contextMenuButtonItems
        .firstWhere((item) => item.type == ContextMenuButtonType.copy)
        .onPressed;
    expect(copy, isNotNull);
    copy!();
    await tester.pump();
    expect(copied, body);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Timeline Markdown 邮箱与不安全链接均无手势且保留源文', (tester) async {
    const source = 'user@example.test\n\n[危险链接](javascript:alert(1))';
    var launched = false;
    await tester.pumpWidget(
      host(
        SingleChildScrollView(
          child: TimelineMarkdown(
            id: 'unsafe-links',
            text: source,
            onLink: (_) => launched = true,
            isSafeLink: (_) => false,
            imageBuilder: (_, _) => throw StateError('没有图片'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(GptMarkdown), findsOneWidget);
    expect(
      tester.widget<TimelineMarkdown>(find.byType(TimelineMarkdown)).text,
      source,
    );
    bool interactive(InlineSpan span) =>
        span is TextSpan &&
        (span.recognizer != null || (span.children?.any(interactive) ?? false));
    for (final rich in tester.widgetList<RichText>(
      find.descendant(
        of: find.byType(TimelineMarkdown),
        matching: find.byType(RichText),
      ),
    )) {
      expect(interactive(rich.text), isFalse);
    }
    expect(find.text('user@example.test', findRichText: true), findsOneWidget);
    expect(find.text('危险链接', findRichText: true), findsOneWidget);
    await tester.tap(find.text('危险链接', findRichText: true));
    await tester.pumpAndSettle();
    expect(launched, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Timeline Markdown 标题保留主题字号层级，不退化为正文', (tester) async {
    late TextTheme textTheme;
    await tester.pumpWidget(
      host(
        Builder(
          builder: (context) {
            textTheme = Theme.of(context).textTheme;
            return SingleChildScrollView(
              child: TimelineMarkdown(
                id: 'headings',
                text: '# 一级标题\n\n## 二级标题\n\n### 三级标题\n\n普通正文',
                onLink: (_) => fail('没有链接'),
                isSafeLink: (_) => false,
                imageBuilder: (_, _) => throw StateError('没有图片'),
              ),
            );
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    for (final (label, style) in [
      ('一级标题', textTheme.headlineLarge!),
      ('二级标题', textTheme.headlineMedium!),
      ('三级标题', textTheme.headlineSmall!),
    ]) {
      final heading = tester.renderObject<RenderParagraph>(
        find.byWidgetPredicate(
          (widget) =>
              widget is RichText && widget.text.toPlainText().startsWith(label),
        ),
      );
      final span = heading.text.getSpanForPosition(
        const TextPosition(offset: 0),
      )!;
      expect(span.style?.fontSize, style.fontSize, reason: '$label 必须使用标题字号');
      expect(heading.size.height, greaterThan(textTheme.bodyMedium!.fontSize!));
      expect(heading.didExceedMaxLines, isFalse);
    }
  });

  for (final markdown in ['---', '前段\n\n---\n\n后段']) {
    testWidgets('Timeline Markdown 正确保留分隔线语法源文：$markdown', (tester) async {
      await tester.pumpWidget(
        host(
          SingleChildScrollView(
            child: TimelineMarkdown(
              id: 'rule',
              text: markdown,
              onLink: (_) => fail('没有链接'),
              isSafeLink: (_) => false,
              imageBuilder: (_, _) => throw StateError('没有图片'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(GptMarkdown), findsOneWidget);
      expect(
        tester.getSize(find.byType(TimelineMarkdown)).height,
        greaterThan(0),
      );
      expect(find.text('---', findRichText: true), findsNothing);
      expect(
        tester.widget<TimelineMarkdown>(find.byType(TimelineMarkdown)).text,
        markdown,
      );
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('共享 TimelineMarkdown 正文增长解析列表并随窄宽窗口重排', (tester) async {
    final plain = List.filled(6, '流式文本需要按阅读列宽度自动换行').join(' ');
    const markdown = '**追加后的强调正文**\n\n- 新增的列表项\n';
    late StateSetter updateBody;
    String body = plain;

    Widget surface(double width) => host(
      Center(
        child: SizedBox(
          width: width,
          child: SingleChildScrollView(
            child: DefaultTextStyle.merge(
              softWrap: false,
              child: StatefulBuilder(
                builder: (context, setState) {
                  updateBody = setState;
                  return TimelineMarkdown(
                    id: 'shared-body',
                    text: body,
                    onLink: (_) => fail('没有链接'),
                    isSafeLink: (_) => false,
                    imageBuilder: (_, _) => throw StateError('没有图片'),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );

    await tester.pumpWidget(surface(320));
    await tester.pumpAndSettle();
    RenderParagraph paragraph() => tester.renderObject<RenderParagraph>(
      find.byWidgetPredicate(
        (widget) => widget is RichText && widget.text.toPlainText() == plain,
      ),
    );
    int lines() => paragraph()
        .getBoxesForSelection(
          TextSelection(baseOffset: 0, extentOffset: plain.length),
        )
        .map((box) => box.top)
        .toSet()
        .length;
    final narrowPlainLines = lines();
    expect(narrowPlainLines, greaterThan(1), reason: '纯文本正文必须实际折行');
    expect(paragraph().didExceedMaxLines, isFalse);

    updateBody(() => body = markdown);
    await tester.pumpAndSettle();
    expect(tester.widget<GptMarkdown>(find.byType(GptMarkdown)).data, markdown);
    expect(find.text('新增的列表项', findRichText: true), findsOneWidget);
    final appendedText = '这是尚在增长中的正文内容'.padRight(160, '续');
    updateBody(() => body = '$markdown\n\n$appendedText');
    await tester.pumpAndSettle();
    expect(tester.widget<GptMarkdown>(find.byType(GptMarkdown)).data, body);
    final narrowParagraph = tester.renderObject<RenderParagraph>(
      find.byWidgetPredicate(
        (widget) =>
            widget is RichText &&
            widget.text.toPlainText().contains(appendedText),
      ),
    );
    final narrowParagraphText = narrowParagraph.text.toPlainText();
    final narrowLines = narrowParagraph
        .getBoxesForSelection(
          TextSelection(
            baseOffset: 0,
            extentOffset: narrowParagraphText.length,
          ),
        )
        .map((box) => box.top)
        .toSet()
        .length;
    expect(narrowLines, greaterThan(1), reason: '窄宽时同一正文段落实际换行');

    await tester.pumpWidget(surface(640));
    await tester.pumpAndSettle();
    final wideParagraph = tester.renderObject<RenderParagraph>(
      find.byWidgetPredicate(
        (widget) =>
            widget is RichText &&
            widget.text.toPlainText().contains(appendedText),
      ),
    );
    final wideParagraphText = wideParagraph.text.toPlainText();
    final wideLines = wideParagraph
        .getBoxesForSelection(
          TextSelection(baseOffset: 0, extentOffset: wideParagraphText.length),
        )
        .map((box) => box.top)
        .toSet()
        .length;
    expect(wideLines, lessThan(narrowLines), reason: '同一最终正文段落加宽后实际减少折行');
    expect(
      tester.widget<TimelineMarkdown>(find.byType(TimelineMarkdown)).text,
      body,
      reason: '软换行不改写正文源文',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('Timeline Markdown 长链接、行内代码、代码块和表格在窄列折行且保留原文', (tester) async {
    final token = 'LongUnbrokenValue' * 10;
    final code = '  final value = "$token";\n  print(value);';
    final markdown =
        '# 标题\n\n'
        '**强调文字**\n\n'
        '[$token](https://fixture.invalid/readme)\n\n'
        '`$token`\n\n'
        '```dart\n$code\n```\n\n'
        '| 第一列 | 第二列 |\n'
        '| --- | --- |\n'
        '| `$token` | [$token](https://fixture.invalid/readme) |\n';

    Widget surface(double width, String text) => host(
      Center(
        child: SizedBox(
          width: width,
          child: SingleChildScrollView(
            child: DefaultTextStyle.merge(
              softWrap: false,
              child: TimelineMarkdown(
                id: 'rich-body',
                text: text,
                onLink: (_) => fail('未点击链接不应启动外部动作'),
                isSafeLink: (_) => true,
                imageBuilder: (_, _) => throw StateError('没有图片'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpWidget(surface(320, markdown));
    await tester.pumpAndSettle();
    expect(find.text('强调文字', findRichText: true), findsOneWidget);
    expect(find.text('第二列', findRichText: true), findsOneWidget);
    expect(find.byType(StudioCodeBlock), findsOneWidget);
    expect(
      tester.widget<SelectableText>(find.byType(SelectableText)).data,
      code,
      reason: '代码块保留原始字符、缩进和换行',
    );
    expect(tester.widget<GptMarkdown>(find.byType(GptMarkdown)).data, markdown);

    final narrowHeight = tester.getSize(find.byType(TimelineMarkdown)).height;
    for (final element
        in find
            .descendant(
              of: find.byType(TimelineMarkdown),
              matching: find.byWidgetPredicate((widget) => widget is RichText),
            )
            .evaluate()) {
      final paragraph = element.renderObject! as RenderParagraph;
      final text = paragraph.text.toPlainText();
      expect(paragraph.didExceedMaxLines, isFalse);
      for (final box in paragraph.getBoxesForSelection(
        TextSelection(baseOffset: 0, extentOffset: text.length),
      )) {
        expect(box.right, lessThanOrEqualTo(paragraph.size.width + .5));
      }
    }
    final codeRender = tester
        .state<EditableTextState>(
          find.descendant(
            of: find.byType(SelectableText),
            matching: find.byType(EditableText),
          ),
        )
        .renderEditable;
    expect(
      codeRender
          .getBoxesForSelection(
            TextSelection(baseOffset: 0, extentOffset: code.length),
          )
          .map((box) => box.top)
          .toSet()
          .length,
      greaterThan(1),
      reason: '代码必须真实折行，不是横向滚动或裁剪',
    );
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(surface(640, markdown));
    await tester.pumpAndSettle();
    expect(
      tester.getSize(find.byType(TimelineMarkdown)).height,
      lessThan(narrowHeight),
    );

    await tester.pumpWidget(surface(320, token));
    await tester.pumpAndSettle();
    final plain = tester.renderObject<RenderParagraph>(find.byType(RichText));
    expect(
      plain
          .getBoxesForSelection(
            TextSelection(baseOffset: 0, extentOffset: token.length),
          )
          .map((box) => box.top)
          .toSet()
          .length,
      greaterThan(1),
    );
    expect(plain.text.toPlainText(), token);
    expect(tester.takeException(), isNull);
  });

  testWidgets('只有真实用户滚动离开底端才进入 History，改窗不误判', (tester) async {
    final items = [
      for (var index = 0; index < 40; index++)
        textItem('item-$index', appendSeq: index + 1, body: '第 $index 段正文' * 4),
    ];
    final lease = await leaseFor(
      tester,
      items: items,
      before: 'cursor',
      hasOlder: true,
    );
    var enteredHistory = 0;
    await tester.pumpWidget(
      host(
        componentTimeline(
          threadId: 'thread',
          view: viewState(hasOlder: true),
          lease: lease,
          onLoadOlder: () async {},
          onRetryOlder: () async {},
          onReturnLive: () async {},
          onEnterHistory: () => enteredHistory += 1,
          onRetryConnection: () async {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 改窗只有布局修正，没有读者意图。
    await tester.binding.setSurfaceSize(const Size(700, 600));
    await tester.pumpAndSettle();
    expect(enteredHistory, 0, reason: 'resize 不是阅读意图');
    await tester.binding.setSurfaceSize(const Size(900, 700));
    await tester.pumpAndSettle();

    // 真实拖动离开 offset 0。
    await tester.drag(
      find.byType(ChatAnimatedListReversed),
      const Offset(0, 240),
    );
    await tester.pumpAndSettle();
    expect(enteredHistory, greaterThan(0));
    expect(lease.mode, TimelineDisplayMode.live, reason: '意图由 owner 改变模式');
  });

  testWidgets('短内容自动加载更早，失败保留内容并可重试', (tester) async {
    final lease = await leaseFor(
      tester,
      items: [textItem('only', appendSeq: 1)],
    );
    var loads = 0;
    var retries = 0;
    final page = Completer<void>();
    await tester.pumpWidget(
      host(
        componentTimeline(
          threadId: 'thread',
          view: viewState(hasOlder: true),
          lease: lease,
          onLoadOlder: () async {
            loads += 1;
            await page.future;
          },
          onRetryOlder: () async {
            retries += 1;
          },
          onReturnLive: () async {},
          onEnterHistory: () {},
          onRetryConnection: () async {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(loads, 1);
    expect(
      find.byKey(
        StudioDriverKeys.timelineRow(lease.presentationFor('only')!.id),
      ),
      findsOneWidget,
    );

    // 分页失败：内容仍在，入口变成可重试。
    await tester.pumpWidget(
      host(
        componentTimeline(
          threadId: 'thread',
          view: viewState(hasOlder: true, olderError: StateError('boom')),
          lease: lease,
          onLoadOlder: () async {
            loads += 1;
          },
          onRetryOlder: () async {
            retries += 1;
          },
          onReturnLive: () async {},
          onEnterHistory: () {},
          onRetryConnection: () async {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    page.complete();
    await tester.pumpAndSettle();
    expect(loads, 1, reason: '失败不能由布局或重建自动重试');
    expect(
      find.byKey(
        StudioDriverKeys.timelineRow(lease.presentationFor('only')!.id),
      ),
      findsOneWidget,
    );
    await tester.tap(find.byKey(StudioDriverKeys.timelineRetryOlder));
    await tester.pumpAndSettle();
    expect(retries, 1);
  });

  testWidgets('空基线后首条消息通过原生列表立即显示', (tester) async {
    final lease = await leaseFor(tester, items: []);
    await tester.pumpWidget(
      host(
        componentTimeline(
          threadId: 'thread',
          view: viewState(),
          lease: lease,
          onLoadOlder: () async {},
          onRetryOlder: () async {},
          onReturnLive: () async {},
          onEnterHistory: () {},
          onRetryConnection: () async {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    await _appendCompleted(tester, lease, [
      textItem('first-live', appendSeq: 1),
    ]);
    await tester.pumpAndSettle();
    expect(
      find.byKey(
        StudioDriverKeys.timelineRow(lease.presentationFor('first-live')!.id),
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('短内容在途分页结束后，同游标 ready 重建可重新受理', (tester) async {
    final lease = await leaseFor(
      tester,
      items: [textItem('only', appendSeq: 1)],
      before: 'cursor',
      hasOlder: true,
    );
    var loads = 0;
    final firstPage = Completer<void>();
    Future<void> render(TimelineSessionViewState view) async {
      await tester.pumpWidget(
        host(
          componentTimeline(
            threadId: 'thread',
            view: view,
            lease: lease,
            onLoadOlder: () async {
              loads++;
              if (loads == 1) await firstPage.future;
            },
            onRetryOlder: () async {},
            onReturnLive: () async {},
            onEnterHistory: () {},
            onRetryConnection: () async {},
          ),
        ),
      );
      await tester.pump();
    }

    final ready = viewState(mode: TimelineDisplayMode.history, hasOlder: true);
    await render(ready);
    await tester.pumpAndSettle();
    expect(loads, 1);
    // This View-only gate ends normally. Rebuilding ready must re-admit its
    // viewport demand; real SDK scope cancellation is covered below.
    firstPage.complete();
    await tester.pump();
    await render(ready.copyWith());
    await tester.pumpAndSettle();
    expect(loads, 2, reason: '在途结束后 ready 重建应重新受理同一页的视口需求');
  });

  testWidgets('窗口扩大后按实际视口补页，resize 不改变阅读模式', (tester) async {
    await tester.binding.setSurfaceSize(const Size(900, 300));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final lease = await leaseFor(
      tester,
      items: [
        for (var i = 0; i < 12; i++) textItem('row-$i', appendSeq: i + 1),
      ],
      before: 'cursor',
      hasOlder: true,
    );
    var loads = 0;
    var histories = 0;
    final page = Completer<void>();
    await tester.pumpWidget(
      host(
        componentTimeline(
          threadId: 'thread',
          view: viewState(hasOlder: true),
          lease: lease,
          onLoadOlder: () async {
            loads++;
            await page.future;
          },
          onRetryOlder: () async {},
          onReturnLive: () async {},
          onEnterHistory: () {
            histories++;
          },
          onRetryConnection: () async {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(lease.scrollController.position.maxScrollExtent, greaterThan(0));
    expect(loads, 0);
    await tester.binding.setSurfaceSize(const Size(900, 2600));
    await tester.pumpAndSettle();
    expect(loads, 1);
    expect(histories, 0);
    expect(lease.scrollController.position.pixels, closeTo(0, 0.5));
    await tester.binding.setSurfaceSize(const Size(900, 2500));
    await tester.pumpAndSettle();
    expect(loads, 1, reason: '反复几何通知共享同一个在途需求');
    await tester.pumpWidget(host(const SizedBox.shrink()));
    page.complete();
    await tester.pump();
  });

  testWidgets('分页只补充折叠组而高度不变时继续检查推进后的游标', (tester) async {
    final (client, owner, transport) = await _openDetailSession(
      tester,
      baseline: componentBaseline(
        [toolItem('new-tool', appendSeq: 100, arguments: '{}')],
        before: 'cursor',
        hasOlder: true,
      ),
    );
    await tester.pumpWidget(
      host(
        const TimelineConnector(threadId: 'thread'),
        client: client,
        owner: owner,
      ),
    );
    await pumpClientFuture(
      tester,
      transport.pageEntered(1),
      'first viewport page',
    );
    expect(
      transport.pageCalls.single.before,
      const ConversationQueryCursor('cursor'),
    );
    transport.pageCalls[0].reply.complete(
      ConversationPage(
        threadId: 'thread',
        timelineEpoch: 'component-epoch',
        items: [toolItem('older-tool', appendSeq: 99, arguments: '{}')],
        before: const ConversationQueryCursor('next'),
        hasOlder: true,
      ),
    );
    await pumpClientFuture(
      tester,
      transport.pageEntered(2),
      'collapsed group requests advancing page',
    );
    expect(
      transport.pageCalls[1].before,
      const ConversationQueryCursor('next'),
    );
    transport.pageCalls[1].reply.complete(
      ConversationPage(
        threadId: 'thread',
        timelineEpoch: 'component-epoch',
        items: [textItem('old-text', appendSeq: 98, body: '历史正文\n' * 120)],
        before: null,
        hasOlder: false,
      ),
    );
    await pumpClientUntil(
      tester,
      () => owner.source.value?.hasOlder == false,
      'older page committed',
    );
    await tester.pumpAndSettle();
    final lease = owner.lease('thread')!;
    expect(transport.pageCalls, hasLength(2));
    expect(lease.loadedCount, 3);
    expect(lease.completedCursor?.appendSeq, 100, reason: '分页不推进完成 cursor');
    expect(lease.scrollController.position.maxScrollExtent, greaterThan(0));
    expect(tester.takeException(), isNull);
  });

  testWidgets('History 回到最新沿用展示窗口和订阅，完成追加仍可见', (tester) async {
    final (client, owner, transport) = await _openDetailSession(
      tester,
      baseline: componentBaseline([
        textItem('only', appendSeq: 1, body: '已完成的长正文\n' * 80),
      ]),
    );
    final lease = owner.lease('thread')!;
    _fixtures[lease] = (owner, transport);
    await owner.dispatch('thread', const TimelineEnterHistory());
    await tester.pumpWidget(
      host(
        const TimelineConnector(threadId: 'thread'),
        client: client,
        owner: owner,
      ),
    );
    await tester.pumpAndSettle();
    await _appendCompleted(tester, lease, [textItem('new', appendSeq: 2)]);
    await tester.pumpAndSettle();
    await tester.drag(
      find.byKey(StudioDriverKeys.timeline),
      const Offset(0, 280),
    );
    await tester.pumpAndSettle();
    expect(lease.scrollController.position.pixels, greaterThan(200));
    expect(find.textContaining('有新输出'), findsOneWidget);
    await tester.tap(find.byKey(StudioDriverKeys.timelineReturnLive));
    await tester.pumpAndSettle();
    expect(owner.source.value?.mode, TimelineDisplayMode.live);
    expect(owner.source.value?.hasNewOutput, isFalse);
    expect(owner.lease('thread'), same(lease));
    expect(lease.scrollController.position.pixels, closeTo(0, 0.5));
    expect(
      lease.scrollController.position.extentBefore.abs(),
      lessThanOrEqualTo(1),
    );
    expect(lease.loadedCount, 2);
    expect(lease.completedCursor?.appendSeq, 2);
    expect(
      find.byKey(
        StudioDriverKeys.timelineRow(lease.presentationFor('new')!.id),
      ),
      findsOneWidget,
    );
    expect(transport.openCalls, 1);
    expect(transport.readerOpens, 0);
    expect(transport.queryAdmissions, 0);
  });

  testWidgets('详情查看器按字段打开、可关闭，且不改动历史行预览', (tester) async {
    final lease = await leaseFor(
      tester,
      items: [textItem('big', appendSeq: 1, body: '预览正文', totalBytes: 126)],
    );
    await tester.pumpWidget(
      host(
        componentTimeline(
          threadId: 'thread',
          view: viewState(),
          lease: lease,
          onLoadOlder: () async {},
          onRetryOlder: () async {},
          onReturnLive: () async {},
          onEnterHistory: () {},
          onRetryConnection: () async {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    final open = find.byKey(StudioDriverKeys.timelineDetailOpen('big', 'text'));
    expect(open, findsOneWidget);
    await tester.tap(open);
    await pumpClientUntil(
      tester,
      () => _fixtures[lease]!.$2.detailCalls.isNotEmpty,
      'detail query admitted',
    );
    _fixtures[lease]!.$2.detailCalls.single.reply.completeError(
      StateError('detail unavailable'),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(StudioDriverKeys.timelineDetailDialog), findsOneWidget);
    // 独立 reader 读取失败：查看器显示可重试错误，而不是伪造全文。
    expect(find.byKey(StudioDriverKeys.timelineDetailRetry), findsOneWidget);
    await tester.tap(find.byKey(StudioDriverKeys.timelineDetailClose));
    await tester.pumpAndSettle();
    expect(find.byKey(StudioDriverKeys.timelineDetailDialog), findsNothing);
    expect(
      find.byKey(
        StudioDriverKeys.timelineRow(lease.presentationFor('big')!.id),
      ),
      findsOneWidget,
    );
  });

  // ---- B1 键盘 / 滚动条轨道：真实阅读意图 --------------------------------------

  List<ConversationItem> longHistory({int count = 120}) => [
    for (var index = 0; index < count; index++)
      textItem('item-$index', appendSeq: index + 1, body: '第 $index 段正文' * 4),
  ];

  testWidgets('键盘 PageUp 是真实阅读意图，改窗与完成追加不是', (tester) async {
    final lease = await leaseFor(
      tester,
      items: longHistory(),
      before: 'cursor',
      hasOlder: true,
    );
    var enteredHistory = 0;
    var olderLoads = 0;
    await tester.pumpWidget(
      host(
        componentTimeline(
          threadId: 'thread',
          view: viewState(hasOlder: true),
          lease: lease,
          onLoadOlder: () async {
            olderLoads++;
          },
          onRetryOlder: () async {},
          onReturnLive: () async {},
          onEnterHistory: () => enteredHistory += 1,
          onRetryConnection: () async {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 改窗只有布局修正：不是阅读意图。
    await tester.binding.setSurfaceSize(const Size(720, 620));
    await tester.pumpAndSettle();
    expect(enteredHistory, 0, reason: 'resize 不是阅读意图');
    await tester.binding.setSurfaceSize(const Size(900, 700));
    await tester.pumpAndSettle();
    expect(enteredHistory, 0);

    expect(lease.controller.messages.last, isA<TextMessage>());
    await _appendCompleted(tester, lease, [
      componentText('item-120', appendSeq: 121, body: '完成新增第一行\n第二行'),
    ]);
    await tester.pumpAndSettle();
    expect(enteredHistory, 0, reason: '真实完成追加的高度增长不是阅读意图');

    // 键盘：先让焦点落在正文（真实用户路径：点选正文后再翻页），再按 PageUp。
    // 鼠标点选正文：官方 SelectionArea 在鼠标按下时请求焦点，读历史用键盘时焦点在它上面。
    final visibleBody = find.byKey(
      StudioDriverKeys.timelineRow(lease.presentationFor('item-119')!.id),
    );
    expect(visibleBody, findsOneWidget);
    await tester.tap(visibleBody, kind: PointerDeviceKind.mouse);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.pageUp);
    await tester.pumpAndSettle();
    expect(
      enteredHistory,
      greaterThan(0),
      reason: 'PageUp 走 ScrollAction，必须登记为真实用户意图',
    );
    final afterPageUp = lease.scrollController.position.pixels;
    expect(afterPageUp, greaterThan(0.5));

    // PageDown 同属 ScrollIntent：不能被吞掉，必须由 Flutter 原生动作滚回（反向列表
    // offset 0 即底端，所以 PageDown 的方向是回到 0，而不是离开底端进 History）。
    await tester.sendKeyEvent(LogicalKeyboardKey.pageDown);
    await tester.pumpAndSettle();
    expect(
      lease.scrollController.position.pixels,
      lessThan(afterPageUp),
      reason: 'PageDown 必须真实滚动（未被 app 吞掉或改倍率）',
    );
    final position = lease.scrollController.position;
    for (
      var page = 0;
      page < 32 && position.extentAfter > position.viewportDimension * 1.8;
      page++
    ) {
      await tester.sendKeyEvent(LogicalKeyboardKey.pageUp);
      await tester.pumpAndSettle();
    }
    expect(position.extentAfter, greaterThan(position.viewportDimension));
    expect(
      position.extentAfter,
      lessThanOrEqualTo(position.viewportDimension * 1.8),
    );
    final beforeThreshold = olderLoads;
    await tester.sendKeyEvent(LogicalKeyboardKey.pageUp);
    // Observe the real multi-frame ScrollAction animation, not just its last frame.
    for (var frame = 0; frame < 8; frame++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    await tester.pumpAndSettle();
    expect(position.extentAfter, lessThan(position.viewportDimension));
    expect(
      olderLoads,
      greaterThan(beforeThreshold),
      reason: '同一次键盘滚动动画跨入一屏范围就预取，无需再按一次',
    );
  });

  testWidgets('滚动条轨道点击分页进入 History', (tester) async {
    final lease = await leaseFor(
      tester,
      items: longHistory(),
      before: 'cursor',
      hasOlder: true,
    );
    var enteredHistory = 0;
    await tester.pumpWidget(
      host(
        componentTimeline(
          threadId: 'thread',
          view: viewState(hasOlder: true),
          lease: lease,
          onLoadOlder: () async {},
          onRetryOlder: () async {},
          onReturnLive: () async {},
          onEnterHistory: () => enteredHistory += 1,
          onRetryConnection: () async {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    final rect = tester.getRect(find.byKey(StudioDriverKeys.timeline));
    // 原生悬停唤回淡出的滚动条，再点击轨道（顶端不在底部 thumb 内）。
    final trackPoint = Offset(rect.right - 2, rect.top + 12);
    final mouse = TestPointer(1, PointerDeviceKind.mouse);
    await tester.sendEventToBinding(mouse.hover(trackPoint));
    await tester.pumpAndSettle();
    await tester.tapAt(trackPoint, kind: PointerDeviceKind.mouse);
    await tester.pumpAndSettle();
    expect(enteredHistory, greaterThan(0), reason: '轨道点击是真实用户意图');
    expect(lease.scrollController.position.pixels, greaterThan(0.5));
    await tester.sendEventToBinding(mouse.removePointer());
  });

  testWidgets('详情字段 token 由唯一 formatter 给出且不同问答 part 不撞', (tester) async {
    // 独立构造的同值字段必须得到同一 token；不同问答 part 必须不同。
    expect(
      StudioDriverKeyValues.timelineDetailField(const ThreadTextFieldView()),
      StudioDriverKeyValues.timelineDetailField(const ThreadTextFieldView()),
    );
    expect(
      StudioDriverKeyValues.timelineDetailField(
        const ThreadToolUserInputFieldView(
          questionIndex: 0,
          part: ThreadUserInputHeaderFieldPartView(),
        ),
      ),
      isNot(
        StudioDriverKeyValues.timelineDetailField(
          const ThreadToolUserInputFieldView(
            questionIndex: 0,
            part: ThreadUserInputAnswerFieldPartView(0),
          ),
        ),
      ),
    );
    expect(
      StudioDriverKeyValues.timelineDetailField(
        const ThreadToolUserInputFieldView(
          questionIndex: 1,
          part: ThreadUserInputQuestionFieldPartView(),
        ),
      ),
      'user-input-1-question',
    );

    // 视图上的按钮 key 与快照 token 同源。
    final lease = await leaseFor(
      tester,
      items: [textItem('big', appendSeq: 1, body: '预览', totalBytes: 46)],
    );
    await tester.pumpWidget(
      host(
        componentTimeline(
          threadId: 'thread',
          view: viewState(),
          lease: lease,
          onLoadOlder: () async {},
          onRetryOlder: () async {},
          onReturnLive: () async {},
          onEnterHistory: () {},
          onRetryConnection: () async {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(
        StudioDriverKeys.timelineDetailOpen(
          'big',
          StudioDriverKeyValues.timelineDetailField(
            const ThreadTextFieldView(),
          ),
        ),
      ),
      findsOneWidget,
    );
  });

  // ---- B4 详情查看器：活动 scope、重试不重拼、退役即终态 --------------------------

  group('B4 详情查看器', () {
    testWidgets('详情独立 reader 不随 feed 重连失活，epoch reset 后终态并真实换绑', (
      tester,
    ) async {
      final (client, owner, transport) = await _openDetailSession(tester);
      final lease = owner.lease('thread')!;
      await tester.pumpWidget(
        host(
          componentTimeline(
            threadId: 'thread',
            view: owner.source.value!,
            lease: lease,
            onLoadOlder: () async {},
            onRetryOlder: () async {},
            onReturnLive: () async {},
            onEnterHistory: () {},
            onRetryConnection: () {},
          ),
          client: client,
          owner: owner,
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(
          StudioDriverKeys.timelineDetailOpen(
            'big',
            StudioDriverKeyValues.timelineDetailField(
              const ThreadTextFieldView(),
            ),
          ),
        ),
      );
      await pumpClientUntil(
        tester,
        () => transport.detailCalls.length == 1,
        'first detail admitted',
      );
      expect(
        transport.detailCalls.single.query.timelineEpoch,
        lease.timelineEpoch,
      );
      expect(transport.detailCalls.single.query.continuation, isNull);
      transport.detailCalls.single.reply.complete(_chunk(continuation: 'c1'));
      await pumpClientUntil(
        tester,
        () => transport.detailCalls.length == 2,
        'continuation admitted',
      );
      final text = find.byKey(StudioDriverKeys.timelineDetailText);
      expect(tester.widget<SelectableText>(text).data, '甲🐱\n');
      expect(
        transport.detailCalls[1].query.continuation,
        const ConversationQueryCursor('c1'),
      );
      final viewer = tester
          .widget<TimelineDetailConnector>(find.byType(TimelineDetailConnector))
          .owner;
      expect(viewer.canCopy, isFalse);
      transport.holdNextInitial = true;
      client.conversations.session('thread').content.refresh();
      await pumpClientFuture(
        tester,
        transport.opened(2),
        'replacement feed open',
      );
      transport.detailCalls[1].reply.complete(_chunk(text: '乙\r\n'));
      await pumpClientUntil(
        tester,
        () => viewer.state.complete,
        'reader completed while feed waits',
      );
      expect(tester.widget<SelectableText>(text).data, '甲🐱\n乙\r\n');
      expect(viewer.canCopy, isTrue);
      expect(owner.lease('thread'), same(lease));
      expect(transport.readerOpens, 1, reason: '重连不重开独立 reader');
      transport.baseline = componentBaseline([
        componentText('replacement', appendSeq: 1),
      ], timelineEpoch: 'replacement-epoch');
      transport.releaseInitial();
      await pumpClientUntil(
        tester,
        () => owner.lease('thread') != lease,
        'explicit epoch reset',
      );
      final replacement = owner.lease('thread')!;
      expect(lease.isRetired, isTrue);
      expect(lease.isMounted, isTrue, reason: '旧纯 View 尚未重建');
      expect(lease.isReleased, isFalse);
      await tester.pumpWidget(
        host(
          componentTimeline(
            threadId: 'thread',
            view: owner.source.value!,
            lease: replacement,
            onLoadOlder: () async {},
            onRetryOlder: () async {},
            onReturnLive: () async {},
            onEnterHistory: () {},
            onRetryConnection: () {},
          ),
          client: client,
          owner: owner,
        ),
      );
      await pumpClientFuture(
        tester,
        lease.released,
        'old Chat subtree and reader joined',
      );
      await _pumpFrames(tester);
      expect(lease.isMounted, isFalse);
      expect(replacement.isMounted, isTrue);
      expect(
        find.byKey(StudioDriverKeys.timelineDetailTerminal),
        findsOneWidget,
      );
      expect(find.byKey(StudioDriverKeys.timelineDetailRetry), findsNothing);
      expect(tester.widget<SelectableText>(text).data, '');
      expect(viewer.canCopy, isFalse);
      expect(transport.detailCalls, hasLength(2));
      expect(transport.readers.single.closed, isTrue);
      await _unmountTimeline(tester);
    });
  });

  testWidgets('关闭在途读取：停新块、await 自己已受理读取后才离开', (tester) async {
    final (client, owner, transport) = await _openDetailSession(tester);
    final deadline = DateTime.now().add(const Duration(seconds: 5));
    final lease = owner.lease('thread')!;
    final first = transport;
    final queriesBefore = client.budget.used(ResourceKind.pendingOperation);

    await tester.pumpWidget(
      host(
        componentTimeline(
          threadId: 'thread',
          view: owner.source.value!,
          lease: lease,
          onLoadOlder: () async {},
          onRetryOlder: () async {},
          onReturnLive: () async {},
          onEnterHistory: () {},
          onRetryConnection: () async {},
        ),
      ),
    );
    await tester.pump();
    await tester.tap(
      find.byKey(
        StudioDriverKeys.timelineDetailOpen(
          'big',
          StudioDriverKeyValues.timelineDetailField(
            const ThreadTextFieldView(),
          ),
        ),
      ),
    );
    await _pumpFrames(tester);
    expect(first.detailCalls, hasLength(1));
    expect(
      client.budget.used(ResourceKind.pendingOperation),
      queriesBefore + 2,
      reason: '真实 SDK scope 同时持有 reader 与已受理读取的 permit',
    );

    // 读取仍在途：点关闭必须先等它真的退出，不能同步 pop 出假 ACK。
    await tester.tap(find.byKey(StudioDriverKeys.timelineDetailClose));
    await _pumpFrames(tester);
    expect(
      find.byKey(StudioDriverKeys.timelineDetailDialog),
      findsOneWidget,
      reason: '已受理读取未退出前不得关闭',
    );
    expect(first.detailCalls, hasLength(1), reason: '停止后续块');
    expect(
      client.budget.used(ResourceKind.pendingOperation),
      queriesBefore + 2,
      reason: '关闭请求不能提前释放尚未退出的读取',
    );

    // 底层读取退出后，关闭完成。
    first.detailCalls.single.reply.complete(_chunk(continuation: 'c1'));
    // 退出等待结束、route 退场动画走完后查看器才真正离开树。
    await _pumpFrames(tester, frames: 16);
    expect(find.byKey(StudioDriverKeys.timelineDetailDialog), findsNothing);
    expect(first.detailCalls, hasLength(1), reason: '关闭后不再发新块');
    expect(client.budget.used(ResourceKind.pendingOperation), queriesBefore);
    expect(first.readers.single.closed, isTrue);
    expect(first.connections.single.closed, isFalse, reason: '详情关闭不关闭共享 feed');

    await _unmountTimeline(tester);
    await _pumpFrames(tester);
    await _closeDetailSession(tester, owner, client, deadline);
    expect(lease.isReleased, isTrue);
    expect(first.connections.single.closed, isTrue);
    expect(first.connections.single.closeCalls, 1);
    expect(client.budget.usage, isEmpty);
    await _pumpFrames(tester, frames: 2);
  });

  testWidgets('同 lease 独立详情重试成功续读，不重字、可复制且不重开 feed', (tester) async {
    final (client, owner, transport) = await _openDetailSession(tester);
    final deadline = DateTime.now().add(const Duration(seconds: 5));
    final lease = owner.lease('thread')!;
    final first = transport;
    final generation = lease.generation;

    await tester.pumpWidget(
      host(
        componentTimeline(
          threadId: 'thread',
          view: owner.source.value!,
          lease: lease,
          onLoadOlder: () async {},
          onRetryOlder: () async {},
          onReturnLive: () async {},
          onEnterHistory: () {},
          onRetryConnection: () async {},
        ),
      ),
    );
    await tester.pump();
    await tester.tap(
      find.byKey(
        StudioDriverKeys.timelineDetailOpen(
          'big',
          StudioDriverKeyValues.timelineDetailField(
            const ThreadTextFieldView(),
          ),
        ),
      ),
    );
    await _pumpFrames(tester);
    first.detailCalls.single.reply.complete(_chunk(continuation: 'c1'));
    await _pumpFrames(tester);
    first.detailCalls[1].reply.completeError(
      StateError('temporary detail read failure'),
    );
    await _pumpFrames(tester);
    expect(find.byKey(StudioDriverKeys.timelineDetailRetry), findsOneWidget);

    // A transient detail failure does not retire its independent scope or feed.
    await tester.tap(find.byKey(StudioDriverKeys.timelineDetailRetry));
    await _pumpFrames(tester);
    final second = transport;
    expect(second.detailCalls, hasLength(3), reason: '重试实际受理 continuation');
    expect(
      second.detailCalls.last.query.continuation,
      const ConversationQueryCursor('c1'),
    );
    expect(second.detailCalls.last.query.timelineEpoch, 'component-epoch');
    second.detailCalls.last.reply.complete(_chunk(text: '乙\r\n'));
    await _pumpFrames(tester);

    final text = find.byKey(StudioDriverKeys.timelineDetailText);
    expect(tester.widget<SelectableText>(text).data, '甲🐱\n乙\r\n');
    expect(
      tester
          .widget<IconButton>(find.byKey(StudioDriverKeys.timelineDetailCopy))
          .onPressed,
      isNotNull,
      reason: '完整读完后允许复制全文',
    );
    // S4：真实点击复制，平台剪贴板实际写入的就是逐字拼接的完整正文。
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map<Object?, Object?>)['text'] as String?;
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    await tester.tap(find.byKey(StudioDriverKeys.timelineDetailCopy));
    await _pumpFrames(tester);
    expect(copied, '甲🐱\n乙\r\n', reason: '复制内容必须等于逐块拼接的真实正文');
    expect(lease.generation, generation, reason: '同 lease 重试不换代');
    expect(first.detailCalls, hasLength(3), reason: '真实 reader 收到三次请求');

    expect(owner.lease('thread'), same(lease));
    expect(transport.openCalls, 1);
    expect(transport.readerOpens, 1);
    await _unmountTimeline(tester);
    await _pumpFrames(tester);
    await _closeDetailSession(tester, owner, client, deadline);
    await _pumpFrames(tester, frames: 2);
  });

  // ---- R1 typed 确定失效：同一冻结引用重试无意义 -----------------------------------

  for (final code in const <StudioFailureCode>[
    StudioFailureCode.conflict,
    StudioFailureCode.notFound,
  ]) {
    testWidgets('SDK 明确 ${code.name} 时查看器进入终态：清正文、无 retry、禁复制', (tester) async {
      final (client, owner, transport) = await _openDetailSession(tester);
      final deadline = DateTime.now().add(const Duration(seconds: 5));
      final lease = owner.lease('thread')!;
      final connection = transport;

      await tester.pumpWidget(
        host(
          componentTimeline(
            threadId: 'thread',
            view: owner.source.value!,
            lease: lease,
            onLoadOlder: () async {},
            onRetryOlder: () async {},
            onReturnLive: () async {},
            onEnterHistory: () {},
            onRetryConnection: () async {},
          ),
        ),
      );
      await tester.pump();
      await tester.tap(
        find.byKey(
          StudioDriverKeys.timelineDetailOpen(
            'big',
            StudioDriverKeyValues.timelineDetailField(
              const ThreadTextFieldView(),
            ),
          ),
        ),
      );
      await _pumpFrames(tester);
      connection.detailCalls.single.reply.complete(_chunk(continuation: 'c1'));
      await _pumpFrames(tester);
      expect(
        tester
            .widget<SelectableText>(
              find.byKey(StudioDriverKeys.timelineDetailText),
            )
            .data,
        '甲🐱\n',
      );

      // 真实 SDK 公开通路：受控 backend 在该冻结引用上返回 typed 失败。
      connection.detailCalls[1].reply.completeError(
        StudioFailure(
          code: code,
          message: 'detail reference is no longer readable',
          retryable: true,
          correlationId: 'synthetic-${code.name}',
        ),
      );
      await _pumpFrames(tester);

      expect(
        find.byKey(StudioDriverKeys.timelineDetailTerminal),
        findsOneWidget,
        reason: '确定失效必须给终态，不能停在通用 error',
      );
      expect(find.byKey(StudioDriverKeys.timelineDetailRetry), findsNothing);
      expect(
        tester
            .widget<SelectableText>(
              find.byKey(StudioDriverKeys.timelineDetailText),
            )
            .data,
        '',
        reason: '终态释放正文缓存',
      );
      expect(
        tester
            .widget<IconButton>(find.byKey(StudioDriverKeys.timelineDetailCopy))
            .onPressed,
        isNull,
      );
      expect(connection.detailCalls, hasLength(2), reason: '终态不得继续发块');

      await _unmountTimeline(tester);
      await _pumpFrames(tester);
      await _closeDetailSession(tester, owner, client, deadline);
      await _pumpFrames(tester, frames: 2);
    });
  }

  // ---- R4 正文选择边界：界面提示不是 canonical 正文 -------------------------------

  /// design/26 §26.8：正文选择只包含所选内容域的文本。详情入口行是界面提示，不属于
  /// canonical 正文，不随跨块选择进入剪贴板；入口的点击、焦点与辅助语义保留。
  testWidgets(
    '跨块全选的实际复制内容只含 canonical 正文，入口行文案不进入剪贴板',
    variant: TargetPlatformVariant.only(TargetPlatform.linux),
    (tester) async {
      final (client, owner, transport) = await _openDetailSession(
        tester,
        baseline: _selectionBaseline(),
      );
      final deadline = DateTime.now().add(const Duration(seconds: 5));
      final lease = owner.lease('thread')!;
      final connection = transport;

      await tester.pumpWidget(
        host(
          componentTimeline(
            threadId: 'thread',
            view: owner.source.value!,
            lease: lease,
            onLoadOlder: () async {},
            onRetryOlder: () async {},
            onReturnLive: () async {},
            onEnterHistory: () {},
            onRetryConnection: () async {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 提示子树当前真实渲染的文案：不是测试自己构造的字符串。
      final notice = find.byKey(StudioDriverKeys.timelineItemBodyNotice('big'));
      expect(notice, findsOneWidget);
      final rows = find.descendant(
        of: notice,
        matching: find.byType(TimelineActivityRow),
      );
      final activityRows = tester
          .widgetList<TimelineActivityRow>(rows)
          .toList();
      expect(activityRows, hasLength(1), reason: '基线只有一个被截断字段，因此只有一行入口');
      final hints = tester
          .widgetList<Text>(
            find.descendant(of: notice, matching: find.byType(Text)),
          )
          .map((widget) => widget.data)
          .whereType<String>()
          .toList();
      expect(hints, hasLength(1), reason: '每字段一行入口文案，不再有截断说明句');
      expect(activityRows.single.label, hints.single, reason: '活动行文案就是唯一入口文案');
      expect(
        tester
            .widget<Text>(
              find.descendant(of: notice, matching: find.byType(Text)).first,
            )
            .maxLines,
        1,
        reason: '入口行只占一行，超出在行内省略',
      );

      // 选择边界不夺走入口：仍可点击、可进入键盘焦点、保留辅助语义标签。
      final open = find.byKey(
        StudioDriverKeys.timelineDetailOpen(
          'big',
          StudioDriverKeyValues.timelineDetailField(
            const ThreadTextFieldView(),
          ),
        ),
      );
      expect(tester.widget<InkWell>(open).onTap, isNotNull);
      await tester.ensureVisible(open);
      final semantics = tester.ensureSemantics();
      await tester.pump();
      // Flutter merges this row with its preview into the tappable node; the
      // complete accessible label and actions still have to remain intact.
      expect(
        tester.getSemantics(open),
        matchesSemantics(
          label: '截断前的preview\n完整正文',
          isFocusable: true,
          hasFocusAction: true,
          hasTapAction: true,
        ),
      );
      semantics.dispose();
      final buttonLabel = tester.element(
        find.descendant(of: open, matching: find.byType(Text)).first,
      );
      Focus.of(buttonLabel).requestFocus();
      await tester.pump();
      expect(
        Focus.of(buttonLabel).hasFocus,
        isTrue,
        reason: '正文选择边界不得移除详情入口的键盘焦点',
      );

      // 平台剪贴板只截获 Flutter 真实复制路径写出的值，不自行写入期望值。
      String? copied;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            copied =
                (call.arguments as Map<Object?, Object?>)['text'] as String?;
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );

      // 真实点击打开查看器；全文接纳与复制、列表预览复制是两个独立信号。
      const fullText = '截断前的preview补足完整内容呀';
      await tester.tap(open);
      await _pumpFrames(tester);
      expect(find.byKey(StudioDriverKeys.timelineDetailDialog), findsOneWidget);
      connection.detailCalls.single.reply.complete(
        _chunk(text: fullText, totalBytes: 40),
      );
      await _pumpFrames(tester);
      expect(
        tester
            .widget<SelectableText>(
              find.byKey(StudioDriverKeys.timelineDetailText),
            )
            .data,
        fullText,
      );
      final detailOwner = tester
          .widget<TimelineDetailConnector>(find.byType(TimelineDetailConnector))
          .owner;
      expect(detailOwner.state.text, fullText);
      expect(detailOwner.state.error, isNull);
      expect(detailOwner.state.complete, isTrue);
      expect(detailOwner.state.loading, isFalse);
      expect(detailOwner.state.terminal, isFalse);
      expect(detailOwner.canCopy, isTrue);
      expect(find.byKey(StudioDriverKeys.timelineDetailRetry), findsNothing);
      expect(find.byKey(StudioDriverKeys.timelineDetailTerminal), findsNothing);
      final detailCopy = find.byKey(StudioDriverKeys.timelineDetailCopy);
      expect(tester.widget<IconButton>(detailCopy).onPressed, isNotNull);
      await tester.tap(detailCopy);
      await _pumpFrames(tester);
      expect(copied, fullText, reason: '40 字节全文经真实详情复制路径原样写入');
      await tester.tap(find.byKey(StudioDriverKeys.timelineDetailClose));
      await _pumpFrames(tester, frames: 16);
      expect(find.byKey(StudioDriverKeys.timelineDetailDialog), findsNothing);

      copied = null;
      final regionFinder = find.byType(SelectableRegion);
      expect(regionFinder, findsOneWidget);
      final region = tester.state<SelectableRegionState>(regionFinder);
      // 跨块全选：与工具栏 Select All / Ctrl+A 同一条公开选择状态通路。
      region.selectAll();
      await tester.pumpAndSettle();
      final copy = region.contextMenuButtonItems.singleWhere(
        (item) => item.type == ContextMenuButtonType.copy,
      );
      copy.onPressed!();
      await _pumpFrames(tester);

      expect(copied, isNotNull, reason: '真实复制路径写入了平台剪贴板');
      // 选区的 plainText 保留按钮内文本的硬换行，这里只做断言侧的空白规范化比较，
      // 不改写生产复制字符串。
      final normalized = copied!.replaceAll(RegExp(r'\s+'), ' ');
      for (final hint in hints) {
        expect(
          normalized,
          isNot(contains(hint)),
          reason: '界面提示不属于 canonical 正文，不得进入剪贴板',
        );
      }
      expect(
        copied,
        '前段canonical正文截断前的preview后段canonical正文',
        reason: '精确等于所选内容域的正文（SDK 顺序拼接、不插分隔）',
      );

      await _unmountTimeline(tester);
      await _pumpFrames(tester);
      await _closeDetailSession(tester, owner, client, deadline);
      await _pumpFrames(tester, frames: 2);
    },
  );

  // ---- 详情入口行：每个被截断字段一行，不额外渲染说明句 ----------------------------

  testWidgets('参数与输出同时被截断时每个字段恰好一行活动行入口', (tester) async {
    final (client, owner, _) = await _openDetailSession(
      tester,
      baseline: _twoFieldBaseline(),
    );
    final deadline = DateTime.now().add(const Duration(seconds: 5));
    final lease = owner.lease('thread')!;

    await tester.pumpWidget(
      host(
        componentTimeline(
          threadId: 'thread',
          view: owner.source.value!,
          lease: lease,
          onLoadOlder: () async {},
          onRetryOlder: () async {},
          onReturnLive: () async {},
          onEnterHistory: () {},
          onRetryConnection: () async {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    // 工具条目属于活动组：展开后成员行与其详情入口才构建。
    final group = lease.presentationFor('tool')!;
    await tester.tap(
      find.byKey(StudioDriverKeys.timelineActivitySummary(group.id)),
    );
    await tester.pumpAndSettle();

    final notice = find.byKey(StudioDriverKeys.timelineItemBodyNotice('tool'));
    expect(notice, findsOneWidget);
    final rows = find.descendant(
      of: notice,
      matching: find.byType(TimelineActivityRow),
    );
    // 基线恰好两个被截断字段：入口行数必须等于字段数，没有额外的说明行。
    expect(rows, findsNWidgets(2), reason: '每个被截断字段一行入口');
    final l10n = AppLocalizations.of(tester.element(rows.first));
    expect(
      tester.widgetList<TimelineActivityRow>(rows).map((row) => row.label),
      [l10n.timelineToolArguments, l10n.timelineToolOutput],
      reason: '行文案是字段领域名，不是截断说明句',
    );
    for (final field in const <ThreadContentFieldView>[
      ThreadToolArgumentsFieldView(),
      ThreadToolResultFieldView(),
    ]) {
      final open = find.byKey(
        StudioDriverKeys.timelineDetailOpen(
          'tool',
          StudioDriverKeyValues.timelineDetailField(field),
        ),
      );
      expect(open, findsOneWidget, reason: '每个被截断字段都有自己的入口');
      expect(tester.widget<InkWell>(open).onTap, isNotNull);
      expect(
        find.descendant(of: open, matching: find.byType(TimelineActivityRow)),
        findsOneWidget,
        reason: '入口就是一行活动行，不另建行样式',
      );
    }

    await _unmountTimeline(tester);
    await _pumpFrames(tester);
    await _closeDetailSession(tester, owner, client, deadline);
    await _pumpFrames(tester, frames: 2);
  });

  // ---- 只读滚动诊断：查询时现场读取当前 controller，不复用通知快照 -----------------

  testWidgets('滚动诊断每次请求读当前 position：拖动中 true，抬手归 false 后立即 false', (
    tester,
  ) async {
    final (client, owner, transport) = await _openDetailSession(
      tester,
      baseline: _longBaseline(),
    );
    final deadline = DateTime.now().add(const Duration(seconds: 5));
    final lease = owner.lease('thread')!;
    await _emitTailAdditions(
      tester,
      owner: owner,
      lease: lease,
      connection: transport.connections.single,
      items: [
        for (var index = 32; index < 40; index++)
          componentText(
            'line-$index',
            appendSeq: index + 1,
            body: '第 $index 段静态正文' * 6,
          ),
      ],
    );
    expect(lease.loadedCount, 40);
    expect(lease.items.map((item) => item.id), [
      for (var index = 0; index < 40; index++) 'line-$index',
    ]);
    // Driver only reads these domains; any account transport use fails closed.
    final accounts = (await tester.runAsync(() async {
      final ports = _UnusedTimelineAccountPorts();
      return AccountDomainResources(
        feed: ports,
        configuration: ports,
        modelPort: ports,
        usagePort: ports,
        acpPort: ports,
        coordinator: client.settingsWrites,
        mutations: client.mutations,
        budget: client.budget,
        owner: 'timeline-driver-accounts',
      );
    }))!;
    addTearDown(() async {
      // Account resources were constructed in the real event zone above.
      final report = await tester.runAsync(
        () => accounts.close(deadline: deadline),
      );
      expect(report!.unresolved, isEmpty);
    });
    bindStudioDriver(
      client,
      timeline: owner,
      accountsRepository: accounts.accounts,
      modelsRepository: accounts.models,
      usageRepository: accounts.usage,
      acpService: accounts.acp,
    );

    await tester.pumpWidget(
      host(
        componentTimeline(
          threadId: 'thread',
          view: owner.source.value!,
          lease: lease,
          onLoadOlder: () async {},
          onRetryOlder: () async {},
          onReturnLive: () async {},
          onEnterHistory: () {},
          onRetryConnection: () async {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    final controller = lease.scrollController;
    final position = controller.position;
    expect(position.maxScrollExtent, greaterThan(200), reason: '静态长内容真实溢出');

    // 静止：诊断等于当前真实几何，不滚动。
    final idle = StudioDriverState.readFacts().timelineScroll;
    expect(idle, isNotNull);
    expect(idle!.threadId, 'thread');
    expect(idle.generation, lease.generation);
    expect(idle.pixels, position.pixels);
    expect(idle.maxScrollExtent, position.maxScrollExtent);
    expect(idle.isScrolling, isFalse);
    expect(idle.isScrolling, position.isScrollingNotifier.value);
    expect(idle.atLiveEdge, isTrue);

    // 真实内容拖动：标准 position 自己进入滚动活动，诊断必须当场为 true。
    final anchor = tester.getCenter(
      find.byKey(
        StudioDriverKeys.timelineRow(lease.presentationFor('line-39')!.id),
      ),
    );
    final gesture = await tester.startGesture(
      anchor,
      kind: PointerDeviceKind.touch,
    );
    await gesture.moveBy(const Offset(0, 40));
    await tester.pump();
    await gesture.moveBy(const Offset(0, 40));
    await tester.pump();
    expect(position.isScrollingNotifier.value, isTrue, reason: '拖动确实在滚动');
    final dragging = StudioDriverState.readFacts().timelineScroll;
    expect(dragging, isNotNull);
    expect(dragging!.isScrolling, isTrue);
    expect(dragging.isScrolling, position.isScrollingNotifier.value);
    expect(dragging.pixels, position.pixels, reason: '诊断读的是同一个 position');
    final pixelsWhileDragging = position.pixels;

    // 抬手：等标准 position 自己结束（真实动画/惯性），不加滚动/改窗/内容增长。
    await gesture.up();
    for (var frame = 0; frame < 240; frame++) {
      if (!position.isScrollingNotifier.value) break;
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(
      position.isScrollingNotifier.value,
      isFalse,
      reason: '标准 position 已经自己结束滚动',
    );
    // 同一帧内立刻读诊断：不依赖后续任何一次滚动通知/几何事件。
    final settled = StudioDriverState.readFacts().timelineScroll;
    expect(settled, isNotNull);
    expect(
      settled!.isScrolling,
      isFalse,
      reason: 'ScrollEnd 通知早于 notifier 提交，缓存会把这里永久留在 true',
    );
    expect(settled.isScrolling, position.isScrollingNotifier.value);
    expect(settled.pixels, position.pixels);
    expect(position.pixels, isNot(0), reason: '确实是从内容里滚出来的位置');
    expect(
      position.pixels,
      greaterThanOrEqualTo(pixelsWhileDragging - 1),
      reason: '抬手后没有再被追加滚动',
    );

    // 再连读两次仍是现读：不是把一次 false 缓成常量。
    final again = StudioDriverState.readFacts().timelineScroll!;
    expect(again.isScrolling, position.isScrollingNotifier.value);
    expect(again.pixels, position.pixels);

    // 真实子树卸载 + 旧代次退役：不返回上一代几何，也不拿别的 Thread 的代次顶替。
    await _unmountTimeline(tester);
    await _pumpFrames(tester);
    await pumpClientFuture(tester, lease.retire(), 'Driver lease retirement');
    await pumpClientFuture(tester, lease.released, 'Driver lease released ACK');
    expect(
      StudioDriverState.readFacts().timelineScroll,
      isNull,
      reason: '退役/无挂载代次不得继续报告上一代几何',
    );
    final ownerReport = await pumpClientFuture(
      tester,
      owner.close(deadline: deadline),
      'Driver timeline owner close',
    );
    expect(ownerReport.unresolved, isEmpty);
    final accountReport = await tester.runAsync(
      () => accounts.close(deadline: deadline),
    );
    expect(accountReport!.unresolved, isEmpty);
    final clientReport = await pumpClientFuture(
      tester,
      client.close(deadline: deadline),
      'Driver client close',
    );
    expect(clientReport.unresolved, isEmpty);
    await _pumpFrames(tester, frames: 2);
  });

  testWidgets('单段思考展开后展示组内概要行，仅含概要时不提供二次展开，含内容时可二次展开', (tester) async {
    for (final (summary, content) in [
      (['**Summary** `evidence`'], ['Full reasoning evidence']),
      (['**Summary** `evidence`'], <String>[]),
      (<String>[], ['Full reasoning evidence']),
      (<String>['  '], <String>[]),
    ]) {
      final lease = await leaseFor(
        tester,
        items: [
          conversationFixture(
            id: 'thinking',
            threadId: 'thread',
            appendSeq: 1,
            descriptor: ConversationThinkingDescriptor(
              outcome: ConversationContentCompleted(
                CompletedThreadContentView(
                  DateTime.utc(2026).add(const Duration(seconds: 3)),
                ),
              ),
            ),
            fields: {
              for (final (chunkIndex, chunk) in summary.indexed)
                ThreadThinkingSummaryFieldView(chunkIndex): chunk,
              for (final (chunkIndex, chunk) in content.indexed)
                ThreadThinkingContentFieldView(chunkIndex): chunk,
            },
          ),
        ],
      );
      await tester.pumpWidget(
        host(
          componentTimeline(
            threadId: 'thread',
            view: viewState(),
            lease: lease,
            onLoadOlder: () async {},
            onRetryOlder: () async {},
            onReturnLive: () async {},
            onEnterHistory: () {},
            onRetryConnection: () async {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      final group = lease.presentationFor('thinking')!;
      final topSummaryFinder = find.byKey(
        StudioDriverKeys.timelineActivitySummary(group.id),
      );
      final topRow = tester.widget<TimelineActivityRow>(
        find.descendant(
          of: topSummaryFinder,
          matching: find.byType(TimelineActivityRow),
        ),
      );
      expect(topRow.icon, isNull, reason: '顶层总折叠行去掉左侧图标');
      expect(topRow.label, 'Thought ended', reason: '完成项没有开始时间，不伪造工作时长');

      await tester.tap(
        find.byKey(StudioDriverKeys.timelineActivitySummary(group.id)),
      );
      await tester.pumpAndSettle();
      final hasContent = content.any((chunk) => chunk.trim().isNotEmpty);
      final innerSummary = find.byKey(
        StudioDriverKeys.timelineActivitySummary('thinking'),
      );
      expect(innerSummary, findsOneWidget);
      expect(
        tester.widget<TimelineActivityRow>(innerSummary).expandable,
        hasContent,
      );
      if (hasContent) {
        await tester.tap(
          find
              .ancestor(of: innerSummary, matching: find.byType(ListTile))
              .first,
        );
        await tester.pumpAndSettle();
      }
      expect(
        find.byKey(const ValueKey('timeline-thinking-content-thinking')),
        hasContent ? findsOneWidget : findsNothing,
      );
      expect(find.text('No reasoning text was provided.'), findsNothing);
      await _unmountTimeline(tester);
      await tester.pumpAndSettle();
      await pumpClientFuture(tester, lease.retire(), 'thinking lease release');
    }
  });

  testWidgets(
    '独立 TimelineActivityGroupBlock 仅接受自有 sealed 消息，不感知轮次并支持持续追加与上层转换',
    (tester) async {
      final timestamp = DateTime.utc(2026);
      final controller = TimelineActivityGroupController(
        id: 'standalone-group',
      );
      addTearDown(controller.dispose);

      // 1. 通过组件自有的 sealed TimelineThinkingGroupMessage 追加首条仅含概要的思考消息（无需传入 threadId/turnId）。
      final replacedFirst = controller.add(
        TimelineThinkingGroupMessage(
          id: 'think-only-summary',
          order: 1,
          createdAt: timestamp,
          completedAt: timestamp.add(const Duration(seconds: 2)),
          summary: '正在设计方案 `step-1`',
        ),
      );
      expect(replacedFirst, isFalse);

      await tester.pumpWidget(
        host(
          Scaffold(body: TimelineActivityGroupBlock(controller: controller)),
        ),
      );
      await tester.pumpAndSettle();

      Finder topSummary() =>
          find.byKey(StudioDriverKeys.timelineActivitySummary(controller.id));
      TimelineActivityRow readTopRow() =>
          tester.widget<TimelineActivityRow>(topSummary());

      expect(readTopRow().icon, isNull);
      expect(readTopRow().label, 'Worked for 2s');

      // 2. 上层调用方通过 TimelineActivityGroupAdapter 将 StudioTimelineItem 转换为组件自有消息并追加。
      final completedToolItem = conversationFixture(
        id: 'tool-1',
        threadId: 'thread',
        appendSeq: 2,
        descriptor: ConversationToolDescriptor(
          invocation: const ConversationToolInvocation(
            toolCallId: 'tool-1',
            name: 'stat_path',
          ),
          state: ConversationToolSucceeded(
            completedAt: timestamp.add(const Duration(seconds: 8)),
            output: ConversationToolOutputDescriptor(attachments: []),
          ),
        ),
        fields: {
          const ThreadToolArgumentsFieldView():
              '{"path":"/workspace/README.md"}',
          const ThreadToolResultFieldView(): 'done',
        },
      );
      final convertedTool = TimelineActivityGroupAdapter.convertItem(
        completedToolItem,
      );
      expect(convertedTool, isA<TimelineActivityConverted>());
      final replacedTool = controller.add(
        (convertedTool as TimelineActivityConverted).message,
      );
      expect(replacedTool, isFalse);
      await tester.pumpAndSettle();
      expect(readTopRow().icon, isNull);
      expect(readTopRow().label, 'Thinking and tools · 1 tools');

      // 3. 展开工作组，验证仅含概要的思考消息不提供二次展开（expandable: false）。
      await tester.tap(
        find.ancestor(of: topSummary(), matching: find.byType(ListTile)).first,
      );
      await tester.pumpAndSettle();
      final innerThinkingSummary = find.byKey(
        StudioDriverKeys.timelineActivitySummary('think-only-summary'),
      );
      expect(innerThinkingSummary, findsOneWidget);
      expect(
        tester.widget<TimelineActivityRow>(innerThinkingSummary).expandable,
        isFalse,
      );
      expect(
        find.byKey(
          const ValueKey('timeline-thinking-summary-think-only-summary'),
        ),
        findsOneWidget,
      );

      // 4. 持续追加含正文的思考消息，验证同 id 幂等更新与含正文思考消息可展开。
      controller.add(
        TimelineThinkingGroupMessage(
          id: 'think-with-content',
          order: 3,
          createdAt: timestamp.add(const Duration(seconds: 8)),
          completedAt: timestamp.add(const Duration(seconds: 10)),
          summary: '正在整理细节',
          content: '完整推理正文',
        ),
      );
      await tester.pumpAndSettle();
      expect(readTopRow().label, 'Thinking and tools · 1 tools');
      final expandableThinkingSummary = find.byKey(
        StudioDriverKeys.timelineActivitySummary('think-with-content'),
      );
      expect(
        tester
            .widget<TimelineActivityRow>(expandableThinkingSummary)
            .expandable,
        isTrue,
      );

      // 5. 上层转换器对组外类型（助手正文、未完成项等）直接拒绝转换，由上层决定结束当前工作组。
      final assistantItem = textItem(
        'assistant-1',
        appendSeq: 4,
        body: 'Answer',
      );
      final rejectedConversion = TimelineActivityGroupAdapter.convertItem(
        assistantItem,
      );
      expect(rejectedConversion, isA<TimelineActivityConversionRejected>());
      expect(
        (rejectedConversion as TimelineActivityConversionRejected).reason,
        TimelineActivityRejectionReason.nonActivityKind,
      );
    },
  );

  testWidgets('只读工具 stat_path 以状态和文件名单行展示，详情只在点击后构建', (tester) async {
    final lease = await leaseFor(
      tester,
      items: [
        toolItem(
          'read-1',
          name: 'stat_path',
          arguments: '{"path":"/workspace/src/target.dart"}',
        ),
      ],
    );
    await tester.pumpWidget(
      host(
        componentTimeline(
          threadId: 'thread',
          view: viewState(),
          lease: lease,
          onLoadOlder: () async {},
          onRetryOlder: () async {},
          onReturnLive: () async {},
          onEnterHistory: () {},
          onRetryConnection: () async {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(
        StudioDriverKeys.timelineActivitySummary(
          lease.presentationFor('read-1')!.id,
        ),
      ),
    );
    await tester.pumpAndSettle();
    final block = find.byKey(StudioDriverKeys.timelineBlock('read-1'));
    final row = find
        .descendant(of: block, matching: find.byType(InkWell))
        .first;
    expect(tester.getSize(row).height, lessThanOrEqualTo(40));
    expect(find.byIcon(Icons.menu_book_outlined), findsOneWidget);
    expect(
      find.textContaining('target.dart', findRichText: true),
      findsOneWidget,
    );
    expect(find.byTooltip('/workspace/src/target.dart'), findsOneWidget);
    final bodies = find.descendant(
      of: block,
      matching: find.byType(StudioCodeBlock),
    );
    expect(bodies, findsNothing, reason: '点击前不得构建工具参数/结果正文');
    await tester.tap(row);
    await tester.pumpAndSettle();
    expect(
      tester.widgetList<StudioCodeBlock>(bodies).map((body) => body.text),
      ['{\n  "path": "/workspace/src/target.dart"\n}', 'ok'],
      reason: '点击后按原文展示参数和结果，不依赖旧私有代码块形状',
    );
    expect(
      find.descendant(of: block, matching: find.byType(TimelineMarkdown)),
      findsNothing,
      reason: '工具参数和结果是原文代码，不经过 Markdown 正文展示器',
    );
    await _unmountTimeline(tester);
    await tester.pumpAndSettle();
    await pumpClientFuture(tester, lease.retire(), 'read-file lease release');
  });

  // ---- S1 图片增量：默认折叠、用户展开语义与引用释放 --------------------------------

  testWidgets('图片组按需读取共享重试，完成追加保持折叠意图，reset 释放图片引用', (tester) async {
    const arguments = '{"path":"/workspace/images/shot.png"}';
    const fullResult = 'ok: tool produced shared image';
    final transport = _ImageTransport(
      failures: 1,
      baseline: componentBaseline([
        imageToolItem(
          'call-a',
          appendSeq: 1,
          name: 'mcp__plot',
          totalResultBytes: utf8.encode(fullResult).length,
        ),
        imageToolItem('call-b', appendSeq: 2),
      ]),
    );
    final (client, owner, _) = await _openDetailSession(
      tester,
      backend: transport,
    );
    final lease = owner.lease('thread')!;
    final connection = transport;
    final pendingBefore = client.budget.used(ResourceKind.pendingOperation);
    final entryA = StudioDriverKeys.toolImageEntryId('call-a', 'att-shared');
    Finder toggleFor(String id) => find.byKey(
      StudioDriverKeys.timelineActivitySummary(lease.presentationFor(id)!.id),
    );
    _fixtures[lease] = (owner, transport);
    await tester.pumpWidget(
      host(
        componentTimeline(
          threadId: 'thread',
          view: owner.source.value!,
          lease: lease,
          onLoadOlder: () async {},
          onRetryOlder: () async {},
          onReturnLive: () async {},
          onEnterHistory: () {},
          onRetryConnection: () async {},
        ),
        client: client,
        owner: owner,
      ),
    );
    await tester.pumpAndSettle();

    // 默认折叠：没有缩略图，也没有任何字节读取（生产不再自动展开）。
    expect(toggleFor('call-a'), findsOneWidget);
    expect(_imageThumbnail('call-a'), findsNothing);
    expect(_imageThumbnail('call-b'), findsNothing);
    expect(transport.reads, isEmpty, reason: '折叠状态不得读取原图');

    // 两个独立完成图片项各自展开；资源缓存仍共享同一附件读取。
    await tester.tap(toggleFor('call-a'));
    await _pumpFrames(tester);
    await tester.pumpAndSettle();
    expect(transport.reads, ['thread:att-shared']);
    await tester.tap(toggleFor('call-b'));
    await _pumpFrames(tester);
    await tester.ensureVisible(_imageRetry('call-b'));
    await tester.pumpAndSettle();
    expect(transport.reads, ['thread:att-shared']);
    expect(_imageRetry('call-a'), findsOneWidget);
    expect(_imageRetry('call-b'), findsOneWidget);
    // One shared retry replaces the failed attempt for BOTH mounted consumers.
    // Revealing the whole first button would evict the second lazy member.
    // Tap its actual visible portion instead, without calling either callback.
    await tester.ensureVisible(_imageRetry('call-a'));
    await tester.pumpAndSettle();
    final imageListA = find.ancestor(
      of: _imageConnector('call-a'),
      matching: find.byType(ListView),
    );
    final visibleRetry = tester
        .getRect(_imageRetry('call-a'))
        .intersect(tester.getRect(imageListA));
    expect(visibleRetry.isEmpty, isFalse);
    await tester.tapAt(visibleRetry.center);
    expect(_imageConnector('call-a'), findsOneWidget);
    expect(_imageConnector('call-b'), findsOneWidget);
    // Native descriptor decoding needs the real event queue. The focus/layout
    // change can also evict the first lazy member; reach it again by scrolling.
    await pumpClientUntil(
      tester,
      () => _imageThumbnail('call-b').evaluate().length == 1,
      'shared-retry second image thumbnail decoded',
    );
    await tester.ensureVisible(_imageConnector('call-a'));
    await tester.pumpAndSettle();
    await pumpClientUntil(
      tester,
      () =>
          _imageThumbnail('call-a').evaluate().length == 1 &&
          _imageThumbnail('call-b').evaluate().length == 1,
      'both shared-retry image thumbnails decoded',
    );
    expect(_imageThumbnail('call-a'), findsOneWidget);
    expect(_imageThumbnail('call-b'), findsOneWidget);
    expect(_imageRetry('call-a'), findsNothing);
    expect(_imageRetry('call-b'), findsNothing);
    expect(transport.reads, ['thread:att-shared', 'thread:att-shared']);
    expect(find.text('/workspace/images/shot.png'), findsNothing);
    await tester.ensureVisible(_imageThumbnail('call-a'));
    await tester.pump();
    await tester.tap(_imageThumbnail('call-a'));
    await tester.pumpAndSettle();
    final imageDialog = find.byKey(StudioDriverKeys.viewImageDialog(entryA));
    expect(imageDialog, findsOneWidget);
    expect(find.text('shot.png'), findsOneWidget);
    expect(transport.reads, hasLength(2), reason: '原图复用共享字节，不新增读取');

    Finder detailAction(ThreadContentFieldView field) => find.descendant(
      of: imageDialog,
      matching: find.byKey(
        StudioDriverKeys.timelineDetailOpen(
          'call-a',
          StudioDriverKeyValues.timelineDetailField(field),
        ),
      ),
    );
    final argumentAction = detailAction(const ThreadToolArgumentsFieldView());
    final resultAction = detailAction(const ThreadToolResultFieldView());
    expect(argumentAction, findsOneWidget);
    expect(resultAction, findsOneWidget);
    expect(tester.widget<TextButton>(argumentAction).onPressed, isNotNull);
    expect(tester.widget<TextButton>(resultAction).onPressed, isNotNull);

    // The complete path is accessible in the typed argument route, not a
    // Flutter-side JSON/path panel. Each viewer owns its production scope.
    final sharedScope = lease.queries!;
    await tester.tap(argumentAction);
    await _pumpFrames(tester);
    final argumentOwner = tester
        .widget<TimelineDetailConnector>(find.byType(TimelineDetailConnector))
        .owner;
    expect(argumentOwner.lease, same(lease));
    expect(argumentOwner.field, const ThreadToolArgumentsFieldView());
    expect(connection.detailCalls, hasLength(1));
    expect(connection.detailCalls[0].itemId, 'call-a');
    expect(
      connection.detailCalls[0].query.field,
      const ThreadToolArgumentsFieldView(),
    );
    expect(connection.detailCalls[0].query.timelineEpoch, 'component-epoch');
    expect(connection.detailCalls[0].query.continuation, isNull);
    connection.detailCalls[0].reply.complete(
      ConversationDetailChunk(
        threadId: 'thread',
        timelineEpoch: 'component-epoch',
        itemId: 'call-a',
        field: const ThreadToolArgumentsFieldView(),
        text: '{"path":"/workspace/images/',
        totalBytes: utf8.encode(arguments).length,
        continuation: const ConversationQueryCursor('path-tail'),
      ),
    );
    await _pumpFrames(tester);
    expect(connection.detailCalls, hasLength(2));
    expect(connection.detailCalls[1].itemId, 'call-a');
    expect(
      connection.detailCalls[1].query.field,
      const ThreadToolArgumentsFieldView(),
    );
    expect(
      connection.detailCalls[1].query.continuation,
      const ConversationQueryCursor('path-tail'),
    );
    connection.detailCalls[1].reply.complete(
      ConversationDetailChunk(
        threadId: 'thread',
        timelineEpoch: 'component-epoch',
        itemId: 'call-a',
        field: const ThreadToolArgumentsFieldView(),
        text: 'shot.png"}',
        totalBytes: utf8.encode(arguments).length,
        continuation: null,
      ),
    );
    await _pumpFrames(tester);
    expect(argumentOwner.state.text, arguments);
    expect(argumentOwner.state.error, isNull);
    expect(argumentOwner.state.complete, isTrue);
    expect(argumentOwner.canCopy, isTrue);
    expect(
      tester
          .widget<SelectableText>(
            find.byKey(StudioDriverKeys.timelineDetailText),
          )
          .data,
      arguments,
      reason: '参数原文中的完整路径可读',
    );
    await tester.tap(find.byKey(StudioDriverKeys.timelineDetailClose));
    await _pumpFrames(tester, frames: 16);
    expect(find.byKey(StudioDriverKeys.timelineDetailDialog), findsNothing);
    expect(client.budget.used(ResourceKind.pendingOperation), pendingBefore);
    expect(sharedScope.isActive, isTrue);
    expect(connection.connections.single.closeCalls, 0);

    // Text accompanying an MCP image remains available as the full result
    // field. The baseline deliberately contains only its truncated preview.
    await tester.tap(resultAction);
    await _pumpFrames(tester);
    final resultOwner = tester
        .widget<TimelineDetailConnector>(find.byType(TimelineDetailConnector))
        .owner;
    expect(resultOwner, isNot(same(argumentOwner)));
    expect(resultOwner.lease, same(lease));
    expect(resultOwner.field, const ThreadToolResultFieldView());
    expect(connection.detailCalls, hasLength(3));
    expect(connection.detailCalls[2].itemId, 'call-a');
    expect(
      connection.detailCalls[2].query.field,
      const ThreadToolResultFieldView(),
    );
    expect(connection.detailCalls[2].query.continuation, isNull);
    connection.detailCalls[2].reply.complete(
      ConversationDetailChunk(
        threadId: 'thread',
        timelineEpoch: 'component-epoch',
        itemId: 'call-a',
        field: const ThreadToolResultFieldView(),
        text: fullResult,
        totalBytes: utf8.encode(fullResult).length,
        continuation: null,
      ),
    );
    await _pumpFrames(tester);
    expect(resultOwner.state.text, fullResult);
    expect(resultOwner.state.error, isNull);
    expect(resultOwner.state.complete, isTrue);
    expect(resultOwner.canCopy, isTrue);
    expect(
      tester
          .widget<SelectableText>(
            find.byKey(StudioDriverKeys.timelineDetailText),
          )
          .data,
      fullResult,
    );
    await tester.tap(find.byKey(StudioDriverKeys.timelineDetailClose));
    await _pumpFrames(tester, frames: 16);
    expect(find.byKey(StudioDriverKeys.timelineDetailDialog), findsNothing);

    // A fresh viewer admits its own query. Closing with that backend gate held
    // cannot acknowledge scope release or close the shared feed.
    await tester.tap(resultAction);
    await _pumpFrames(tester);
    expect(connection.detailCalls, hasLength(4));
    expect(connection.detailCalls[3].itemId, 'call-a');
    expect(
      connection.detailCalls[3].query.field,
      const ThreadToolResultFieldView(),
    );
    expect(connection.detailCalls[3].query.continuation, isNull);
    expect(sharedScope.pendingQueries, 0, reason: '详情不借用共享分页 scope');
    expect(
      client.budget.used(ResourceKind.pendingOperation),
      pendingBefore + 2,
    );
    await tester.tap(find.byKey(StudioDriverKeys.timelineDetailClose));
    await _pumpFrames(tester);
    expect(find.byKey(StudioDriverKeys.timelineDetailDialog), findsOneWidget);
    expect(
      client.budget.used(ResourceKind.pendingOperation),
      pendingBefore + 2,
    );
    expect(connection.connections.single.closeCalls, 0);
    connection.detailCalls[3].reply.complete(
      ConversationDetailChunk(
        threadId: 'thread',
        timelineEpoch: 'component-epoch',
        itemId: 'call-a',
        field: const ThreadToolResultFieldView(),
        text: fullResult,
        totalBytes: utf8.encode(fullResult).length,
        continuation: null,
      ),
    );
    await _pumpFrames(tester, frames: 16);
    expect(find.byKey(StudioDriverKeys.timelineDetailDialog), findsNothing);
    expect(sharedScope.isActive, isTrue);
    expect(client.budget.used(ResourceKind.pendingOperation), pendingBefore);
    expect(connection.connections.single.closeCalls, 0);
    expect(transport.reads, hasLength(2), reason: '原图与工具详情操作均不重新读取附件');
    await tester.tap(find.byKey(StudioDriverKeys.timelineImageClose));
    await tester.pumpAndSettle();
    expect(imageDialog, findsNothing);

    // Immutable completed image atoms append without replacing prior entries.
    await _appendCompleted(tester, lease, [
      imageToolItem('call-c', appendSeq: 3),
    ]);
    await _pumpFrames(tester);
    expect(
      _imageThumbnail('call-a'),
      findsOneWidget,
      reason: '完成追加保持旧图片项的用户展开',
    );
    expect(transport.reads, hasLength(2), reason: '同附件继续复用缓存');
    await tester.tap(toggleFor('call-a'));
    await tester.pumpAndSettle();
    await _appendCompleted(tester, lease, [
      imageToolItem('call-d', appendSeq: 4),
    ]);
    await _pumpFrames(tester);
    expect(_imageThumbnail('call-a'), findsNothing, reason: '折叠后完成追加不自动展开');
    expect(transport.reads, hasLength(2));
    final oldResources = lease.imageResources;
    final feed = transport.connections.single;
    feed.emit(
      ConversationReset(
        componentBaseline(
          [imageToolItem('replacement-image', appendSeq: 1)],
          timelineEpoch: 'replacement-epoch',
          subscriptionId: feed.subscriptionId,
        ),
      ),
    );
    await pumpClientUntil(
      tester,
      () => owner.lease('thread') != lease,
      'image epoch reset',
    );
    final replacement = owner.lease('thread')!;
    expect(replacement.imageResources, isNot(same(oldResources)));
    await tester.pumpWidget(
      host(
        const TimelineConnector(threadId: 'thread'),
        client: client,
        owner: owner,
      ),
    );
    await tester.pumpAndSettle();
    await pumpClientFuture(tester, lease.released, 'old image subtree release');
    expect(lease.isReleased, isTrue);
    expect(transport.reads, hasLength(2), reason: '新代次仍默认折叠');
    await tester.tap(
      find.byKey(
        StudioDriverKeys.timelineActivitySummary(
          replacement.presentationFor('replacement-image')!.id,
        ),
      ),
    );
    await pumpClientUntil(
      tester,
      () => _imageThumbnail('replacement-image').evaluate().length == 1,
      'replacement image decoded',
    );
    expect(transport.reads, hasLength(3), reason: '旧代次已释放后必须重新读取');

    await _unmountTimeline(tester);
    await _pumpFrames(tester);
  });

  testWidgets('退役展示尚未卸载时不再发布阅读意图', (tester) async {
    final lease = await leaseFor(tester, items: longHistory());
    var intents = 0;
    await tester.pumpWidget(
      host(
        componentTimeline(
          threadId: 'thread',
          view: viewState(),
          lease: lease,
          onLoadOlder: () async {},
          onRetryOlder: () async {},
          onReturnLive: () async {},
          onRetryConnection: () async {},
          onEnterHistory: () => intents++,
        ),
      ),
    );
    await tester.pumpAndSettle();
    final released = lease.retire();
    try {
      final pointer = TestPointer(9, PointerDeviceKind.mouse);
      final center = tester.getCenter(find.byKey(StudioDriverKeys.timeline));
      await tester.sendEventToBinding(pointer.hover(center));
      await tester.sendEventToBinding(pointer.scroll(const Offset(0, -120)));
      await tester.pumpAndSettle();
      expect(lease.scrollController.position.pixels, greaterThan(0));
      expect(intents, 0, reason: '旧子树的最后一次滚动不能冻结已经切回的新展示');
    } finally {
      await _unmountTimeline(tester);
      await pumpClientFuture(tester, released, 'retired mounted lease release');
    }
  });

  testWidgets('失败连接的已捕获重试与返回按钮在展示退役后不能重开 feed', (tester) async {
    final (client, owner, transport) = await _openDetailSession(
      tester,
      baseline: _longBaseline(),
    );
    final lease = owner.lease('thread')!;
    await owner.dispatch('thread', const TimelineEnterHistory());
    await tester.pumpWidget(
      host(
        const TimelineConnector(threadId: 'thread'),
        client: client,
        owner: owner,
      ),
    );
    transport.openFailure = const StudioFailure(
      code: StudioFailureCode.unavailable,
      message: 'synthetic terminal connection failure',
      retryable: false,
      correlationId: 'retired-failed-actions',
    );
    client.conversations.session('thread').content.refresh();
    await pumpClientUntil(
      tester,
      () => transport.openCalls == 2,
      'failed reconnect admitted',
    );
    // Advance only the SDK's documented retry timers, not an arbitrary settling delay.
    for (final (index, delay) in const RetryPolicy().delays.indexed) {
      await tester.pump();
      await tester.pump(delay);
      await pumpClientUntil(
        tester,
        () => transport.openCalls == index + 3,
        'retry policy attempt ${index + 1}',
      );
    }
    await pumpClientUntil(
      tester,
      () => owner.source.value?.connection == TimelineConnectionPhase.failed,
      'real SDK connection failure',
    );
    await tester.pumpAndSettle();
    final retry = tester
        .widget<ButtonStyleButton>(
          find.byKey(StudioDriverKeys.timelineRetryConnection),
        )
        .onPressed!;
    final back = tester
        .widget<ButtonStyleButton>(
          find.byKey(StudioDriverKeys.timelineReturnLive),
        )
        .onPressed!;
    final before = owner.source.value;
    final opensBefore = transport.openCalls;
    final messages = List<Message>.of(lease.controller.messages);
    final released = lease.retire();
    expect(lease.isMounted, isTrue);
    expect(lease.isReleased, isFalse);
    for (final action in [retry, back]) {
      action();
      await tester.pump();
      expect(owner.source.value, same(before));
      expect(lease.controller.messages, orderedEquals(messages));
      expect(transport.openCalls, opensBefore, reason: '捕获的旧按钮不能重新打开连接');
      expect(transport.queryAdmissions, 0);
      expect(lease.isReleased, isFalse);
    }
    await _unmountTimeline(tester);
    await pumpClientFuture(tester, released, 'failed display subtree released');
    expect(lease.isReleased, isTrue);
  });

  testWidgets('epoch reset 换绑拒绝旧按钮和迟到页，真实卸载后仍等待旧 reader', (tester) async {
    final (client, owner, transport) = await _openDetailSession(
      tester,
      baseline: componentBaseline(
        [
          for (var i = 100; i < 132; i++)
            componentText('old-$i', appendSeq: i, body: '旧展示正文' * 16),
        ],
        before: 'same-cursor',
        hasOlder: true,
      ),
    );
    final lease = owner.lease('thread')!;
    await owner.dispatch('thread', const TimelineEnterHistory());
    final failedPage = owner.loadOlder('thread', generation: lease.generation);
    await pumpClientFuture(
      tester,
      transport.pageEntered(1),
      'old page admitted',
    );
    transport.pageCalls[0].reply.completeError(StateError('page failure'));
    await pumpClientFuture(tester, failedPage, 'page failure rendered');
    await tester.pumpWidget(
      host(
        const TimelineConnector(threadId: 'thread'),
        client: client,
        owner: owner,
      ),
    );
    await tester.pumpAndSettle();
    expect(lease.isMounted, isTrue);
    final retry = tester
        .widget<ButtonStyleButton>(
          find.byKey(StudioDriverKeys.timelineRetryOlder),
        )
        .onPressed!;
    final back = tester
        .widget<ButtonStyleButton>(
          find.byKey(StudioDriverKeys.timelineReturnLive),
        )
        .onPressed!;
    retry();
    await pumpClientFuture(
      tester,
      transport.pageEntered(2),
      'captured valid retry admitted',
    );
    final accepted = owner.retryOlder('thread', generation: lease.generation);
    final oldScope = lease.queries!;
    expect(oldScope.pendingQueries, 1);
    final pending = client.budget.used(ResourceKind.pendingOperation);
    final feed = transport.connections.single;
    transport.baseline = componentBaseline(
      [
        for (var i = 100; i < 132; i++)
          componentText('new-$i', appendSeq: i, body: '新展示正文' * 16),
      ],
      before: 'same-cursor',
      hasOlder: true,
      timelineEpoch: 'new-epoch',
      subscriptionId: feed.subscriptionId,
    );
    feed.emit(ConversationReset(transport.baseline));
    await pumpClientUntil(
      tester,
      () => owner.lease('thread') != lease,
      'new epoch accepted',
    );
    final replacement = owner.lease('thread')!;
    await tester.pumpAndSettle();
    expect(replacement.isMounted, isTrue);
    expect(lease.isMounted, isFalse);
    expect(lease.isReleased, isFalse, reason: '真实卸载不能丢失旧页与 reader join');
    expect(oldScope.isActive, isFalse);
    final state = owner.source.value;
    final messages = List<Message>.of(replacement.controller.messages);
    final cursor = replacement.completedCursor;
    for (final action in [retry, back]) {
      action();
      await tester.pump();
      expect(owner.source.value, same(state));
      expect(replacement.controller.messages, orderedEquals(messages));
      expect(replacement.completedCursor, same(cursor));
      expect(transport.queryAdmissions, 2);
      expect(transport.openCalls, 1);
      expect(oldScope.pendingQueries, 1);
      expect(client.budget.used(ResourceKind.pendingOperation), pending);
    }
    final closing = await pumpClientFuture(
      tester,
      oldScope.close(deadline: DateTime.utc(2000)),
      'retired reader pending close report',
    );
    expect(closing.complete, isFalse);
    expect(closing.unresolved, isNotEmpty);
    expect(replacement.isRetired, isFalse);
    expect(replacement.isMounted, isTrue);
    expect(client.budget.used(ResourceKind.pendingOperation), pending);
    transport.pageCalls[1].reply.complete(
      ConversationPage(
        threadId: 'thread',
        timelineEpoch: 'component-epoch',
        items: [componentText('late-old', appendSeq: 99, body: '迟到旧页')],
        before: const ConversationQueryCursor('older-next'),
        hasOlder: true,
      ),
    );
    await pumpClientFuture(tester, accepted, 'old accepted page joined');
    await pumpClientFuture(
      tester,
      lease.released,
      'old reader and Chat released',
    );
    expect(replacement.itemOf('late-old'), isNull);
    expect(replacement.completedCursor, same(cursor));
    expect(replacement.controller.messages, orderedEquals(messages));
    expect(owner.source.value, same(state), reason: '迟到页不能污染仍活动的新展示');
    expect(transport.readers.single.closed, isTrue);
    final replacementPage = owner.loadOlder(
      'thread',
      generation: replacement.generation,
    );
    await pumpClientFuture(
      tester,
      transport.pageEntered(3),
      'replacement same cursor admitted',
    );
    expect(
      transport.pageCalls[2].before,
      const ConversationQueryCursor('same-cursor'),
    );
    expect(replacement.queries, isNot(same(oldScope)));
    expect(replacement.queries!.generation, replacement.generation);
    transport.pageCalls[2].reply.complete(
      ConversationPage(
        threadId: 'thread',
        timelineEpoch: 'new-epoch',
        items: [
          componentText(
            'replacement-older',
            appendSeq: 99,
            body: '新 scope 接纳的旧页',
          ),
        ],
        before: null,
        hasOlder: false,
      ),
    );
    await pumpClientFuture(
      tester,
      replacementPage,
      'replacement page committed',
    );
    await tester.pumpAndSettle();
    expect(
      replacement
          .itemOf('replacement-older')
          ?.fieldFor(const ThreadTextFieldView())
          ?.text,
      '新 scope 接纳的旧页',
    );
    expect(replacement.hasOlder, isFalse);
    expect(replacement.completedCursor, same(cursor));
    expect(transport.openCalls, 1);
    expect(transport.readers, hasLength(2));
    expect(transport.readers.last.closed, isFalse);
    await _unmountTimeline(tester);
    final joined = await pumpClientFuture(
      tester,
      owner.close(),
      'retry owner cleanup',
    );
    expect(joined.complete, isTrue);
  });

  // ---- R2 嵌套工具内部滚动：桌面平台语义下的承重证明 -----------------------------

  testWidgets(
    '嵌套工具内部滚动不会把主 Timeline 推进 History',
    variant: TargetPlatformVariant.only(TargetPlatform.linux),
    (tester) async {
      final lease = await leaseFor(
        tester,
        items: [
          toolItem(
            'tool-1',
            arguments: [
              for (var line = 0; line < 40; line++) 'line-$line: payload',
            ].join('\n'),
          ),
        ],
      );
      var enteredHistory = 0;
      await tester.pumpWidget(
        host(
          componentTimeline(
            threadId: 'thread',
            view: viewState(),
            lease: lease,
            onLoadOlder: () async {},
            onRetryOlder: () async {},
            onReturnLive: () async {},
            onEnterHistory: () => enteredHistory += 1,
            onRetryConnection: () async {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(
          StudioDriverKeys.timelineActivitySummary(
            lease.presentationFor('tool-1')!.id,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find
            .descendant(
              of: find.byKey(StudioDriverKeys.timelineBlock('tool-1')),
              matching: find.byType(InkWell),
            )
            .first,
      );
      await tester.pumpAndSettle();
      // The new feature's native group ListView owns the bounded tool viewport;
      // do not require the retired private code-block scroll widget.
      final groupView = find
          .ancestor(
            of: find.byKey(
              StudioDriverKeys.timelineActivitySummary(
                lease.presentationFor('tool-1')!.id,
              ),
            ),
            matching: find.byType(TimelineEntryView),
          )
          .first;
      final candidates = find.descendant(
        of: groupView,
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is Scrollable &&
              axisDirectionToAxis(widget.axisDirection) == Axis.vertical,
        ),
      );
      expect(candidates, findsWidgets);
      // 选出承载展开工具参数、真正可滚动的内部区域（有独立 extent）。
      Finder? inner;
      ScrollPosition? innerPosition;
      for (var index = 0; index < candidates.evaluate().length; index++) {
        final candidate = candidates.at(index);
        final position = tester.state<ScrollableState>(candidate).position;
        if (position.maxScrollExtent > 0) {
          inner = candidate;
          innerPosition = position;
          break;
        }
      }
      expect(inner, isNotNull, reason: '工具参数有自己的可滚动区域');
      final innerBefore = innerPosition!.pixels;

      // 真实用户输入作用在内部区域：鼠标滚轮落在嵌套视图内。
      final innerRect = tester.getRect(inner!);
      final pointer = TestPointer(1, PointerDeviceKind.mouse);
      await tester.sendEventToBinding(pointer.hover(innerRect.center));
      await tester.sendEventToBinding(pointer.scroll(const Offset(0, 120)));
      await tester.pumpAndSettle();
      // 内层确实是滚动目标：自己的 position 真实前进，而不是只固定了外层。
      expect(
        innerPosition.pixels,
        isNot(innerBefore),
        reason: '嵌套工具内部必须真实滚动，而不是被吞掉',
      );
      expect(innerPosition.pixels, greaterThan(0));
      expect(enteredHistory, 0, reason: '嵌套工具内部滚动不得改主 Timeline 模式');
      expect(lease.scrollController.position.pixels, 0, reason: '外层几何不动');
    },
  );

  // ---- R3 无位移动作不得悬挂意图 --------------------------------------------------

  testWidgets('底端无位移的键盘/轨道动作不把之后的几何修正误判为用户意图', (tester) async {
    final lease = await leaseFor(tester, items: longHistory());
    var enteredHistory = 0;
    var loads = 0;
    await tester.pumpWidget(
      host(
        componentTimeline(
          threadId: 'thread',
          view: viewState(),
          lease: lease,
          onLoadOlder: () async {
            loads += 1;
          },
          onRetryOlder: () async {},
          onReturnLive: () async {},
          onEnterHistory: () => enteredHistory += 1,
          onRetryConnection: () async {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    final loadsAtStart = loads;
    // 已在底端：先点选最靠近底端的正文让键盘焦点进入，再按 PageDown
    // （反向列表底端无位移）。
    await tester.tap(
      find.byKey(
        StudioDriverKeys.timelineRow(lease.presentationFor('item-119')!.id),
      ),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.pageDown);
    await tester.pumpAndSettle();
    expect(lease.scrollController.position.pixels, 0);

    // 真实非用户的 depth-0 几何修正：只移动标准 position（`jumpTo` 不发
    // `UserScrollNotification`，Start/Update/End 都不带 dragDetails），等价于布局/内容
    // 扩展引起的像素修正，而不是读者滚动。无位移动作若留下悬挂意图，这里会被判成
    // “用户离开底端”。
    final position = lease.scrollController.position;
    expect(position.maxScrollExtent, greaterThan(200), reason: '确保存在可修正的几何');
    lease.scrollController.jumpTo(200);
    await tester.pumpAndSettle();
    expect(position.pixels, 200);
    expect(enteredHistory, 0, reason: '无位移动作不得把后续几何修正误判为用户意图');
    // 同一无位移动作之后再做一次反向修正也不得触发。
    lease.scrollController.jumpTo(0);
    await tester.pumpAndSettle();
    expect(enteredHistory, 0);

    // 端点轨道：底端 thumb 按下不翻页（探针确认几何），也不得留下意图。
    final scrollbar = find
        .byWidgetPredicate((widget) => widget is RawScrollbar)
        .first;
    final barRect = tester.getRect(scrollbar);
    final endpoint = Offset(barRect.right - 6, barRect.bottom - 4);
    // 自动淡出后先按真实鼠标悬停唤回滚动条，避免透明时点击穿透使本用例空跑。
    final mouse = TestPointer(1, PointerDeviceKind.mouse);
    await tester.sendEventToBinding(mouse.hover(endpoint));
    await tester.pumpAndSettle();
    final paintFinder = find.descendant(
      of: scrollbar,
      matching: find.byWidgetPredicate(
        (widget) =>
            widget is CustomPaint &&
            widget.foregroundPainter is ScrollbarPainter,
      ),
    );
    final painter =
        tester.widget<CustomPaint>(paintFinder).foregroundPainter!
            as ScrollbarPainter;
    final box = tester.renderObject<RenderBox>(paintFinder);
    expect(
      painter.hitTestOnlyThumbInteractive(
        box.globalToLocal(endpoint),
        PointerDeviceKind.mouse,
      ),
      isTrue,
      reason: '端点动作必须命中可见 thumb，而不是穿透到正文',
    );
    await tester.tapAt(endpoint, kind: PointerDeviceKind.mouse);
    await tester.sendEventToBinding(mouse.removePointer());
    await tester.pumpAndSettle();
    expect(position.pixels, 0, reason: '底端轨道动作不产生位移');
    lease.scrollController.jumpTo(200);
    await tester.pumpAndSettle();
    expect(enteredHistory, 0, reason: '端点轨道动作不得留下悬挂意图');
    lease.scrollController.jumpTo(0);
    await tester.pumpAndSettle();

    // 随后改窗/内容增长引起的几何修正同样不得被当成用户离开底端。
    await tester.binding.setSurfaceSize(const Size(760, 640));
    await tester.pumpAndSettle();
    await tester.binding.setSurfaceSize(const Size(900, 700));
    await tester.pumpAndSettle();
    expect(enteredHistory, 0, reason: '无位移动作不得留下悬挂意图');
    expect(loads, loadsAtStart, reason: '这些动作都不是分页意图');
  });

  // ---- R4 有内容时连接状态可见 + 重试不换代 ---------------------------------------

  testWidgets('重连/失败在已有内容时可见，重试不换代也不丢 History', (tester) async {
    final lease = await leaseFor(
      tester,
      items: [textItem('only', appendSeq: 1)],
    );
    var retries = 0;
    await tester.pumpWidget(
      host(
        componentTimeline(
          threadId: 'thread',
          view: viewState(mode: TimelineDisplayMode.history),
          lease: lease,
          onLoadOlder: () async {},
          onRetryOlder: () async {},
          onReturnLive: () async {},
          onEnterHistory: () {},
          onRetryConnection: () async {
            retries += 1;
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(StudioDriverKeys.timelineConnectionNotice), findsNothing);

    // reconnecting：可见提示，内容仍在，无 retry。
    await tester.pumpWidget(
      host(
        componentTimeline(
          threadId: 'thread',
          view: viewState(
            mode: TimelineDisplayMode.history,
            connection: TimelineConnectionPhase.reconnecting,
          ),
          lease: lease,
          onLoadOlder: () async {},
          onRetryOlder: () async {},
          onReturnLive: () async {},
          onEnterHistory: () {},
          onRetryConnection: () async {
            retries += 1;
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(StudioDriverKeys.timelineConnectionNotice),
      findsOneWidget,
    );
    final reconnectNotice = find.byKey(
      StudioDriverKeys.timelineConnectionNotice,
    );
    expect(
      find.descendant(of: reconnectNotice, matching: find.byType(Text)),
      findsWidgets,
      reason: '重连状态必须有实际可见提示，且已有内容保留',
    );
    expect(
      find.byKey(
        StudioDriverKeys.timelineRow(lease.presentationFor('only')!.id),
      ),
      findsOneWidget,
    );
    expect(find.byKey(StudioDriverKeys.timelineRetryConnection), findsNothing);

    // failed：可见错误 + retry；点 retry 只重试连接，代次与内容不变。
    await tester.pumpWidget(
      host(
        componentTimeline(
          threadId: 'thread',
          view: viewState(
            mode: TimelineDisplayMode.history,
            connection: TimelineConnectionPhase.failed,
            connectionError: StateError('synthetic connection failure'),
          ),
          lease: lease,
          onLoadOlder: () async {},
          onRetryOlder: () async {},
          onReturnLive: () async {},
          onEnterHistory: () {},
          onRetryConnection: () async {
            retries += 1;
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(StudioDriverKeys.timelineConnectionNotice),
      findsOneWidget,
    );
    expect(
      find.textContaining('synthetic connection failure'),
      findsOneWidget,
      reason: '错误信息在已有 History 内容旁仍可见',
    );
    await tester.tap(find.byKey(StudioDriverKeys.timelineRetryConnection));
    await tester.pumpAndSettle();
    expect(retries, 1);
    expect(lease.generation, 1, reason: '连接重试不得换代');
    expect(
      find.byKey(
        StudioDriverKeys.timelineRow(lease.presentationFor('only')!.id),
      ),
      findsOneWidget,
    );
  });
}

final _fixtures = Expando<(TimelineSessionOwner, _DetailTransport)>();

Future<void> _appendCompleted(
  WidgetTester tester,
  TimelineDisplayLease lease,
  List<ConversationItem> items,
) async {
  final (owner, transport) = _fixtures[lease]!;
  final connection = transport.connections.last;
  final from = lease.completedCursor!.appendSeq;
  final through = items.last.header.appendSeq;
  expect(items.map((item) => item.header.appendSeq), [
    for (var seq = from + 1; seq <= through; seq++) seq,
  ]);
  connection.emit(
    ConversationBatch(
      subscriptionId: connection.subscriptionId,
      timelineEpoch: lease.timelineEpoch,
      fromSeq: from,
      throughSeq: through,
      items: items,
    ),
  );
  await pumpClientUntil(
    tester,
    () => lease.completedCursor?.appendSeq == through,
    'completed atoms accepted by Flyer',
  );
  await pumpClientUntil(
    tester,
    () => connection.acknowledgements.contains(connection.deliveredFrames),
    'completion credit acknowledged',
  );
  expect(owner.lease('thread'), same(lease));
  expect(lease.completedCursor?.appendSeq, through);
}

Future<void> _emitTailAdditions(
  WidgetTester tester, {
  required TimelineSessionOwner owner,
  required TimelineDisplayLease lease,
  required _DetailConnection connection,
  required List<ConversationItem> items,
}) async {
  expect(lease.loadedCount, 32);
  final from = lease.completedCursor!.appendSeq;
  final through = items.last.header.appendSeq;
  expect(items.map((item) => item.header.appendSeq), [
    for (var seq = from + 1; seq <= through; seq++) seq,
  ]);
  connection.emit(
    ConversationBatch(
      subscriptionId: connection.subscriptionId,
      timelineEpoch: lease.timelineEpoch,
      fromSeq: from,
      throughSeq: through,
      items: items,
    ),
  );
  await pumpClientUntil(
    tester,
    () => lease.completedCursor?.appendSeq == through,
    'completion batch presented',
  );
  await pumpClientUntil(
    tester,
    () => connection.acknowledgements.contains(connection.deliveredFrames),
    'batch credit acknowledged',
  );
  expect(owner.lease('thread'), same(lease));
  expect(lease.loadedCount, 40);
}

// The Client/owner are constructed by the widget test, while their first feed
// is started in runAsync below. Close must drive both zones; assertions stay
// outside the future being pumped so Flutter's guarded test APIs do not reenter.
Future<void> _closeDetailSession(
  WidgetTester tester,
  TimelineSessionOwner owner,
  AnyworkClient client,
  DateTime deadline,
) async {
  final ownerReport = await pumpClientFuture(
    tester,
    owner.close(deadline: deadline),
    'detail session owner close',
  );
  expect(ownerReport.unresolved, isEmpty);
  final clientReport = await pumpClientFuture(
    tester,
    client.close(deadline: deadline),
    'detail session client close',
  );
  expect(clientReport.unresolved, isEmpty);
}

Future<(AnyworkClient, TimelineSessionOwner, _DetailTransport)>
_openDetailSession(
  WidgetTester tester, {
  ConversationBaseline? baseline,
  _DetailTransport? backend,
}) async {
  final transport = backend ?? _DetailTransport(baseline: baseline);
  final accounts = _UnusedTimelineAccountPorts();
  final graph = AppGraph(
    transport: transport,
    statisticsFeed: const TestStatisticsFeedPort(),
    clientId: 'timeline-widget',
    accountFeed: accounts,
    accountConfiguration: accounts,
    accountModels: accounts,
    accountUsage: accounts,
    acpPort: accounts,
  );
  final client = graph.client;
  final owner = graph.timeline;
  addTearDown(() async {
    transport.releasePending();
    await _unmountTimeline(tester);
    final report = await pumpClientFuture(
      tester,
      graph.close(deadline: DateTime.now().add(const Duration(seconds: 5))),
      'widget AppGraph close',
    );
    expect(report.unresolved, isEmpty);
    expect(client.budget.usage, isEmpty);
  });
  graph.setConversationPageVisible(true, threadId: 'thread');
  await pumpClientFuture(
    tester,
    client.conversations.session('thread').content.ready,
    'SDK baseline ready after owner acceptance',
  );
  expect(owner.source.value?.connection, TimelineConnectionPhase.ready);
  await pumpClientUntil(
    tester,
    () => transport.connections.single.acknowledgements.contains(
      transport.connections.single.deliveredFrames,
    ),
    'baseline credit acknowledged',
  );
  return (client, owner, transport);
}

StudioThread _thread() => StudioThread(
  id: 'thread',
  workspaceId: 'project',
  title: 'Thread',
  mode: ThreadModeId.simple,
  delegationMode: DelegationMode.profile,
  delegationPreference: DelegationPreference.balanced,
  updatedAt: DateTime.utc(2026),
  workspacePath: '/workspace/thread',
);

/// Typed baseline facts; no old ThreadItem shell or duplicate detail metadata.
ConversationBaseline _detailBaseline() => componentBaseline([
  componentText('big', appendSeq: 1, body: '预览', totalBytes: 13),
]);

// The Driver projection receives a small baseline followed by a real completion
// batch. It does not seed a second history mirror or bypass owner acceptance.
ConversationBaseline _longBaseline() => componentBaseline(
  [
    for (var index = 0; index < 32; index++)
      componentText(
        'line-$index',
        appendSeq: index + 1,
        body: '第 $index 段静态正文' * 6,
      ),
  ],
  before: 'cursor',
  hasOlder: true,
);

ConversationBaseline _selectionBaseline() => componentBaseline([
  componentText('before', appendSeq: 1, body: '前段canonical正文'),
  componentText('big', appendSeq: 2, body: '截断前的preview', totalBytes: 40),
  componentText('after', appendSeq: 3, body: '后段canonical正文'),
]);

ConversationBaseline _twoFieldBaseline() => componentBaseline([
  componentTool(
    'tool',
    arguments: '{"command":"cargo test"}',
    result: 'ok',
    totalArgumentsBytes: 80,
    totalResultBytes: 8,
  ),
]);

final class _UnusedTimelineAccountPorts extends UnusedAccountPorts {}

/// 真实附件字节通路的受控 backend：记录实际读取，返回可解码的 1×1 PNG。
final class _ImageTransport extends _DetailTransport {
  _ImageTransport({this.failures = 0, super.baseline});
  int failures;
  final List<String> reads = [];

  @override
  Future<Uint8List> readThreadAttachment(
    String threadId,
    String attachmentId,
  ) async {
    reads.add('$threadId:$attachmentId');
    if (failures > 0) {
      failures--;
      throw StateError('Fixture image temporarily unavailable');
    }
    return _onePixelPng;
  }
}

/// 1×1 透明 PNG：真实解码路径可用，避免用伪造字节触发解码错误。
final Uint8List _onePixelPng = Uint8List.fromList(const <int>[
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, //
  0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52, //
  0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01, //
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, //
  0x89, 0x00, 0x00, 0x00, 0x0A, 0x49, 0x44, 0x41, //
  0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00, //
  0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00, //
  0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE, //
  0x42, 0x60, 0x82,
]);

class _DetailTransport extends RecordingDemoTransport {
  _DetailTransport({ConversationBaseline? baseline})
    : baseline = baseline ?? _detailBaseline();
  ConversationBaseline baseline;
  final List<_DetailConnection> connections = [];
  final List<_DetailReader> readers = [];
  int openCalls = 0;
  Object? openFailure;
  int get readerOpens => readers.length;
  int get queryAdmissions => pageCalls.length + detailCalls.length;
  final List<
    ({
      ConversationQueryCursor? before,
      int? limit,
      Completer<ConversationPage> reply,
    })
  >
  pageCalls = [];
  final List<
    ({
      String itemId,
      ConversationDetailQuery query,
      Completer<ConversationDetailChunk> reply,
    })
  >
  detailCalls = [];
  final List<Completer<void>> _pageAdmissions = [];
  final List<Completer<_DetailConnection>> _opened = [];
  bool holdNextInitial = false;
  Completer<void>? _initialGate;
  Future<void> pageEntered(int count) {
    while (_pageAdmissions.length < count) {
      _pageAdmissions.add(Completer<void>());
    }
    return _pageAdmissions[count - 1].future;
  }

  Future<_DetailConnection> opened(int count) {
    while (_opened.length < count) {
      _opened.add(Completer<_DetailConnection>());
    }
    return _opened[count - 1].future;
  }

  @override
  Future<ConversationFeed> openConversationFeed(
    String threadId, {
    ConversationCompletionCursor? resumeAfter,
  }) async {
    openCalls++;
    final failure = openFailure;
    if (failure != null) throw failure;
    final gate = holdNextInitial ? (_initialGate = Completer<void>()) : null;
    holdNextInitial = false;
    final connection = _DetailConnection(
      baseline: () => baseline,
      serial: connections.length + 1,
      initialGate: gate,
      resumed: resumeAfter != null,
    );
    connections.add(connection);
    opened(connections.length);
    _opened[connections.length - 1].complete(connection);
    return connection;
  }

  @override
  Future<ConversationHistoryReader> openHistoryReader(String threadId) async {
    final reader = _DetailReader(this, threadId, baseline.timelineEpoch);
    readers.add(reader);
    return reader;
  }

  void releaseInitial() {
    _initialGate!.complete();
    _initialGate = null;
  }

  void releasePending() {
    final gate = _initialGate;
    if (gate != null && !gate.isCompleted) gate.complete();
    for (final call in pageCalls) {
      if (!call.reply.isCompleted) {
        call.reply.completeError(const StaleConversationScope());
      }
    }
    for (final call in detailCalls) {
      if (!call.reply.isCompleted) {
        call.reply.completeError(const StaleConversationScope());
      }
    }
  }
}

final class _DetailConnection extends ScriptedConversationFeed {
  _DetailConnection({
    required ConversationBaseline Function() baseline,
    required int serial,
    this.initialGate,
    required this.resumed,
  }) : super(
         threadId: 'thread',
         subscriptionId: 'detail-$serial',
         baseline: () {
           final value = baseline();
           return componentBaseline(
             value.items,
             before: value.before?.token,
             hasOlder: value.hasOlder,
             timelineEpoch: value.timelineEpoch,
             subscriptionId: 'detail-$serial',
           );
         },
         state: () => ThreadSnapshotFrame(
           workspace: ThreadWorkspace(
             thread: _thread(),
             revision: 1,
             interactions: const [],
             runtime: const ThreadRuntimeView(
               modelId: 'fixture',
               contextTokens: 0,
               contextWindow: 100,
               totalTokens: 0,
               costLabel: '',
               activeSkills: [],
               activeMcpServers: [],
               activeLspServers: [],
             ),
           ),
         ),
       );
  final Completer<void>? initialGate;
  final bool resumed;
  @override
  Stream<ConversationFrame> get events async* {
    if (initialGate != null) await initialGate!.future;
    await for (final frame in super.events) {
      if ((resumed, frame.event) case (
        true,
        ConversationBaselineEvent(:final baseline),
      )) {
        yield ConversationFrame(
          threadId: frame.threadId,
          subscriptionId: frame.subscriptionId,
          deliverySequence: frame.deliverySequence,
          event: ConversationUpdateEvent(update: ConversationReset(baseline)),
        );
      } else {
        yield frame;
      }
    }
  }
}

/// An independent native reader fixture, never a feed or a completion consumer.
final class _DetailReader implements ConversationHistoryReader {
  _DetailReader(this.transport, this.threadId, this.timelineEpoch);
  final _DetailTransport transport;
  @override
  final String threadId;
  @override
  final String timelineEpoch;
  final List<Future<void>> _pending = [];
  bool closing = false;
  bool closed = false;
  Future<T> _record<T>(Completer<T> reply) {
    if (closing) throw StateError('Reader is closing');
    _pending.add(
      reply.future.then<void>((_) {}, onError: (Object _, StackTrace _) {}),
    );
    return reply.future;
  }

  @override
  Future<ConversationPage> page({ConversationQueryCursor? before, int? limit}) {
    final reply = Completer<ConversationPage>();
    final result = _record(reply);
    transport.pageCalls.add((before: before, limit: limit, reply: reply));
    transport.pageEntered(transport.pageCalls.length);
    transport._pageAdmissions[transport.pageCalls.length - 1].complete();
    return result;
  }

  @override
  Future<ConversationDetailChunk> readDetail({
    required String itemId,
    required ConversationDetailQuery query,
  }) {
    final reply = Completer<ConversationDetailChunk>();
    final result = _record(reply);
    transport.detailCalls.add((itemId: itemId, query: query, reply: reply));
    return result;
  }

  @override
  void requestClose() {
    closing = true;
  }

  @override
  Future<void> close() async {
    requestClose();
    await Future.wait(_pending);
    closed = true;
  }
}

ConversationDetailChunk _chunk({
  String? continuation,
  String? text,
  int totalBytes = 13,
}) => ConversationDetailChunk(
  threadId: 'thread',
  timelineEpoch: 'component-epoch',
  itemId: 'big',
  field: const ThreadTextFieldView(),
  text: text ?? (continuation == null ? '甲🐱\n乙\r\n' : '甲🐱\n'),
  totalBytes: totalBytes,
  continuation: continuation == null
      ? null
      : ConversationQueryCursor(continuation),
);

Finder _imageConnector(String toolId) => find.byWidgetPredicate(
  (widget) =>
      widget is TimelineImageConnector &&
      widget.message.id == '$toolId:attachment:att-shared',
);

Finder _imageThumbnail(String toolId) => find.descendant(
  of: _imageConnector(toolId),
  matching: find.byType(FlyerChatImageMessage),
);

Finder _imageRetry(String toolId) => find.descendant(
  of: _imageConnector(toolId),
  matching: find.byType(TextButton),
);

/// Close the real route/owner before removing its Navigator, so disposal cannot
/// turn an unjoined viewer into a false resource-release acknowledgement.
Future<void> _unmountTimeline(WidgetTester tester) async {
  final close = find.byKey(StudioDriverKeys.timelineDetailClose);
  if (close.evaluate().isNotEmpty) {
    await tester.tap(close);
    await _pumpFrames(tester, frames: 16);
    await pumpClientUntil(
      tester,
      () =>
          find.byKey(StudioDriverKeys.timelineDetailDialog).evaluate().isEmpty,
      'detail route close before unmount',
    );
    expect(find.byKey(StudioDriverKeys.timelineDetailDialog), findsNothing);
  }
  await tester.pumpWidget(const SizedBox.shrink());
}

/// 只推进有限帧：查看器读取中可能出现进度指示，`pumpAndSettle` 会等不到静止。
Future<void> _pumpFrames(WidgetTester tester, {int frames = 8}) async {
  for (var index = 0; index < frames; index++) {
    await tester.pump(const Duration(milliseconds: 20));
  }
}
