import 'package:flutter/material.dart';
import 'package:gpt_markdown/gpt_markdown.dart';

import '../../../../app/theme/studio_tokens.dart';
import '../../../../shared/studio_chrome.dart';
import 'timeline_plain_text.dart';

/// Official text surfaces cannot override remote images. Only syntax-free
/// messages use them; Markdown uses this public builder with explicit media
/// actions and the existing soft-wrapping code/table components. Never repair,
/// trim or insert characters into canonical text.
///
/// The autolink recognizer also claims bare emails (`a@b`), `mailto:`/`xmpp:`,
/// `<scheme:...>` and case-insensitive `www.` hosts. Those candidates must not
/// stay on the official text path where a global tap callback could hand them
/// a gesture, so plain `@`/`:` and any-casing `www.` route here too. A stray
/// colon or at-sign taking the Markdown path is acceptable; mutating canonical
/// text is not.
bool timelineNeedsSafeMarkdown(String text) =>
    text.contains('\n') ||
    text.contains('\r') ||
    RegExp(r'^(?: {0,3}(?:[-+]\s+|\d+[.)]\s+))').hasMatch(text) ||
    RegExp(r'[\\`*_\[\]()#>~!|]').hasMatch(text) ||
    text.contains('://') ||
    text.contains('@') ||
    text.contains(':') ||
    RegExp(r'www\.', caseSensitive: false).hasMatch(text);

class TimelineMarkdown extends StatelessWidget {
  const TimelineMarkdown({
    super.key,
    required this.id,
    required this.text,
    required this.onLink,
    required this.isSafeLink,
    required this.imageBuilder,
  });
  final String id;
  final String text;
  final ValueChanged<String> onLink;
  final bool Function(String) isSafeLink;
  final Widget Function(BuildContext, String) imageBuilder;

  @override
  Widget build(BuildContext context) {
    final style = context.text.bodyMedium?.copyWith(height: 1.57);
    if (!timelineNeedsSafeMarkdown(text)) {
      return TimelinePlainText(id: id, text: text, style: style);
    }
    return GptMarkdown(
      text,
      key: ValueKey('gpt-markdown-$id'),
      style: style,
      // No global onLinkTap: unsafe targets must keep their text without any
      // gesture instead of relying on a final callback to refuse the launch.
      inlineLinkBuilder: (link) {
        if (!isSafeLink(link.url)) {
          return TextSpan(children: link.labelSpans, style: link.style);
        }
        return LinkTextSpan.wrapping(
          children: link.labelSpans,
          url: link.url,
          linkStyle: link.linkStyle,
          style: link.style,
          hoverStyle: link.hoverStyle,
          onTap: () => onLink(link.url),
        );
      },
      inlineSourceTagBuilder: (tag) {
        final url = tag.url;
        return SourceTagBuildDetails(
          context: tag.context,
          config: tag.config,
          style: tag.style,
          id: tag.id,
          url: url,
          sourceTagStyle: tag.sourceTagStyle,
          onTap: url != null && isSafeLink(url) ? () => onLink(url) : null,
        ).defaultSpan();
      },
      imageBuilder: (context, url, _, _) => imageBuilder(context, url),
      styleSheet: GptMarkdownStyleSheet(
        table: TableStyle(
          overflow: TableOverflow.wrap,
          borderColor: context.colors.outlineVariant,
          headerBackground: context.colors.surfaceContainerLow,
          headerTextStyle: const TextStyle(fontWeight: FontWeight.w600),
          cellPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        ),
      ),
      inlineCodeStyle: InlineCodeStyle(
        fontFamily: studioCodeFontFamily,
        borderWidth: 0,
        backgroundColor: context.colors.surfaceContainerLow,
      ),
      codeBuilder: (context, name, code, closed) => StudioCodeBlock(
        text: code,
        horizontalScroll: false,
        margin: EdgeInsets.zero,
        padding: const EdgeInsets.all(16),
        backgroundColor: context.colors.surfaceContainerLow,
        borderColor: context.colors.outlineVariant,
        borderRadius: const Radius.circular(StudioRadii.sm),
        textStyle: style?.copyWith(fontFamily: studioCodeFontFamily),
      ),
    );
  }
}
