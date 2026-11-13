import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

bool isTimelineContentLaidOut(Finder finder) {
  final elements = finder.evaluate();
  if (elements.length != 1) return false;
  final render = elements.single.findRenderObject();
  return render is RenderBox &&
      render.attached &&
      render.hasSize &&
      !render.size.isEmpty;
}

Future<void> revealTimelineTextFragment(
  WidgetTester tester,
  Finder finder,
  String fragment, {
  double alignment = 0.5,
  ScrollPosition? expectedScrollPosition,
}) async {
  expect(isTimelineContentLaidOut(finder), isTrue);
  // Consume the existing layout allowance before measuring the glyphs: an
  // admitted body can still be inside an expanding outer disclosure.
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  expect(tester.takeException(), isNull);
  expect(isTimelineContentLaidOut(finder), isTrue);
  final text = find.descendant(
    of: finder,
    matching: find.byWidgetPredicate(
      (widget) =>
          widget is RichText && widget.text.toPlainText().contains(fragment),
    ),
  );
  expect(text, findsOneWidget);
  final paragraph = tester.renderObject<RenderParagraph>(text);
  final start = paragraph.text.toPlainText().indexOf(fragment);
  expect(start, greaterThanOrEqualTo(0));
  final selection = TextSelection(
    baseOffset: start,
    extentOffset: start + fragment.length,
  );
  final boxes = paragraph.getBoxesForSelection(selection);
  expect(boxes, isNotEmpty);
  final bounds = boxes
      .map((box) => box.toRect())
      .reduce((left, right) => left.expandToInclude(right));
  final viewport = RenderAbstractViewport.of(paragraph);
  final position = Scrollable.of(tester.element(text)).position;
  if (expectedScrollPosition != null) {
    expect(position, same(expectedScrollPosition));
  }
  // Align the actual glyph range in its own viewport, centered by default.
  // Explicit edge alignment can reserve space for related content in Main.
  final reveal = viewport.getOffsetToReveal(paragraph, alignment, rect: bounds);
  await position.moveTo(reveal.offset, duration: Duration.zero);
  await tester.pump();
  expect(tester.takeException(), isNull);
  expect(tester.renderObject<RenderParagraph>(text), same(paragraph));
  // Preserve outward reveal for callers inside nested disclosures, using the
  // current glyph geometry rather than the pre-scroll measurement.
  final currentBounds = paragraph
      .getBoxesForSelection(selection)
      .map((box) => box.toRect())
      .reduce((left, right) => left.expandToInclude(right));
  paragraph.showOnScreen(rect: currentBounds);
  await tester.pump();
  expect(tester.takeException(), isNull);
  expect(tester.renderObject<RenderParagraph>(text), same(paragraph));
  expectTimelineTextFragmentVisible(tester, finder, fragment);
}

void expectTimelineTextFragmentVisible(
  WidgetTester tester,
  Finder finder,
  String fragment, {
  bool hitTestable = false,
}) {
  expect(isTimelineContentLaidOut(finder), isTrue);
  final text = find.descendant(
    of: finder,
    matching: find.byWidgetPredicate(
      (widget) =>
          widget is RichText && widget.text.toPlainText().contains(fragment),
    ),
  );
  expect(text, findsOneWidget);
  final paragraph = tester.renderObject<RenderParagraph>(text);
  final start = paragraph.text.toPlainText().indexOf(fragment);
  expect(start, greaterThanOrEqualTo(0));
  final boxes = paragraph.getBoxesForSelection(
    TextSelection(baseOffset: start, extentOffset: start + fragment.length),
  );
  expect(boxes, isNotEmpty);
  for (final box in boxes) {
    final local = box.toRect();
    final rect = Rect.fromPoints(
      paragraph.localToGlobal(local.topLeft),
      paragraph.localToGlobal(local.bottomRight),
    );
    RenderObject? ancestor = paragraph.parent;
    while (ancestor != null) {
      if ((ancestor is RenderClipRect || ancestor is RenderAbstractViewport) &&
          ancestor is RenderBox) {
        final viewport = (ancestor.localToGlobal(Offset.zero) & ancestor.size)
            .inflate(1);
        final diagnostic =
            '$fragment $rect in ${ancestor.runtimeType} $viewport; '
            '${Scrollable.maybeOf(tester.element(text))?.position}';
        expect(viewport.contains(rect.topLeft), isTrue, reason: diagnostic);
        expect(viewport.contains(rect.bottomRight), isTrue, reason: diagnostic);
      }
      ancestor = ancestor.parent;
    }
    if (hitTestable) {
      expect(
        tester
            .hitTestOnBinding(rect.center)
            .path
            .any((entry) => identical(entry.target, paragraph)),
        isTrue,
        reason:
            'The actual $fragment glyphs must be hit-testable, not the '
            'center of a larger multi-line text widget',
      );
    }
  }
}
