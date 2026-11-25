import 'package:anywork_client/statistics.dart';
import 'package:material_ui/material_ui.dart';

import '../../../../app/theme/studio_tokens.dart';
import '../../../../l10n/studio_l10n.dart';

/// A failed explicit read keeps its previous content and offers another refresh.
class StatisticsConnectionStatus extends StatelessWidget {
  const StatisticsConnectionStatus({
    required this.state,
    required this.onRefresh,
    super.key,
  });

  final StatisticsConnectionState state;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    if (state.phase != StatisticsConnectionPhase.failed) {
      return const SizedBox.shrink();
    }
    final message = state.failure?.message.trim();
    final label = (message == null || message.isEmpty)
        ? context.l10n.settingsStatisticsReadFailedTitle
        : message;
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Icon(Icons.error_outline, size: 16, color: context.colors.error),
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
          TextButton.icon(
            key: const ValueKey('settings-topic-retry-ModelPerformanceTopic'),
            onPressed: onRefresh,
            icon: const Icon(Icons.refresh, size: 16),
            label: Text(context.l10n.sidebarRetry),
          ),
        ],
      ),
    );
  }
}

/// 统计投影的轻量状态行：gap/readFailed 只在固定页头占一行，避免正文顶部反复插拔
/// 大块导致布局跳动；pending（保存中暂态）不做可见展示。
class StatisticsStatusLine extends StatelessWidget {
  const StatisticsStatusLine({required this.snapshot, super.key});

  final StatisticsSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final items = <Widget>[
      if (snapshot.readFailed)
        _StatisticsStatusItem(
          key: const ValueKey('statistics-status-read-failed'),
          icon: Icons.error_outline,
          label: context.l10n.settingsStatisticsReadFailedTitle,
          color: context.colors.error,
        ),
      if (snapshot.statisticsGap)
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
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 15, color: color),
        const SizedBox(width: 6),
        Text(label, style: context.text.bodySmall?.copyWith(color: color)),
      ],
    );
  }
}
