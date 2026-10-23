import 'package:anywork_client/workspace.dart';
import 'package:flutter/material.dart';

import '../../l10n/studio_l10n.dart';
import 'exit_state.dart';

class ApplicationShutdownView extends StatelessWidget {
  const ApplicationShutdownView({required this.state, super.key});
  final ApplicationExitState state;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final report = state.report;
    final issue = state.diagnosticsIssue ?? report?.shutdown.issues.firstOrNull;
    final handoffError = switch (report?.updateHandoff) {
      FailedUpdateHandoff(:final error) => error,
      _ => null,
    };
    final finished = state.phase == ApplicationExitPhase.finished;
    final safe = report?.shutdown.outcome == ShutdownOutcome.clean &&
        report?.shutdown.issues.isEmpty == true &&
        report?.shutdown.persistence is DrainedPendingPersistence &&
        state.diagnosticsIssue == null;
    return ColoredBox(
      color: Theme.of(context).colorScheme.surface,
      child: Center(child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 480),
          child: Card(key: const ValueKey('studio-shutdown-overlay'),
            child: Padding(padding: const EdgeInsets.all(24), child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(state.readyUpdateVersion == null ? l10n.shutdownTitle
                    : l10n.shutdownUpdateTitle(state.readyUpdateVersion!),
                  style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 16),
                if (!finished) const LinearProgressIndicator(),
                const SizedBox(height: 12),
                Text(finished && safe ? l10n.shutdownPhaseStopped : switch (state.phase) {
                  ApplicationExitPhase.running || ApplicationExitPhase.sealing ||
                  ApplicationExitPhase.closingDartOwners => l10n.shutdownPhaseStoppingSubscriptions,
                  ApplicationExitPhase.finalizingRuntime => l10n.shutdownUpdateSaving,
                  ApplicationExitPhase.finishingDiagnostics || ApplicationExitPhase.finished => l10n.shutdownFinalizing,
                }),
                if (state.readyUpdateVersion != null) ...[
                  const SizedBox(height: 10),
                  Text(state.intent == ExitIntent.updateRestart
                      ? l10n.shutdownUpdateRestartHint : l10n.shutdownUpdateExitHint),
                ],
                if (issue != null) ...[
                  const SizedBox(height: 12),
                  SelectableText('${issue.message}\n${issue.code} · ${issue.correlationId}'),
                ],
                if (handoffError != null) ...[
                  const SizedBox(height: 12),
                  SelectableText('${handoffError.message}\n${handoffError.code}'),
                ],
                if (state.failed) ...[
                  const SizedBox(height: 12), Text(l10n.shutdownFinalizingHint),
                ],
              ],
            )),
          ),
        ),
      )),
    );
  }
}
