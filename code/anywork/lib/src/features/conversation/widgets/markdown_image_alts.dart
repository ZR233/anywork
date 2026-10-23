import 'package:gpt_markdown/gpt_markdown.dart';

Map<String, String> markdownImageAlts(String source) {
  final alts = <String, String>{};

  void visit(MdNode node) {
    if (node is MdImage) {
      alts.putIfAbsent(node.url, () => node.alt.trim());
      return;
    }
    final children = switch (node) {
      MdHeading(:final children) ||
      MdParagraph(:final children) ||
      MdBlockQuote(:final children) ||
      MdCheckbox(:final children) ||
      MdRadio(:final children) ||
      MdBold(:final children) ||
      MdItalic(:final children) ||
      MdStrike(:final children) ||
      MdUnderline(:final children) ||
      MdLink(:final children) => children,
      MdUnorderedList(:final items) || MdOrderedList(:final items) => [
        for (final item in items) ...item.children,
      ],
      MdTable(:final header, :final rows) => [
        for (final cell in header.cells) ...cell.content,
        for (final row in rows)
          for (final cell in row.cells) ...cell.content,
      ],
      MdFootnoteDefinitions(:final footnotes) => [
        for (final footnote in footnotes) ...footnote.children,
      ],
      MdText() ||
      MdCodeBlock() ||
      MdInlineCode() ||
      MdInlineLatex() ||
      MdBlockLatex() ||
      MdHorizontalRule() ||
      MdImage() ||
      MdSourceTag() ||
      MdFootnoteReference() ||
      MdLineBreak() ||
      MdCustomBlock() => const <MdNode>[],
    };
    for (final child in children) {
      visit(child);
    }
  }

  for (final node in Plusparse.parse(source).children) {
    visit(node);
  }
  return alts;
}
