import 'package:freezed_annotation/freezed_annotation.dart';

part 'recovery_values.freezed.dart';

enum RecoveryScope { application, project, thread }
enum RecoveryCategory { processLease, toolCatalog, repository, storage }
enum RecoveryAction { none, retry, cleanupThread, removeProject, cleanupWorktree }
enum WorktreeOwner { session, child }

@Freezed(toStringOverride: false)
abstract class WorktreeRecoveryPreview with _$WorktreeRecoveryPreview {
  const factory WorktreeRecoveryPreview({
    required WorktreeOwner ownerKind,
    required String ownerThreadId,
    required int leaseRevision,
    required String state,
    required String repositoryRoot,
    required String path,
    required String branch,
    required String baseCommit,
    required String? headCommit,
    required bool dirty,
    required List<String> changedFiles,
  }) = _WorktreeRecoveryPreview;
}

@Freezed(toStringOverride: false)
abstract class RecoveryIssue with _$RecoveryIssue {
  const RecoveryIssue._();

  const factory RecoveryIssue({
    required String id,
    required RecoveryScope scope,
    required RecoveryCategory category,
    required RecoveryAction action,
    required String? projectId,
    required String? threadId,
    required String message,
    required WorktreeRecoveryPreview? worktree,
  }) = _RecoveryIssue;

  bool get blocksAccess => category != RecoveryCategory.toolCatalog;
  bool get canRetry => action == RecoveryAction.retry;
  bool get canCleanup =>
      action == RecoveryAction.cleanupThread ||
      action == RecoveryAction.removeProject ||
      action == RecoveryAction.cleanupWorktree;
}
