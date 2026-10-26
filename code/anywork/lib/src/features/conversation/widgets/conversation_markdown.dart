import 'package:flutter/material.dart';
import 'package:gpt_markdown/gpt_markdown.dart';

import '../../../app/theme/studio_tokens.dart';
import '../../../ui/content/studio_code_block.dart';
import 'markdown_style.dart';
import 'plain_body_text.dart';
import 'markdown_repair.dart';
import 'markdown_image_alts.dart';

export 'markdown_style.dart' show MarkdownSurface;

// 原始字符串（r''）把 \r \n \\ \[ \] 作为**转义**交给 RegExp，因此这里匹配真实 CR/LF、
// 反斜杠与 markdown 符号（反引号、* _ [ ] ( ) # > ~ ! |），而不是字母 r/n；含换行的
// 正文因此走 Markdown 分支。非原始字符串里 \r/\n 会变成真实控制字符、\[ 还会成为非法
// 转义，所以这里必须保持 raw。
final RegExp _streamingMarkdownSyntax = RegExp(r'[\r\n\\`*_\[\]()#>~!|]');

class ConversationMarkdown extends StatefulWidget {
  const ConversationMarkdown({
    required this.id,
    required this.text,
    required this.surface,
    this.onLink,
    this.linkAllowed,
    this.imageBuilder,
    super.key,
  });

  final String id;
  final String text;
  final MarkdownSurface surface;
  final ValueChanged<String>? onLink;
  final bool Function(String)? linkAllowed;
  final Widget Function(BuildContext, String, String)? imageBuilder;

  @override
  State<ConversationMarkdown> createState() => ConversationMarkdownState();
}

class ConversationMarkdownState extends State<ConversationMarkdown> {
  GptMarkdownThemeData? _headingTheme;

  @override
  Widget build(BuildContext context) {
    final ConversationMarkdown(:id, :text, :surface) = widget;
    final plainText =
        !_streamingMarkdownSyntax.hasMatch(text) &&
        !text.contains('://') &&
        !text.contains('www.');
    if (plainText) {
      return PlainBodyText(
        key: ValueKey('plain-$id'),
        id: id,
        text: text,
        surface: surface,
      );
    }
    final repaired = repairAgentMarkdownForDisplay(text);
    final imageAlts = repaired.contains('![')
        ? markdownImageAlts(repaired)
        : const <String, String>{};
    final scheme = Theme.of(context).colorScheme;
    final onUserSurface = surface == MarkdownSurface.user;
    final headingTheme = GptMarkdownTheme.of(context).copyWith(
      h1: _timelineHeadingStyle(context, surface, 2.0),
      h2: _timelineHeadingStyle(context, surface, 1.5),
      h3: _timelineHeadingStyle(context, surface, 1.25),
      h4: _timelineHeadingStyle(context, surface, 1.0),
      h5: _timelineHeadingStyle(context, surface, 0.875),
      h6: _timelineHeadingStyle(context, surface, 0.85),
    );
    // The package notifies dependants by theme identity. Retain an equivalent
    // configuration so unrelated window updates do not discard its text caches.
    if (_headingTheme?.isSame(headingTheme) != true) {
      _headingTheme = headingTheme;
    }
    return GptMarkdownTheme(
      // VS Code 预览的标题阶梯：全部 w600、line-height 1.25，字级按正文字号
      // 相对递进（2/1.5/1.25/1/0.875/0.85em）。只能在 GptMarkdownThemeData
      // 上按级提供；用局部 InheritedWidget 覆盖，不改动全局主题。
      gptThemeData: _headingTheme!,
      child: GptMarkdown(
        repaired,
        key: ValueKey('gpt-markdown-$id'),
        style: markdownBodyStyle(context, surface),
        styleSheet: GptMarkdownStyleSheet(
          blockQuote: BlockQuoteStyle(
            textStyle: TextStyle(
              color: context.colors.onSurfaceVariant,
              height: 1.57,
            ),
          ),
          heading: HeadingStyle(
            // 仅做随表面的语义色覆盖；节奏与 H1/H2 分隔线由 headingBuilder 提供。
            textStyle: switch (surface) {
              MarkdownSurface.reasoning => TextStyle(
                color: context.colors.onSurfaceVariant,
              ),
              MarkdownSurface.error => TextStyle(color: scheme.error),
              _ => null,
            },
          ),
          list: ListStyle(
            // 有序/无序列表统一标记距离；标记色弱化，正文保持主导。
            indent: 8,
            gapAfterMarker: 8,
            bulletColor: scheme.onSurfaceVariant,
            markerTextStyle: TextStyle(
              fontWeight: FontWeight.w500,
              color: scheme.onSurfaceVariant,
            ),
          ),
          table: TableStyle(
            // 原生列宽分配在阅读列内折行，短列保留内容宽度，长代码也能断行。
            overflow: TableOverflow.wrap,
            borderColor: scheme.outlineVariant,
            headerBackground: scheme.surfaceContainerLow,
            headerTextStyle: const TextStyle(fontWeight: FontWeight.w600),
            cellPadding: const EdgeInsets.symmetric(
              horizontal: 10,
              vertical: 8,
            ),
          ),
        ),
        headingBuilder: (context, level, content, style) {
          final bodySize = markdownBodyStyle(context, surface)?.fontSize ?? 14;
          // VS Code 预览节奏：块间空行承担约一段距（≈1.15em），标题只补
          // margin-top 24px（相对正文 ≈1.7em）；H3-H6 底距交还空行节奏。
          // H1/H2 自带 0.3em 底距与 1px 轻分隔线（padding 在线之上）。
          // 选择顺序：标题整树包 _HeadingSelectionUnit 作为块级选择单元，
          // 外层选择区域见块级边界而非窄标题文本盒，几何排序不再因文本
          // 盒 top 偏移把标题排到后续正文之后（复制错序）。
          final topPadding = bodySize * 24 / 14;
          final Widget heading;
          if (level > 2) {
            heading = LayoutBuilder(
              builder: (context, constraints) {
                // 有界阅读列内标题占满列宽，块级选择边界覆盖整行；
                // 无界约束保持内容宽度，避免 infinity 布局错误。
                return constraints.hasBoundedWidth
                    ? SizedBox(width: double.infinity, child: content)
                    : content;
              },
            );
          } else {
            final headingSize = bodySize * (level == 1 ? 2.0 : 1.5);
            heading = LayoutBuilder(
              builder: (context, constraints) {
                final rule = DecoratedBox(
                  decoration: BoxDecoration(
                    border: Border(
                      bottom: BorderSide(
                        color: Theme.of(context).colorScheme.outlineVariant,
                        width: 1,
                      ),
                    ),
                  ),
                  child: Padding(
                    padding: EdgeInsets.only(bottom: headingSize * 0.3),
                    child: content,
                  ),
                );
                // 有界阅读列内底线占满列宽、内容保持起始对齐；
                // 无界约束保持内容宽度，避免 infinity 布局错误。
                return constraints.hasBoundedWidth
                    ? SizedBox(width: double.infinity, child: rule)
                    : rule;
              },
            );
          }
          return _HeadingSelectionUnit(
            child: Padding(
              padding: EdgeInsets.only(top: topPadding),
              child: heading,
            ),
          );
        },
        onLinkTap: (url, _) {
          widget.onLink?.call(url);
        },
        inlineLinkBuilder: (link) => widget.linkAllowed?.call(link.url) != true
            ? TextSpan(children: link.labelSpans, style: link.style)
            : link.defaultSpan(),
        inlineCodeStyle: InlineCodeStyle(
          // 与其他代码表面共用包注册字体，中文缺失字形由系统回退。
          fontFamily: studioCodeFontFamily,
          fontSizeFactor: 1.0,
          color: scheme.onSurface,
          backgroundColor: onUserSurface
              ? scheme.surfaceContainerLowest
              : scheme.surfaceContainerLow,
          // 只用轻底色区分，去掉描边和加粗，避免打断中文阅读基线。
          borderWidth: 0,
          borderRadius: Radius.circular(5),
          padding: const EdgeInsets.symmetric(horizontal: 5.5, vertical: 1.5),
        ),
        // VS Code 预览引用：常规左侧线 + 低对比背景，无垂直外边距
        // （块间空行已承担节奏），内边距 0 16 0 10、小圆角。
        blockQuoteBuilder: (context, content, style) => LayoutBuilder(
          builder: (context, constraints) {
            final card = DecoratedBox(
              key: const ValueKey('studio-markdown-quote'),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerLowest,
                border: BorderDirectional(
                  start: BorderSide(color: scheme.outlineVariant, width: 5),
                ),
                borderRadius: BorderRadius.circular(2),
              ),
              child: Padding(
                padding: const EdgeInsetsDirectional.fromSTEB(10, 0, 16, 0),
                child: content,
              ),
            );
            // 宽度有界时占满可用宽度，与其他块级内容右边缘对齐；
            // 无界约束（如横向滚动内）保持内容宽度，避免 infinity 布局错误。
            return constraints.hasBoundedWidth
                ? SizedBox(width: double.infinity, child: card)
                : card;
          },
        ),
        imageBuilder: (context, url, _, _) =>
            widget.imageBuilder?.call(context, url, imageAlts[url] ?? '') ??
            Text(imageAlts[url] ?? url),
        codeBuilder: (context, name, code, closed) {
          final scheme = Theme.of(context).colorScheme;
          final textTheme = Theme.of(context).textTheme;
          // VS Code 预览代码区：低对比背景 + 1px 边框，不显示语言栏；
          // 垂直节奏交还块间空行。
          final codeBackground = onUserSurface
              ? scheme.surfaceContainerHigh
              : scheme.surfaceContainerLow;
          final bodyStyle = surface == MarkdownSurface.reasoning
              ? textTheme.bodySmall
              : textTheme.bodyMedium;
          return StudioCodeBlock(
            text: code,
            horizontalScroll: false,
            margin: EdgeInsets.zero,
            padding: const EdgeInsets.all(16),
            backgroundColor: codeBackground,
            borderColor: scheme.outlineVariant,
            borderRadius: const Radius.circular(StudioRadii.sm),
            textStyle: bodyStyle?.copyWith(
              color: surface == MarkdownSurface.reasoning
                  ? context.colors.onSurfaceVariant
                  : surface == MarkdownSurface.error
                  ? scheme.error
                  : scheme.onSurface,
              fontSize: bodyStyle.fontSize ?? 14,
              height: 1.36,
            ),
          );
        },
      ),
    );
  }

  /// VS Code 预览标题：相对所在 surface 正文字号的递进字级（em），
  /// 全部 w600、line-height 1.25；从全局正文字体派生保持家族继承。
  TextStyle? _timelineHeadingStyle(
    BuildContext context,
    MarkdownSurface surface,
    double em,
  ) {
    final bodySize = markdownBodyStyle(context, surface)?.fontSize ?? 14;
    return Theme.of(context).textTheme.bodyMedium?.copyWith(
      fontSize: bodySize * em,
      fontWeight: FontWeight.w600,
      height: 1.25,
    );
  }
}

/// 标题的块级选择单元：内层标题文本注册到局部
/// [StaticSelectionContainerDelegate]，外层选择区域只见 [SelectionContainer]
/// 的 RenderBox 边界（paintBounds，覆盖标题完整 padding 与底线），而不是
/// 窄标题文本盒——几何选择排序因此把标题当作与后续正文平级的块单元，
/// 不会因文本盒 top 偏移把标题排到正文之后（复制错序）。标题仍参与外层
/// 连续选择：委托嵌套是 SDK 官方用法（SelectableRegion 自身即用
/// SelectionContainer 嵌套委托），不通过独立文本编辑控件隔离标题，也不
/// 改变全局选择排序。
class _HeadingSelectionUnit extends StatefulWidget {
  const _HeadingSelectionUnit({required this.child});

  final Widget child;

  @override
  State<_HeadingSelectionUnit> createState() => _HeadingSelectionUnitState();
}

class _HeadingSelectionUnitState extends State<_HeadingSelectionUnit> {
  // State 拥有 delegate 生命周期（create once / dispose），与 SDK
  // SelectionListenerContainer 同构：SelectionContainer 自身 dispose 时
  // 只清理引用，不负责销毁 delegate。
  final StaticSelectionContainerDelegate _delegate =
      StaticSelectionContainerDelegate();

  @override
  void dispose() {
    _delegate.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SelectionContainer(delegate: _delegate, child: widget.child);
  }
}
