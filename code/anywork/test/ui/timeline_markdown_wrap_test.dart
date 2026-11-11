import 'dart:ui' as ui;

import 'package:anywork/src/app/theme/material3_theme.dart';
import 'package:anywork/src/features/conversation/timeline/widgets/timeline_markdown.dart';
import 'package:anywork/src/l10n/app_localizations.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> pumpMarkdown(
    WidgetTester tester, {
    required String text,
    Size size = const Size(240, 640),
    int? maxLines,
    TextOverflow? overflow,
    double textScale = 1,
  }) async {
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        theme: pureStudioTheme(),
        localizationsDelegates: [
          AppLocalizations.delegate,
          ...GlobalMaterialLocalizations.delegates,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: MediaQuery(
          data: MediaQueryData(
            size: size,
            textScaler: TextScaler.linear(textScale),
          ),
          child: Scaffold(
            body: SizedBox(
              key: const ValueKey('markdown-parent'),
              width: size.width,
              child: SelectionArea(
                child: TimelineMarkdown(
                  id: 'wrap',
                  text: text,
                  onLink: (_) {},
                  isSafeLink: (_) => true,
                  imageBuilder: (_, url) => Text(url),
                  maxLines: maxLines,
                  overflow: overflow,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('展开 Markdown 长无空格串按父宽换行，不横向溢出', (tester) async {
    const url =
        'https://example.test/very/long/path/without/spaces/abcdefghijklmnopqrstuvwxyz0123456789';
    await pumpMarkdown(tester, text: 'See `$url` and $url');
    expect(tester.takeException(), isNull);
    final markdown = tester.getRect(find.byType(TimelineMarkdown));
    _expectWithinParent(tester, markdown);
    final paragraphs = _paragraphs(tester);
    expect(
      paragraphs.any((paragraph) => _lineCount(paragraph) > 1),
      isTrue,
      reason: 'the long inline content must actually wrap onto multiple lines',
    );
  });

  testWidgets('代码块在有限宽度下换行，缩放后仍不溢出', (tester) async {
    const code =
        'fn very_long_identifier_without_spaces_abcdefghijklmnopqrstuvwxyz()';
    await pumpMarkdown(
      tester,
      text: '```dart\n$code\n```',
      textScale: 1.4,
      size: const Size(220, 640),
    );
    expect(tester.takeException(), isNull);
    final markdown = tester.getRect(find.byType(TimelineMarkdown));
    _expectWithinParent(tester, markdown);
    expect(find.textContaining('very_long_identifier'), findsOneWidget);
    final codeParagraph = _paragraphs(
      tester,
    ).singleWhere((paragraph) => paragraph.text.toPlainText().contains(code));
    expect(
      _lineCount(codeParagraph),
      greaterThan(1),
      reason: 'the long code line wraps instead of scrolling or clipping',
    );
  });

  testWidgets('摘要路径保持单行省略，不展开全文', (tester) async {
    const text =
        '**summary** that should stay on one line even when it is quite long';
    await pumpMarkdown(
      tester,
      text: text,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      size: const Size(180, 80),
    );
    expect(tester.takeException(), isNull);
    final markdown = tester.getRect(find.byType(TimelineMarkdown));
    _expectWithinParent(tester, markdown);
    final summary = _paragraphs(tester).singleWhere(
      (paragraph) => paragraph.text.toPlainText().contains('summary'),
    );
    expect(summary.maxLines, 1);
    expect(summary.overflow, TextOverflow.ellipsis);
    expect(
      summary.didExceedMaxLines,
      isTrue,
      reason: 'the long summary is truncated, not expanded to its full height',
    );
  });

  testWidgets('外层正文选择包含代码块并保留代码缩进和内部换行', (tester) async {
    const code = 'void example() {\n  print("preserve indentation");\n}';
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
    await pumpMarkdown(
      tester,
      text: 'Before the code.\n\n```dart\n$code\n```\n\nAfter the code.',
      size: const Size(420, 640),
    );
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
    expect(copied, contains(code));
    expect(
      copied!.indexOf('Before the code.'),
      lessThan(copied!.indexOf(code)),
    );
    expect(copied!.indexOf(code), lessThan(copied!.indexOf('After the code.')));
    expect(tester.takeException(), isNull);
  });

  testWidgets('生产多行普通正文原样显示并复制缩进、段落和尾随换行', (tester) async {
    const text = '    raw paragraph: user@example.test\n\nlast line  \r\n';
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
    await pumpMarkdown(tester, text: text);
    expect(
      tester.widget<Text>(find.byKey(const ValueKey('plain-text-wrap'))).data,
      text,
    );
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
    expect(copied, text);
    expect(tester.takeException(), isNull);
  });
}

Iterable<RenderParagraph> _paragraphs(WidgetTester tester) =>
    tester.renderObjectList<RenderParagraph>(
      find.descendant(
        of: find.byType(TimelineMarkdown),
        matching: find.bySubtype<RichText>(),
      ),
    );

int _lineCount(RenderParagraph paragraph) => paragraph
    .getBoxesForSelection(
      TextSelection(
        baseOffset: 0,
        extentOffset: paragraph.text.toPlainText().length,
      ),
      boxHeightStyle: ui.BoxHeightStyle.max,
    )
    .map((box) => box.top)
    .toSet()
    .length;

void _expectWithinParent(WidgetTester tester, Rect markdown) {
  final parent = tester.getRect(find.byKey(const ValueKey('markdown-parent')));
  expect(markdown.width, greaterThan(0));
  expect(markdown.height, greaterThan(0));
  expect(markdown.left, greaterThanOrEqualTo(parent.left));
  expect(markdown.right, lessThanOrEqualTo(parent.right));
  expect(markdown.top, greaterThanOrEqualTo(parent.top));
  expect(markdown.bottom, lessThanOrEqualTo(parent.bottom));
  for (final paragraph in _paragraphs(tester)) {
    final rect = paragraph.localToGlobal(Offset.zero) & paragraph.size;
    expect(rect.left, greaterThanOrEqualTo(markdown.left));
    expect(rect.right, lessThanOrEqualTo(markdown.right));
  }
}
