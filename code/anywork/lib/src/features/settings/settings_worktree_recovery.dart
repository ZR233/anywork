import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/studio_tokens.dart';
import '../../presentation/providers/client_provider.dart';
import '../../presentation/providers/recovery_store.dart';
import '../../shared/recovery_check_status.dart';
import '../../domain/models/studio_models.dart';
import '../../l10n/studio_l10n.dart';
import 'settings_common.dart';
import 'settings_scope.dart';

class WorktreeRecoveryPanel extends ConsumerWidget {
  const WorktreeRecoveryPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final issues =
        ref
            .watch(recoveryStoreProvider)
            .value
            ?.values
            .where(
              (issue) => issue.category == RecoveryIssueCategory.repository,
            )
            .toList(growable: false) ??
        const <StudioRecoveryIssue>[];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SettingsTopicStatus(topic: RecoveryTopic()),
        const RecoveryCheckStatus(showChecking: false),
        if (issues.isNotEmpty)
          ExpansionTile(
            key: const ValueKey('settings-worktree-recovery'),
            leading: const Icon(Icons.folder_outlined),
            title: Text(
              context.l10n.settingsWorktreeRecoveryTitle(issues.length),
            ),
            children: [
              for (final issue in issues)
                if (issue.worktree != null)
                  WorktreeRecoverySection(key: ValueKey(issue.id), issue: issue)
                else
                  Padding(
                    key: ValueKey(issue.id),
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        SelectableText(context.recoveryIssueLabel(issue)),
                        if (issue.canRetry)
                          TextButton(
                            onPressed: () async {
                              try {
                                await ref
                                    .read(anyworkClientProvider)
                                    .directoryCommands
                                    .retryRecovery();
                              } catch (error) {
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(content: Text(error.toString())),
                                  );
                                }
                              }
                            },
                            child: Text(context.l10n.settingsWorktreeRetry),
                          ),
                      ],
                    ),
                  ),
            ],
          ),
      ],
    );
  }
}

class WorktreeRecoverySection extends ConsumerStatefulWidget {
  const WorktreeRecoverySection({super.key, required this.issue});

  final StudioRecoveryIssue issue;

  @override
  ConsumerState<WorktreeRecoverySection> createState() =>
      _WorktreeRecoverySectionState();
}

class _WorktreeRecoverySectionState
    extends ConsumerState<WorktreeRecoverySection> {
  bool _cleaning = false;
  String? _error;

  @override
  Widget build(BuildContext context) {
    final worktree = widget.issue.worktree!;
    final l10n = context.l10n;
    final head = worktree.headCommit;
    final owner = worktree.ownerKind.isSession
        ? l10n.settingsWorktreeOwnerSession
        : l10n.settingsWorktreeOwnerChild;
    final identity = '${worktree.ownerKind.id}-${worktree.ownerThreadId}';
    final canCleanup =
        widget.issue.availableActions.contains(
          RecoveryIssueAction.cleanupWorktree,
        ) &&
        worktree.inspection == WorktreeInspection.available;
    final dirtyLabel = switch (worktree.dirty) {
      true => l10n.settingsWorktreeDirty,
      false => l10n.settingsWorktreeClean,
      null => l10n.settingsWorktreeDirtyUnknown,
    };
    return SettingsResourceRow(
      key: ValueKey('worktree-recovery-$identity'),
      title:
          worktree.branch ??
          switch (worktree.inspection) {
            WorktreeInspection.available => l10n.settingsWorktreeDetached,
            WorktreeInspection.missing ||
            WorktreeInspection.identityMismatch ||
            WorktreeInspection.unavailable =>
              l10n.settingsWorktreeBranchUnknown,
          },
      subtitle: owner,
      icon: Icons.account_tree_outlined,
      status: Text(
        [
          context.worktreeStateLabel(worktree.state),
          _inspectionLabel(context, worktree.inspection),
          dirtyLabel,
        ].join(' · '),
      ),
      actions: [
        if (canCleanup)
          TextButton.icon(
            key: ValueKey('worktree-cleanup-$identity'),
            onPressed: _cleaning ? null : () => _cleanup(worktree),
            icon: _cleaning
                ? const SizedBox.square(
                    dimension: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.delete_sweep_outlined, size: 18),
            label: Text(context.l10n.settingsWorktreeCleanup),
          ),
        if (widget.issue.canRetry)
          TextButton.icon(
            key: ValueKey('worktree-retry-$identity'),
            onPressed: _cleaning ? null : _retryRecovery,
            icon: const Icon(Icons.refresh, size: 18),
            label: Text(context.l10n.settingsWorktreeRetry),
          ),
      ],
      children: [
        SelectableText(context.recoveryIssueLabel(widget.issue)),
        const SizedBox(height: 8),
        SelectableText(
          [
            l10n.settingsWorktreeBase(worktree.baseCommit),
            head == null
                ? l10n.settingsWorktreeHeadUnavailable
                : l10n.settingsWorktreeHead(head),
            worktree.path,
          ].join('\n'),
          style: DefaultTextStyle.of(context).style
              .copyWith(fontFamily: studioCodeFontFamily),
        ),
        if (worktree.changedFiles == null || worktree.ignoredFiles == null) ...[
          const SizedBox(height: 8),
          Text(l10n.settingsWorktreeChangedFilesUnknown),
        ],
        if (worktree.changedFiles?.isNotEmpty == true) ...[
          const SizedBox(height: 8),
          Text(
            context.l10n.settingsWorktreeChangedFiles(
              worktree.changedFiles!.join(', '),
            ),
            style: const TextStyle(fontFamily: studioCodeFontFamily),
          ),
        ],
        if (worktree.ignoredFiles?.isNotEmpty == true) ...[
          const SizedBox(height: 8),
          Text(
            l10n.settingsWorktreeIgnoredFiles(
              worktree.ignoredFiles!.join(', '),
            ),
            style: const TextStyle(fontFamily: studioCodeFontFamily),
          ),
        ],
        if (_error != null) SettingsInlineError(message: _error!),
        const Divider(height: 24),
      ],
    );
  }

  String _inspectionLabel(BuildContext context, WorktreeInspection state) =>
      switch (state) {
        WorktreeInspection.available =>
          context.l10n.settingsWorktreeInspectionAvailable,
        WorktreeInspection.missing =>
          context.l10n.settingsWorktreeInspectionMissing,
        WorktreeInspection.identityMismatch =>
          context.l10n.settingsWorktreeInspectionIdentityMismatch,
        WorktreeInspection.unavailable =>
          context.l10n.settingsWorktreeInspectionUnavailable,
      };

  Future<void> _retryRecovery() async {
    setState(() {
      _cleaning = true;
      _error = null;
    });
    try {
      await ref.read(anyworkClientProvider).directoryCommands.retryRecovery();
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _cleaning = false);
    }
  }

  Future<void> _cleanup(WorktreeRecoveryPreview worktree) async {
    setState(() {
      _cleaning = true;
      _error = null;
    });
    try {
      await ref
          .read(anyworkClientProvider)
          .directoryCommands
          .cleanupPreservedWorktree(worktree);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _cleaning = false);
    }
  }
}
