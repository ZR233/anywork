import 'package:flutter/material.dart';

import '../../app/theme/studio_tokens.dart';

/// 详情悬浮表面的分区标题与内容容器。
///
/// 组件只负责排版：分区标题、键值行和列表行保持同一套字号、间距与细线，不拥有业务状态。
class StatusDetailPanel extends StatelessWidget {
  const StatusDetailPanel({
    required this.title,
    required this.children,
    super.key,
  });

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title.toUpperCase(),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: context.text.labelSmall?.copyWith(
            color: context.colors.onSurfaceVariant,
            fontSize: 9.5,
            fontWeight: FontWeight.w600,
            letterSpacing: 1,
          ),
        ),
        const SizedBox(height: 6),
        ...children,
      ],
    );
  }
}

/// 分区之间的细分隔线；只用于分隔同级事实，不作为装饰性边框。
class StatusDetailDivider extends StatelessWidget {
  const StatusDetailDivider({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: SizedBox(
        height: 1,
        child: ColoredBox(color: context.colors.outlineVariant),
      ),
    );
  }
}

class StatusDetailRow extends StatelessWidget {
  const StatusDetailRow({
    required this.label,
    required this.value,
    this.valueMaxLines = 2,
    this.valueKey,
    super.key,
  });

  final String label;
  final String value;
  final int valueMaxLines;
  final Key? valueKey;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2.5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 5,
            child: Text(
              label,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: context.text.bodySmall?.copyWith(
                color: context.colors.onSurfaceVariant,
                height: 1.25,
              ),
            ),
          ),
          const SizedBox(width: 12),
          // 紧约束的值槽让数字真正贴齐内容右边界；宽松槽只让 Text 自宽，右对齐会落在槽中间。
          Expanded(
            flex: 4,
            child: Text(
              value,
              key: valueKey,
              maxLines: valueMaxLines,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.right,
              style: context.text.bodySmall?.copyWith(
                color: context.colors.onSurface,
                fontWeight: FontWeight.w600,
                height: 1.25,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class StatusDetailIconRow extends StatelessWidget {
  const StatusDetailIconRow({
    required this.icon,
    required this.title,
    required this.detail,
    this.tone = StudioTone.neutral,
    super.key,
  });

  final IconData icon;
  final String title;
  final String detail;
  final StudioTone tone;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox.square(
            dimension: 22,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: tone.background(context),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Icon(icon, size: 13, color: tone.indicator(context)),
            ),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: title,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  TextSpan(text: ' · $detail'),
                ],
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: context.text.bodySmall?.copyWith(
                color: context.colors.onSurface,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class StatusDetailIconList extends StatelessWidget {
  const StatusDetailIconList({
    required this.icon,
    required this.title,
    required this.items,
    this.tone = StudioTone.neutral,
    this.itemKey,
    super.key,
  });

  final IconData icon;
  final String title;
  final List<String> items;
  final StudioTone tone;
  final Key Function(String item)? itemKey;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      label: title,
      value: items.join(', '),
      child: Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox.square(
              dimension: 22,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: tone.background(context),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Icon(icon, size: 13, color: tone.indicator(context)),
              ),
            ),
            const SizedBox(width: 9),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: context.text.bodySmall?.copyWith(
                      color: context.colors.onSurface,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  for (final item in items)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 3),
                      child: Text(
                        '• $item',
                        key: itemKey?.call(item),
                        style: context.text.bodySmall?.copyWith(
                          color: context.colors.onSurface,
                          height: 1.3,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
