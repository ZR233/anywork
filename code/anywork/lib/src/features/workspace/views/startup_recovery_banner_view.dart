import 'package:anywork_client/resources.dart';
import 'package:anywork_client/workspace.dart';
import 'package:flutter/material.dart';

import '../../../l10n/studio_l10n.dart';
import '../widgets/workspace_failure_notice.dart';

class StartupRecoveryBannerView extends StatelessWidget {
  const StartupRecoveryBannerView({
    required this.recovery,
    required this.failure,
    required this.onDismiss,
    required this.onRetry,
    super.key,
  });
  final StartupRecovery? recovery;
  final StudioFailure? failure;
  final VoidCallback onDismiss;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final report = recovery;
    if (failure case final error?) {
      return WorkspaceFailureNotice(failure: error, onRetry: onRetry);
    }
    if (report == null) return const SizedBox.shrink();
    return ColoredBox(
      key: const ValueKey('startup-recovery-report'),
      color: Theme.of(context).colorScheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(context.l10n.startupRecoveredNotice),
                  SelectableText('${report.reason}\n${report.backupPath}'),
                ],
              ),
            ),
            IconButton(
              tooltip: context.l10n.recoveryArchiveDismiss,
              onPressed: onDismiss,
              icon: const Icon(Icons.close),
            ),
          ],
        ),
      ),
    );
  }
}
