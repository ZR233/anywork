import 'package:flutter/material.dart';
import 'package:gpt_markdown/gpt_markdown.dart';

import '../../../../app/theme/studio_tokens.dart';
import '../../../../shared/studio_chrome.dart';
import 'timeline_plain_text.dart';

/// Standard Text preserves syntax-free paragraphs, including their whitespace.
/// Markdown and link candidates use the public renderer with explicit safe
/// actions and the existing wrapping code/table components.
bool timelineNeedsSafeMarkdown(String text) =>
    RegExp(
      r'^(?: {0,3}(?:[-+]\s+|\d+[.)]\s+))',
      multiLine: true,
    ).hasMatch(text) ||
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
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxWidth = constraints.maxWidth;
        final bounded = maxWidth.isFinite;
        Widget markdown = GptMarkdown(
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
          codeBuilder: (context, name, code, closed) {
            final block = StudioCodeBlock(
              text: code,
              horizontalScroll: false,
              margin: EdgeInsets.zero,
              padding: const EdgeInsets.all(16),
              backgroundColor: context.colors.surfaceContainerLow,
              borderColor: context.colors.outlineVariant,
              borderRadius: const Radius.circular(StudioRadii.sm),
              textStyle: style?.copyWith(fontFamily: studioCodeFontFamily),
            );
            return bounded ? SizedBox(width: maxWidth, child: block) : block;
          },
        );
        if (!bounded) return markdown;
        return ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth),
          child: markdown,
        );
      },
    );
  }
}
