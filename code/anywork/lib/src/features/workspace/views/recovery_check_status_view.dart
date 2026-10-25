import 'package:anywork_client/resources.dart';
import 'package:flutter/material.dart';

import '../../../l10n/studio_l10n.dart';

class RecoveryCheckStatusView extends StatelessWidget {
  const RecoveryCheckStatusView({
    required this.status,
    required this.sourceError,
    required this.readError,
    required this.retryPending,
    required this.onRetry,
    this.showChecking = false,
    super.key,
  });
  final ObservedBrief? status;
  final SourceStateError? sourceError;
  final StudioFailure? readError;
  final bool retryPending;
  final VoidCallback onRetry;
  final bool showChecking;

  @override
  Widget build(BuildContext context) {
    final checking =
        status is LoadingObservedBrief || status is RefreshingObservedBrief;
    final failed =
        status is FailedObservedBrief ||
        status is DegradedObservedBrief ||
        readError != null;
    if (!(showChecking && checking) && !failed) return const SizedBox.shrink();
    final retryable = switch (status) {
      FailedObservedBrief(:final retryable) ||
      DegradedObservedBrief(:final retryable) => retryable,
      _ => readError?.retryable == true,
    };
    return Material(
      key: const ValueKey('recovery-check-status'),
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            if (checking)
              const SizedBox.square(
                dimension: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            else
              Icon(
                Icons.error_outline,
                size: 18,
                color: Theme.of(context).colorScheme.error,
              ),
            const SizedBox(width: 12),
            Expanded(
              child: Semantics(
                liveRegion: true,
                child: Text(
                  checking
                      ? context.l10n.recoveryChecking
                      : '${context.l10n.recoveryCheckFailed}'
                            '${sourceError == null ? '' : '\n${sourceError!.message}'}'
                            '${readError == null ? '' : '\n${readError!.message} · ${readError!.correlationId}'}',
                ),
              ),
            ),
            if (!checking && retryable)
              TextButton(
                key: const ValueKey('recovery-check-retry'),
                onPressed: retryPending ? null : onRetry,
                child: Text(context.l10n.runtimeFatalRetry),
              ),
          ],
        ),
      ),
    );
  }
}
