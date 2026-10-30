import 'package:flutter/material.dart';
import 'package:gpt_markdown/gpt_markdown.dart';

import '../../../../app/theme/studio_tokens.dart';
import '../../../../shared/studio_chrome.dart';
import 'timeline_plain_text.dart';

/// Shared body renderer for completed and streaming text. Only syntax-free
/// messages use standard Flutter Text; Markdown uses the public builder
/// with explicit media actions and the existing soft-wrapping code/table
/// components. Never repair, trim or insert characters into canonical text.
///
/// Newlines, indentation, colons and bare emails do not opt ordinary text into
/// Markdown: its native Text selection preserves the complete source. Markdown
/// and autolink candidates use the renderer's safe-link predicate for gestures.
bool timelineNeedsSafeMarkdown(String text) =>
    // A leading dash/plus may start a list or a thematic break (`---`).
    // Route candidates, not a second Markdown parser: GptMarkdown decides.
    RegExp(r'^ {0,3}(?:[-+]|\d+[.)]\s+)', multiLine: true).hasMatch(text) ||
    RegExp(r'[\\`*_\[\]()#>~!|]').hasMatch(text) ||
    text.contains('://') ||
    RegExp(r'www\.', caseSensitive: false).hasMatch(text);

class TimelineMarkdown extends StatelessWidget {
  const TimelineMarkdown({
    super.key,
    required this.id,
    required this.text,
    required this.onLink,
    required this.isSafeLink,
    required this.imageBuilder,
    this.style,
    this.maxLines,
    this.overflow,
  });
  final String id;
  final String text;
  final ValueChanged<String> onLink;
  final bool Function(String) isSafeLink;
  final Widget Function(BuildContext, String) imageBuilder;
  final TextStyle? style;
  final int? maxLines;
  final TextOverflow? overflow;

  @override
  Widget build(BuildContext context) {
    final textStyle = style ?? context.text.bodyMedium?.copyWith(height: 1.57);
    if (maxLines == null && !timelineNeedsSafeMarkdown(text)) {
      return TimelinePlainText(id: id, text: text, style: textStyle);
    }
    return DefaultTextStyle.merge(
      softWrap: true,
      child: GptMarkdown(
        text,
        key: ValueKey('gpt-markdown-$id'),
        style: textStyle,
        maxLines: maxLines,
        overflow: overflow,
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
            cellPadding: const EdgeInsets.symmetric(
              horizontal: 10,
              vertical: 8,
            ),
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
      ),
    );
  }
}
