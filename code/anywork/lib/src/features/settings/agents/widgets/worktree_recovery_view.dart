import 'package:anywork_client/recovery.dart';
import 'package:flutter/material.dart';

import '../../../../app/theme/studio_typography.dart';
import '../../../../l10n/studio_l10n.dart';
import '../../state/settings_action.dart';

class WorktreeRecoveryView extends StatelessWidget {
  const WorktreeRecoveryView({
    required this.worktree,
    required this.action,
    required this.errors,
    required this.onCleanup,
    super.key,
  });
  final WorktreeRecoveryPreview worktree;
  final SettingsAction? action;
  final List<String> errors;
  final VoidCallback onCleanup;
  @override
  Widget build(BuildContext context) {
    final identity = '${worktree.ownerKind.name}-${worktree.ownerThreadId}';
    return Card.outlined(
      key: ValueKey('worktree-recovery-$identity'),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(worktree.branch),
              subtitle: Text(
                worktree.ownerKind == WorktreeOwner.session
                    ? context.l10n.settingsWorktreeOwnerSession
                    : context.l10n.settingsWorktreeOwnerChild,
              ),
              trailing: TextButton.icon(
                key: ValueKey('worktree-cleanup-$identity'),
                onPressed: action?.preventsResubmission == true
                    ? null
                    : onCleanup,
                icon: const Icon(Icons.delete_sweep_outlined),
                label: Text(context.l10n.settingsWorktreeCleanup),
              ),
            ),
            Text(
              [
                context.worktreeStateLabel(worktree.state),
                if (worktree.dirty) context.l10n.settingsWorktreeDirty,
              ].join(' · '),
            ),
            SelectableText(
              [
                context.l10n.settingsWorktreeBase(worktree.baseCommit),
                worktree.headCommit == null
                    ? context.l10n.settingsWorktreeHeadUnavailable
                    : context.l10n.settingsWorktreeHead(worktree.headCommit!),
                worktree.path,
              ].join('\n'),
              style: const TextStyle(fontFamily: studioCodeFontFamily),
            ),
            if (worktree.changedFiles.isNotEmpty)
              Text(
                context.l10n.settingsWorktreeChangedFiles(
                  worktree.changedFiles.join(', '),
                ),
                style: const TextStyle(fontFamily: studioCodeFontFamily),
              ),
            for (final error in errors)
              SelectableText(
                error,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
          ],
        ),
      ),
    );
  }
}
