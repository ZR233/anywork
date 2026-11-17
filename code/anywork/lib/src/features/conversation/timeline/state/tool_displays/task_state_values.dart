import '../../../../../l10n/app_localizations.dart';

Object? toolTaskStateValues(AppLocalizations l10n, Object? value) =>
    switch (value) {
      final List entries => [
        for (final entry in entries) toolTaskStateValues(l10n, entry),
      ],
      final Map<String, dynamic> object => {
        for (final MapEntry(:key, :value) in object.entries)
          key: switch ((key, value)) {
            ('status' || 'state', final String state) => switch (state) {
              'queued' => l10n.timelineToolStateQueued,
              'running' => l10n.timelineToolStateRunning,
              'succeeded' => l10n.timelineToolStateSucceeded,
              'completed' => l10n.timelineToolStateCompleted,
              'failed' => l10n.timelineToolStateFailed,
              'cancelled' => l10n.timelineToolStateCancelled,
              'interrupted' => l10n.timelineToolStateInterrupted,
              'idle' => l10n.timelineToolStateIdle,
              'waitingTool' => l10n.timelineToolStateWaitingTool,
              'waitingInteraction' => l10n.timelineToolStateWaitingInteraction,
              'cancelling' => l10n.timelineToolStateCancelling,
              'closing' => l10n.timelineToolStateClosing,
              'closed' => l10n.timelineToolStateClosed,
              'faulted' => l10n.timelineToolStateFaulted,
              'budgetLimited' => l10n.timelineToolStateBudgetLimited,
              'ready' => l10n.timelineToolStateReady,
              _ => state,
            },
            _ =>
              const {'tasks', 'files', 'status', 'state'}.contains(key)
                  ? toolTaskStateValues(l10n, value)
                  : value,
          },
      },
      _ => value,
    };
