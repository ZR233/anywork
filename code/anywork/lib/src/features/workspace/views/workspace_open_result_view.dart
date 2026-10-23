import 'package:anywork_client/operations.dart';
import 'package:anywork_client/workspace.dart';
import 'package:flutter/material.dart';

import '../../../l10n/studio_l10n.dart';
import '../widgets/workspace_failure_notice.dart';

/// Independent steps stay visible even if later activation or navigation
/// failed. UnknownOutcome is not collapsed into cancellation or a retry CTA.
class WorkspaceOpenResultView extends StatelessWidget {
  const WorkspaceOpenResultView({required this.result, required this.onDismiss, super.key});
  final WorkspaceOpenResult result;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) => Material(
    key: const ValueKey('workspace-open-result'),
    color: Theme.of(context).colorScheme.surfaceContainerLow,
    child: Padding(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min, children: [
            for (final step in result.steps) switch (step) {
              OpenedWorkspaceOpenStep(:final result) => _command(context, context.l10n.sidebarOpenProject, result),
              RenamedWorkspaceOpenStep(:final result) => _command(context, context.l10n.commonSave, result),
              ActivatedWorkspaceOpenStep(:final result) => _command(context, context.l10n.sidebarContinue, result),
              NotStartedWorkspaceOpenStep(:final stage, :final error) => Column(
                crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(stage.name), WorkspaceFailureNotice(failure: error),
                ]),
            },
            switch (result.selection) {
              AppliedWorkspaceOpenSelection(:final value) => Text(
                '${context.l10n.sidebarNavigation}: ${value.disposition.name}'),
              NotAttemptedWorkspaceOpenSelection(:final reason) => WorkspaceFailureNotice(failure: reason),
              FailedWorkspaceOpenSelection(:final error) => WorkspaceFailureNotice(failure: error),
            },
          ])),
        IconButton(tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
          onPressed: onDismiss, icon: const Icon(Icons.close, size: 18)),
      ])),
  );

  Widget _command<T>(BuildContext context, String label, CommandResult<T> result) {
    final (value, error, outcome) = switch (result) {
      CommittedCommandResult<T>(:final value) => (value, null, 'committed'),
      AcknowledgedCommandResult<T>(:final value) => (value, null, 'acknowledged'),
      RejectedCommandResult<T>(:final error) => (null, error, 'rejected'),
      UnknownOutcomeCommandResult<T>(:final error) => (null, error, 'unknownOutcome'),
      SyncFailedCommandResult<T>(:final value, :final error) => (value, error, 'syncFailed'),
      AcknowledgedSyncFailedCommandResult<T>(:final value, :final error) => (value, error, 'acknowledgedSyncFailed'),
    };
    return Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
      Text('$label · $outcome'),
      if (value is ProjectRecord) Text('${value.name}\n${value.path}'),
      if (error != null) WorkspaceFailureNotice(failure: error),
    ]);
  }
}
