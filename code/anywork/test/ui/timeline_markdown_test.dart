// Pure Markdown regressions retained from the retired timeline/group suite.
import 'package:anywork/src/app/theme/material3_theme.dart';
import 'package:anywork/src/features/conversation/timeline/widgets/timeline_markdown.dart';
import 'package:anywork/src/l10n/app_localizations.dart';
import 'package:anywork/src/shared/studio_code_block.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gpt_markdown/gpt_markdown.dart';

Widget host(Widget child) => MaterialApp(
  theme: pureStudioTheme(),
  locale: const Locale('zh'),
  localizationsDelegates: [
    AppLocalizations.delegate,
    ...GlobalMaterialLocalizations.delegates,
  ],
  supportedLocales: AppLocalizations.supportedLocales,
  home: Scaffold(body: child),
);
void main() {
  testWidgets('热更新字面标记经 Markdown 行内代码保留完整四字形', (tester) async {
    var source = '热更新正文：';
    final markers = <String>[];
    for (var index = 0; index <= 20; index++) {
      if (index > 0) {
        final number = index.toString().padLeft(2, '0');
        source += ' `[$number]`';
        markers.add('[$number]');
      }
      await tester.pumpWidget(
        host(
          TimelineMarkdown(
            id: 'hot-update-literal-markers',
            text: source,
            onLink: (_) => fail('字面标记不是链接'),
            isSafeLink: (_) => false,
            imageBuilder: (_, _) => throw StateError('没有图片'),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final paragraphs = find.descendant(
        of: find.byType(TimelineMarkdown),
        matching: find.byWidgetPredicate((widget) => widget is RichText),
      );
      final texts = tester
          .widgetList<RichText>(paragraphs)
          .map((widget) => widget.text.toPlainText())
          .toList();
      expect(texts.any((text) => text.contains('热更新正文：')), isTrue);
      for (final marker in markers) {
        expect(
          texts.where((text) => text.contains(marker)),
          hasLength(1),
          reason: '正文必须绘制完整字面标记，而不是来源标签的占位符或编号',
        );
      }
      expect(tester.takeException(), isNull);
    }
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

  testWidgets('Timeline Markdown HTML 链接无危险手势且图片经过受控入口', (tester) async {
    const source =
        '<b>HTML 正文</b>\n\n'
        '<a href="javascript:alert(1)">危险 HTML 链接</a>\n\n'
        '<script>隐藏脚本</script>\n\n'
        '<img src="https://fixture.invalid/html.png" alt="HTML 图片">\n\n'
        '![Markdown 图片](https://fixture.invalid/markdown.png)';
    final images = <String>{};
    await tester.pumpWidget(
      host(
        SingleChildScrollView(
          child: TimelineMarkdown(
            id: 'html-safety',
            text: source,
            onLink: (_) => fail('危险 HTML 链接不应触发动作'),
            isSafeLink: (_) => false,
            imageBuilder: (_, url) {
              images.add(url);
              return SizedBox(key: ValueKey(url), width: 20, height: 20);
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('HTML 正文', findRichText: true), findsOneWidget);
    expect(find.text('危险 HTML 链接', findRichText: true), findsOneWidget);
    expect(find.textContaining('隐藏脚本', findRichText: true), findsNothing);
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
    expect(images, {
      'https://fixture.invalid/html.png',
      'https://fixture.invalid/markdown.png',
    });
    for (final url in images) {
      expect(find.byKey(ValueKey(url)), findsOneWidget);
    }
    expect(tester.widget<GptMarkdown>(find.byType(GptMarkdown)).data, source);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Timeline Markdown 引用标签仅安全目标具有点击手势', (tester) async {
    const source =
        '安全引用 [1]，危险引用 [2]，无目标引用 [3]。\n\n'
        '[1]: https://fixture.invalid/source\n'
        '[2]: javascript:alert';
    final launched = <String>[];
    await tester.pumpWidget(
      host(
        TimelineMarkdown(
          id: 'source-tag-safety',
          text: source,
          onLink: launched.add,
          isSafeLink: (url) => url == 'https://fixture.invalid/source',
          imageBuilder: (_, _) => throw StateError('没有图片'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    for (final id in ['1', '2', '3']) {
      expect(find.text(id), findsOneWidget);
      final gestures = tester.widgetList<GestureDetector>(
        find.ancestor(
          of: find.text(id),
          matching: find.byType(GestureDetector),
        ),
      );
      expect(
        gestures.where((gesture) => gesture.onTap != null),
        hasLength(id == '1' ? 1 : 0),
        reason: '危险或无目标引用必须没有点击手势',
      );
    }
    await tester.tap(find.text('1'));
    await tester.pumpAndSettle();
    expect(launched, ['https://fixture.invalid/source']);
    expect(tester.widget<GptMarkdown>(find.byType(GptMarkdown)).data, source);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Timeline Markdown 标题遵循所在主题层级且完整可读', (tester) async {
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

    for (final (label, size) in [
      ('一级标题', textTheme.headlineLarge!.fontSize!),
      ('二级标题', textTheme.headlineMedium!.fontSize!),
      ('三级标题', textTheme.headlineSmall!.fontSize!),
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
      expect(span.style?.fontSize, size, reason: '$label 必须使用所在主题的标题字号');
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
}
