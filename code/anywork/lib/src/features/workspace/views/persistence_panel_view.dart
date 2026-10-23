import 'package:anywork_client/conversation.dart' show FacetSyncPhase;
import 'package:anywork_client/persistence.dart';
import 'package:anywork_client/resources.dart';
import 'package:flutter/material.dart';

import '../../../l10n/studio_l10n.dart';
import '../state/collection_presentation.dart';
import '../state/workspace_diagnostics_state.dart';
import '../widgets/workspace_failure_notice.dart';

class PersistencePanelView extends StatelessWidget {
  const PersistencePanelView({
    required this.state, required this.onRetryPersistence,
    required this.displayedOldestAgeMillis,
    required this.onRetryThread, required this.onResumeThread,
    required this.onToggleDetails, required this.onReadQueue, super.key,
    required this.onRetryExecution,
  });
  final WorkspaceDiagnosticsState state;
  final int? displayedOldestAgeMillis;
  final VoidCallback onRetryPersistence;
  final ValueChanged<StoragePanelTarget> onRetryThread;
  final ValueChanged<StoragePanelTarget> onResumeThread;
  final VoidCallback onToggleDetails;
  final VoidCallback onReadQueue;
  final ValueChanged<StoragePanelTarget> onRetryExecution;

  @override
  Widget build(BuildContext context) {
    final persistence = state.persistence.projection.header?.state;
    final queue = state.queue.projection.header;
    final target = state.storageTarget;
    final storage = target?.execution.value?.storage;
    final queueRows = presentRows(state.queue.threads);
    final attention = persistence is DegradedPersistenceBrief ||
        persistence is RecoveringPersistenceBrief || persistence is BlockedPersistenceBrief;
    final paused = storage?.resumeRequired == true ||
        storage?.execution == ThreadStorageExecution.pausing ||
        storage?.execution == ThreadStorageExecution.paused;
    final pressure = storage?.pressurePaused == true || queue?.pressurePaused == true;
    final faults = queueRows.any((row) => row.fault != null);
    final errors = [
      for (final entry in state.readErrors.entries)
        if (entry.key.startsWith('persistence') || entry.key.startsWith('queue')) entry.value,
      if (state.persistence.projection.sync.error case final error?) error,
      if (state.queue.projection.sync.error case final error?) error,
    ];
    // Normal queued writes and Flushing are never inserted as a visible banner.
    final actionFailure = state.actions.entries.any((entry) =>
      (entry.key.startsWith('persistence') || entry.key.contains('history:')) &&
      (entry.value.admissionError != null || entry.value.observationError != null ||
       entry.value.operation?.error != null || entry.value.operation?.evidenceError != null));
    if (!attention && !paused && !pressure && !faults && errors.isEmpty && !actionFailure) {
      return const SizedBox.shrink();
    }
    final l10n = context.l10n;
    final colors = Theme.of(context).colorScheme;
    final readyToResume = storage?.resumeRequired == true && storage?.canResume == true;
    final executionReady = target?.execution.sync.phase == FacetSyncPhase.ready;
    final dangerous = !readyToResume && (attention || faults || paused || errors.isNotEmpty);
    final global = presentReadValue(state.persistence.value)?.state;
    final sourceError = switch (global) {
      DegradedPersistenceStatus(:final error) || BlockedPersistenceStatus(:final error) => error,
      _ => null,
    };
    final summary = readyToResume ? l10n.persistenceHistoryResumeHint
        : paused ? l10n.persistenceExecutionPaused
        : pressure ? l10n.persistenceNewWorkPaused
        : switch (persistence) {
          DegradedPersistenceBrief(:final pendingCommits) => l10n.persistenceDegraded(pendingCommits),
          RecoveringPersistenceBrief(:final pendingCommits) => l10n.persistenceRecovering(pendingCommits),
          BlockedPersistenceBrief(:final pendingCommits) => l10n.persistenceBlocked(pendingCommits),
          _ => faults ? l10n.persistenceHistoryWriteFailed : l10n.persistenceQueueUnavailable,
        };
    final retryKey = target == null || storage == null ? null
        : 'retry-history:${target.threadId}:${storage.faultGeneration}';
    final resumeKey = target == null || storage == null ? null
        : 'resume-history:${target.threadId}:${storage.faultGeneration}';
    return Material(
      key: const ValueKey('persistence-status-panel'),
      color: dangerous ? colors.errorContainer : colors.surfaceContainerLow,
      child: Padding(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Icon(dangerous ? Icons.error_outline : Icons.info_outline, size: 18),
            const SizedBox(width: 8),
            Expanded(child: Text(summary)),
            IconButton(key: const ValueKey('persistence-queue-details'),
              tooltip: state.queueExpanded ? l10n.persistenceQueueHideDetails : l10n.persistenceQueueShowDetails,
              onPressed: onToggleDetails,
              icon: Icon(state.queueExpanded ? Icons.expand_less : Icons.expand_more)),
          ]),
          Wrap(spacing: 8, children: [
            if (target != null && storage != null && (paused || storage.fault != null)) TextButton(
              key: const ValueKey('persistence-history-retry'),
              onPressed: !executionReady || state.actions[retryKey]?.waiting == true
                  ? null : () => onRetryThread(target),
              child: Text(l10n.persistenceHistoryRetrySave)),
            if (target != null && readyToResume) FilledButton.tonal(
              key: const ValueKey('persistence-history-resume'),
              onPressed: !executionReady || state.actions[resumeKey]?.waiting == true
                  ? null : () => onResumeThread(target),
              child: Text(l10n.persistenceHistoryResume)),
            if (attention) TextButton(key: const ValueKey('persistence-retry'),
              onPressed: state.actions['persistence']?.waiting == true ? null : onRetryPersistence,
              child: Text(l10n.persistenceRetry)),
          ]),
          for (final error in errors) WorkspaceFailureNotice(failure: error, onRetry: onReadQueue),
          if (target != null)
            if (target.execution.sync.error ?? state.readErrors['active-execution'] case final error?)
            WorkspaceFailureNotice(failure: error, onRetry: () => onRetryExecution(target)),
          for (final entry in state.actions.entries)
            if (entry.key.startsWith('persistence') || entry.key.contains('history:')) ...[
              if (entry.value.admissionError ?? entry.value.operation?.error case final error?)
                WorkspaceFailureNotice(failure: error),
              if (entry.value.operation?.evidenceError case final error?)
                WorkspaceFailureNotice(failure: error),
              if (entry.value.observationError case final error?)
                WorkspaceFailureNotice(failure: error),
            ],
          if (state.queueExpanded) ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 132),
            child: SingleChildScrollView(child: SelectionArea(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l10n.persistenceQueueTitle, style: Theme.of(context).textTheme.labelLarge),
                if (sourceError != null) Text('${sourceError.message}\n${sourceError.code}'),
                if (queue == null) Text(l10n.persistenceQueueUnavailable)
                else ...[
                  Text(l10n.persistenceQueuePending(queue.pendingOperations, queue.pendingBytes)),
                  Text(l10n.persistenceQueueInFlight(queue.inFlightBytes)),
                  if (displayedOldestAgeMillis case final age?) Text(l10n.persistenceQueueOldestAge(age)),
                  if (queue.statisticsGap) Text(l10n.persistenceStatisticsGap),
                  if (queue.pressurePaused) Text(l10n.persistenceQueuePressurePaused),
                ],
                if (presentReadValue(state.queue.lastError) case final message?)
                  Text(l10n.persistenceQueueError(message)),
                for (final row in queueRows.take(3)) ...[
                  Text('${row.threadId} · ${row.fault?.name ?? '—'} · ${row.faultGeneration}'),
                  Text('history: ${row.historyDurableSequence ?? '—'} / ${row.historyAdmittedSequence ?? '—'}; '
                    'state: ${row.stateDurableRevision ?? '—'} / ${row.stateSavingRevision ?? '—'} / ${row.stateDirtyRevision ?? '—'}; '
                    'calls: ${row.callsDurableSequence ?? '—'} / ${row.callsAdmittedSequence ?? '—'}'),
                  if (row.lastError case final error?) Text(error),
                ],
                TextButton(onPressed: onReadQueue, child: Text(l10n.persistenceQueueRefresh)),
              ],
            ))),
          ),
        ]),
      ),
    );
  }
}
