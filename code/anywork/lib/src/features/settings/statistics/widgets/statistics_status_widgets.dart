import 'package:anywork_client/resources.dart';
import 'package:flutter/material.dart';

import '../../../../app/theme/studio_tokens.dart';
import '../../../../l10n/studio_l10n.dart';

/// 统计投影的轻量状态行：gap/readFailed 只在固定页头占一行，避免正文顶部反复插拔
/// 大块导致布局跳动；pending（保存中暂态）不做可见展示。
class StatisticsStatusLine extends StatelessWidget {
  const StatisticsStatusLine({
    required this.readFailed,
    required this.gap,
    super.key,
  });

  final bool readFailed;
  final bool gap;

  @override
  Widget build(BuildContext context) {
    final items = <Widget>[
      if (readFailed)
        _StatisticsStatusItem(
          key: const ValueKey('statistics-status-read-failed'),
          icon: Icons.error_outline,
          label: context.l10n.settingsStatisticsReadFailedTitle,
          color: context.colors.error,
        ),
      if (gap)
        _StatisticsStatusItem(
          key: const ValueKey('statistics-status-gap'),
          icon: Icons.warning_amber_rounded,
          label: context.l10n.settingsStatisticsGapTitle,
          color: context.statusColors.warning,
        ),
    ];
    if (items.isEmpty) return const SizedBox.shrink();
    return Wrap(spacing: 16, runSpacing: 4, children: items);
  }
}

/// Statistics-owned connection status with the established topic-status geometry
/// and retry behaviour: a routine connecting/idle/ready phase stays invisible,
/// and only a real failure offers the domain's read-only re-sync. It is not a
/// resident health line and shows no paging affordance.
class StatisticsConnectionStatus extends StatelessWidget {
  const StatisticsConnectionStatus({
    required this.sync,
    required this.onRetry,
    super.key,
  });

  final ResourceSyncState sync;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    if (sync.phase == ResourceSyncPhase.idle ||
        sync.phase == ResourceSyncPhase.connecting ||
        sync.phase == ResourceSyncPhase.ready) {
      return const SizedBox.shrink();
    }
    final failed = sync.phase == ResourceSyncPhase.failed;
    final message = sync.error?.message.trim();
    final label = (message == null || message.isEmpty)
        ? (failed
              ? context.l10n.settingsSshStateFailed
              : context.l10n.settingsSshStateReconnecting)
        : message;
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Icon(
            failed ? Icons.error_outline : Icons.sync_problem_outlined,
            size: 16,
            color: failed ? context.colors.error : context.statusColors.warning,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: context.text.bodySmall?.copyWith(
                color: context.colors.onSurfaceVariant,
              ),
            ),
          ),
          if (failed)
            TextButton.icon(
              key: const ValueKey('settings-topic-retry-ModelPerformanceTopic'),
              onPressed: onRetry,
              icon: const Icon(Icons.refresh, size: 16),
              label: Text(context.l10n.sidebarRetry),
            ),
        ],
      ),
    );
  }
}

class _StatisticsStatusItem extends StatelessWidget {
  const _StatisticsStatusItem({
    required this.icon,
    required this.label,
    required this.color,
    super.key,
  });

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(icon, size: 15, color: color),
      const SizedBox(width: 6),
      Text(label, style: context.text.bodySmall?.copyWith(color: color)),
    ],
  );
}
