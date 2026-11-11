import 'package:material_ui/material_ui.dart';

import '../../../../app/theme/studio_tokens.dart';
import '../state/patch_presentation.dart';

/// apply_patch 参数/窗口正文到修改片段的统一入口。
///
/// 正文为空时返回 null（沿用普通空态）；无法完整解析时返回明确的不可用
/// 提示，不回退原始参数或控制标记（design/26 §26.9.1）。
Widget? timelineApplyPatchBody(String raw) {
  if (raw.trim().isEmpty) return null;
  final document = parseTimelinePatch(timelineApplyPatchSource(raw));
  if (document == null) return const TimelinePatchUnavailableHint();
  return TimelinePatchDiffView(document: document);
}

/// 已声明正文窗口（toolArguments 的有界段）适配 TimelineBodyReadIntent：
/// 窗口已有内容，空段同样按不可完整解析提示，不回退原文。
Widget timelineApplyPatchWindowBody(String text) {
  return timelineApplyPatchBody(text) ?? const TimelinePatchUnavailableHint();
}

/// 截断窗口、缺失片段归属或不支持语法时的统一提示。
class TimelinePatchUnavailableHint extends StatelessWidget {
  const TimelinePatchUnavailableHint({super.key});

  @override
  Widget build(BuildContext context) {
    return Text(
      '补丁片段不可用：内容不完整或无法完整解析',
      style: context.text.bodySmall?.copyWith(
        color: context.colors.onSurfaceVariant,
      ),
    );
  }
}

/// 按文件与片段呈现请求中的修改：新增整行绿底 `+`、删除整行红底 `-`、
/// 上下文中性底；行背景铺满代码面板并在长行横滚时跟随内容宽度，正文
/// 保持可选择复制，片段之间用中性省略分隔，不虚构原文件行号。
class TimelinePatchDiffView extends StatelessWidget {
  const TimelinePatchDiffView({required this.document, super.key});

  final TimelinePatchDocument document;

  @override
  Widget build(BuildContext context) {
    final sections = <Widget>[];
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final additionBackground = isDark ? _darkAddition : _lightAddition;
    final deletionBackground = isDark ? _darkDeletion : _lightDeletion;
    final additionMarker = isDark ? _darkAdditionMarker : _lightAdditionMarker;
    final deletionMarker = isDark ? _darkDeletionMarker : _lightDeletionMarker;
    final codeStyle = context.text.bodySmall?.copyWith(
      color: context.colors.onSurface,
      fontFamily: studioCodeFontFamily,
      height: 1.5,
    );
    for (var fileIndex = 0; fileIndex < document.files.length; fileIndex++) {
      final file = document.files[fileIndex];
      if (fileIndex > 0) sections.add(const SizedBox(height: 12));
      sections.add(
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: _fileHeader(context, file),
        ),
      );
      sections.add(const SizedBox(height: 4));
      for (var chunkIndex = 0; chunkIndex < file.chunks.length; chunkIndex++) {
        final chunk = file.chunks[chunkIndex];
        if (chunkIndex > 0) sections.add(_chunkDivider(context));
        if (chunk.context case final header? when header.isNotEmpty) {
          sections.add(
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Text(
                header,
                style: codeStyle?.copyWith(
                  color: context.colors.onSurfaceVariant,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ),
          );
        }
        for (final line in chunk.lines) {
          sections.add(
            _lineRow(
              context,
              line,
              codeStyle,
              additionBackground,
              additionMarker,
              deletionBackground,
              deletionMarker,
            ),
          );
        }
      }
    }
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: context.colors.surfaceContainerLow,
        borderRadius: const BorderRadius.all(Radius.circular(8)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          // 行背景至少铺满可见面板；内容更长时随横滚一起延展。
          final content = IntrinsicWidth(
            child: ConstrainedBox(
              constraints: BoxConstraints(minWidth: constraints.maxWidth),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: sections,
              ),
            ),
          );
          final scrolled = SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: content,
          );
          // 已处于文档级选择容器时加入同一选择；否则建立独立跨行选择区。
          return SelectionContainer.maybeOf(context) == null
              ? SelectionArea(child: scrolled)
              : scrolled;
        },
      ),
    );
  }

  Widget _fileHeader(BuildContext context, TimelinePatchFile file) {
    final (label, color) = switch (file.op) {
      TimelinePatchFileOp.add => ('新增', _markerColor(context, true)),
      TimelinePatchFileOp.update => ('更新', context.colors.primary),
      TimelinePatchFileOp.delete => ('删除', _markerColor(context, false)),
    };
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.14),
            borderRadius: const BorderRadius.all(Radius.circular(6)),
          ),
          child: Text(
            label,
            style: context.text.labelSmall?.copyWith(
              color: color,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            file.moveTo == null ? file.path : '${file.path} → ${file.moveTo}',
            overflow: TextOverflow.ellipsis,
            maxLines: 1,
            style: context.text.labelSmall?.copyWith(
              color: context.colors.onSurface,
              fontWeight: FontWeight.w600,
              fontFamily: studioCodeFontFamily,
            ),
          ),
        ),
      ],
    );
  }

  Widget _chunkDivider(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Center(
        child: Text(
          '⋯',
          style: context.text.labelSmall?.copyWith(
            color: context.colors.onSurfaceVariant,
          ),
        ),
      ),
    );
  }

  Widget _lineRow(
    BuildContext context,
    TimelinePatchLine line,
    TextStyle? codeStyle,
    Color additionBackground,
    Color additionMarker,
    Color deletionBackground,
    Color deletionMarker,
  ) {
    final (marker, background, markerStyle) = switch (line.kind) {
      TimelinePatchLineKind.addition => (
        '+',
        additionBackground,
        codeStyle?.copyWith(color: additionMarker, fontWeight: FontWeight.w600),
      ),
      TimelinePatchLineKind.deletion => (
        '-',
        deletionBackground,
        codeStyle?.copyWith(color: deletionMarker, fontWeight: FontWeight.w600),
      ),
      TimelinePatchLineKind.context => (' ', null, codeStyle),
    };
    Widget row = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: Text.rich(
        TextSpan(
          children: [
            TextSpan(text: '$marker ', style: markerStyle),
            TextSpan(text: line.text),
          ],
        ),
        style: codeStyle,
      ),
    );
    // 行背景铺满面板宽度；上下文行保持中性面板底色。
    return background == null ? row : ColoredBox(color: background, child: row);
  }

  Color _markerColor(BuildContext context, bool addition) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return isDark
        ? (addition ? _darkAdditionMarker : _darkDeletionMarker)
        : (addition ? _lightAdditionMarker : _lightDeletionMarker);
  }
}

const _lightAddition = Color(0x24388E3C);
const _lightAdditionMarker = Color(0xFF1B5E20);
const _lightDeletion = Color(0x24D32F2F);
const _lightDeletionMarker = Color(0xFFB71C1C);
const _darkAddition = Color(0x3D66BB6A);
const _darkAdditionMarker = Color(0xFF81C784);
const _darkDeletion = Color(0x42EF5350);
const _darkDeletionMarker = Color(0xFFE57373);
