import 'package:anywork_client/workspace.dart';
import 'package:flutter/material.dart';

import '../../../app/theme/studio_tokens.dart';
import '../../../l10n/studio_l10n.dart';
import '../presentation/agent_status.dart';

/// Per-row Thread status, never the selected Conversation's busy flag. Waiting
/// for a person is static; only actual working states use a progress ring.
class ShellThreadStatusIndicator extends StatelessWidget {
  const ShellThreadStatusIndicator({required this.status, super.key});
  final ThreadStatus status;

  @override
  Widget build(BuildContext context) {
    if (status == ThreadStatus.idle) return const SizedBox.shrink();
    final label = context.threadStatusLabel(status);
    return Semantics(
      container: true,
      label: label,
      child: Tooltip(
        message: label,
        child: shellStatusWorking(status)
            ? SizedBox.square(
                dimension: 16,
                child: CircularProgressIndicator(
                  value: MediaQuery.disableAnimationsOf(context) ? .75 : null,
                  strokeWidth: 2,
                  strokeCap: StrokeCap.round,
                  color: context.statusColors.activeIndicator,
                ),
              )
            : Icon(
                switch (status) {
                  ThreadStatus.waitingInteraction => Icons.help_outline,
                  ThreadStatus.faulted => Icons.error_outline,
                  _ => Icons.check_circle_outline,
                },
                size: 16,
                color: shellThreadColor(context, status),
              ),
      ),
    );
  }
}

Color shellThreadColor(BuildContext context, ThreadStatus status) =>
    switch (status) {
      ThreadStatus.faulted => context.colors.error,
      ThreadStatus.waitingInteraction => context.statusColors.warning,
      ThreadStatus.queued ||
      ThreadStatus.running ||
      ThreadStatus.waitingTool ||
      ThreadStatus.cancelling ||
      ThreadStatus.closing => context.statusColors.activeIndicator,
      ThreadStatus.closed => context.colors.onSurfaceVariant.withValues(
        alpha: 0.72,
      ),
      ThreadStatus.idle => context.statusColors.success,
    };
