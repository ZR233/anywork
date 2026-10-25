import 'dart:async';

import 'package:anywork_client/resources.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../view_models/workspace_diagnostics_view_model.dart';
import '../views/persistence_panel_view.dart';
import '../widgets/workspace_failure_notice.dart';

class PersistencePanelConnector extends ConsumerWidget {
  const PersistencePanelConnector({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final watched = ref.watch(workspaceDiagnosticsViewModelProvider);
    if (watched.asError case final failure?) {
      if (failure.error is! StudioFailure) {
        Error.throwWithStackTrace(failure.error, failure.stackTrace);
      }
      return WorkspaceFailureNotice(
        failure: failure.error as StudioFailure,
        onRetry: () => ref.invalidate(workspaceDiagnosticsViewModelProvider),
      );
    }
    final current = watched.asData?.value;
    if (current == null) return const SizedBox.shrink();
    final vm = ref.read(workspaceDiagnosticsViewModelProvider.notifier);
    final queue = current.queue.projection.header;
    final baseAge = queue?.oldestPendingAgeMillis;
    final elapsed = queue == null
        ? 0
        : DateTime.now().millisecondsSinceEpoch - queue.updatedAt * 1000;
    return PersistencePanelView(
      state: current,
      // Presentation-only elapsed time from the canonical event, not a poll or
      // a new queue value. Missing age remains unknown rather than zero.
      displayedOldestAgeMillis: baseAge == null
          ? null
          : baseAge + (elapsed > 0 ? elapsed : 0),
      onRetryPersistence: () => unawaited(vm.retryPersistence()),
      onRetryThread: (target) => unawaited(vm.retryThreadHistory(target)),
      onResumeThread: (target) => unawaited(vm.resumeThreadHistory(target)),
      onToggleDetails: vm.toggleQueueDetails,
      onReadQueue: () => unawaited(vm.readQueue()),
      onRetryExecution: (target) =>
          unawaited(vm.retryStorageObservation(target)),
    );
  }
}
