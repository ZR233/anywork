import 'package:flutter/material.dart';

import '../../../l10n/studio_l10n.dart';
import '../../../ui/formatters/throughput_format.dart';
import '../../../ui/status/status_bar_item.dart';
import '../state/thread_metrics_state.dart';

class ThreadMetricsView extends StatelessWidget {
  const ThreadMetricsView({
    required this.state,
    required this.onRetry,
    super.key,
  });
  final ThreadMetricsViewState state;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final formatted = formatTokenThroughputValue(state.tokensPerSecond);
    final error = state.error ?? state.source?.sync.error;
    return StatusBarItem(
      label: formatted == null
          ? context.l10n.statusThroughputUnavailable
          : context.l10n.statusThroughputValue(formatted),
      icon: Icons.speed,
      detailBuilder: (context) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(context.l10n.statisticsSpeed),
          Text(context.l10n.settingsStatisticsThroughputNote),
          if (error != null) ...[
            Text(error.message),
            TextButton(
              onPressed: state.retrying ? null : onRetry,
              child: Text(context.l10n.sidebarRetry),
            ),
          ],
        ],
      ),
    );
  }
}
