import 'package:anywork_client/recovery.dart';
import 'package:flutter/material.dart';

import '../../../../app/theme/studio_typography.dart';
import '../../../../l10n/studio_l10n.dart';
import '../../state/settings_action.dart';
import '../../widgets/settings_resource_row.dart';

class WorktreeRecoveryView extends StatelessWidget {
  const WorktreeRecoveryView({
    required this.worktree,
    required this.availableActions,
    required this.message,
    required this.enabled,
    required this.action,
    required this.retryAction,
    required this.errors,
    required this.onCleanup,
    required this.onRetry,
    super.key,
  });

  final WorktreeRecoveryPreview worktree;
  final List<RecoveryAction> availableActions;
  final String message;
  final bool enabled;
  final SettingsAction? action;
  final SettingsAction? retryAction;
  final List<String> errors;
  final VoidCallback onCleanup;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final identity = '${worktree.ownerKind.name}-${worktree.ownerThreadId}';
    final pending =
        action?.preventsResubmission == true ||
        retryAction?.preventsResubmission == true;
    final changedFiles = worktree.changedFiles;
    return SettingsResourceRow(
      key: ValueKey('worktree-recovery-$identity'),
      title: worktree.branch,
      subtitle: worktree.ownerKind == WorktreeOwner.session
          ? context.l10n.settingsWorktreeOwnerSession
          : context.l10n.settingsWorktreeOwnerChild,
      icon: Icons.account_tree_outlined,
      status: Text(
        [
          context.worktreeStateLabel(worktree.state),
          switch (worktree.inspection) {
            WorktreeInspection.available =>
              context.l10n.settingsWorktreeInspectionAvailable,
            WorktreeInspection.missing =>
              context.l10n.settingsWorktreeInspectionMissing,
            WorktreeInspection.identityMismatch =>
              context.l10n.settingsWorktreeInspectionIdentityMismatch,
            WorktreeInspection.unavailable =>
              context.l10n.settingsWorktreeInspectionUnavailable,
          },
          switch (worktree.dirty) {
            true => context.l10n.settingsWorktreeDirty,
            false => context.l10n.settingsWorktreeClean,
            null => context.l10n.settingsWorktreeDirtyUnknown,
          },
        ].join(' · '),
      ),
      actions: [
        if (availableActions.contains(RecoveryAction.cleanupWorktree))
          TextButton.icon(
            key: ValueKey('worktree-cleanup-$identity'),
            onPressed: !enabled || pending ? null : onCleanup,
            icon: action?.pending == true
                ? const SizedBox.square(
                    dimension: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.delete_sweep_outlined, size: 18),
            label: Text(context.l10n.settingsWorktreeCleanup),
          ),
        if (availableActions.contains(RecoveryAction.retry))
          TextButton.icon(
            key: ValueKey('worktree-retry-$identity'),
            onPressed: !enabled || pending ? null : onRetry,
            icon: const Icon(Icons.refresh, size: 18),
            label: Text(context.l10n.settingsWorktreeRetry),
          ),
      ],
      children: [
        SelectableText(
          [
            context.l10n.settingsWorktreeBase(worktree.baseCommit),
            worktree.headCommit == null
                ? context.l10n.settingsWorktreeHeadUnavailable
                : context.l10n.settingsWorktreeHead(worktree.headCommit!),
            worktree.path,
          ].join('\n'),
          style: DefaultTextStyle.of(context).style.copyWith(
            fontFamily: studioCodeFontFamily,
          ),
        ),
        const SizedBox(height: 8),
        SelectableText(message),
        if (changedFiles == null) ...[
          const SizedBox(height: 8),
          Text(context.l10n.settingsWorktreeChangedFilesUnknown),
        ] else if (changedFiles.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(
            context.l10n.settingsWorktreeChangedFiles(changedFiles.join(', ')),
            style: const TextStyle(fontFamily: studioCodeFontFamily),
          ),
        ],
        for (final error in errors)
          SelectableText(
            error,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        const Divider(height: 24),
      ],
    );
  }
}
