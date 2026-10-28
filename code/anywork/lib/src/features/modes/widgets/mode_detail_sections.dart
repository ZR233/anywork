import 'package:flutter/material.dart';

import '../../../app/theme/studio_tokens.dart';

/// 阶段和转换详情共用的信息层级，不持有文档或编辑状态。
class ModeDetailSection extends StatelessWidget {
  const ModeDetailSection({
    super.key,
    required this.title,
    required this.child,
  });

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 20),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Divider(height: 1, color: context.colors.outlineVariant),
        const SizedBox(height: 20),
        Text(
          title,
          style: context.text.titleSmall?.copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 12),
        child,
      ],
    ),
  );
}

class ModeDetailReadOnlyNotice extends StatelessWidget {
  const ModeDetailReadOnlyNotice({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(24, 12, 24, 20),
    child: DecoratedBox(
      decoration: BoxDecoration(
        color: context.colors.surfaceContainer,
        borderRadius: BorderRadius.circular(StudioRadii.sm),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Icon(Icons.lock_outline, size: 18, color: context.colors.primary),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                text,
                style: context.text.bodySmall?.copyWith(
                  color: context.colors.onSurfaceVariant,
                  height: 1.5,
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class ModeDetailStageLink extends StatelessWidget {
  const ModeDetailStageLink({
    super.key,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.icon = Icons.account_tree_outlined,
    this.trailing,
  });

  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final IconData icon;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Card.outlined(
    margin: const EdgeInsets.only(bottom: 8),
    color: context.colors.surface,
    child: ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      leading: Icon(icon, size: 22, color: context.colors.primary),
      title: Text(
        title,
        style: context.text.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
      ),
      subtitle: Text(
        subtitle,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: context.text.bodySmall?.copyWith(
          color: context.colors.onSurfaceVariant,
          height: 1.5,
        ),
      ),
      trailing: trailing ?? const Icon(Icons.chevron_right, size: 18),
      onTap: onTap,
    ),
  );
}
