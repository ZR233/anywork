import 'dart:convert';

import 'collection_extensions.dart';
import 'failure_models.dart';

enum RecoveryIssueScope { application, project, thread }

enum RecoveryIssueCategory { processLease, toolCatalog, repository, storage }

enum RecoveryIssueImpact { advisory, executionBlocked, accessBlocked }

enum RecoveryIssueAction { retry, cleanupWorktree }

/// Worktree lease 归属来源；显式清理必须与 durable lease 的归属一致。
enum WorktreeOwnerKind {
  session,
  child;

  /// Canonical wire 值：`session` | `child`。
  String get id => name;

  bool get isSession => this == WorktreeOwnerKind.session;
}

enum WorktreeInspection { available, missing, identityMismatch, unavailable }

class WorktreeRecoveryPreview {
  const WorktreeRecoveryPreview({
    required this.inspection,
    required this.ownerKind,
    required this.ownerThreadId,
    required this.leaseRevision,
    required this.state,
    required this.repositoryRoot,
    required this.path,
    required this.branch,
    required this.baseCommit,
    required this.headCommit,
    required this.dirty,
    required this.changedFiles,
  });

  final WorktreeInspection inspection;
  final WorktreeOwnerKind ownerKind;
  final String ownerThreadId;
  final int leaseRevision;
  final String state;
  final String repositoryRoot;
  final String path;
  final String? branch;
  final String baseCommit;
  final String? headCommit;
  final bool? dirty;
  final List<String>? changedFiles;
}

class StudioRecoveryIssue {
  const StudioRecoveryIssue({
    required this.id,
    required this.scope,
    required this.category,
    required this.impact,
    required this.availableActions,
    required this.detail,
    this.workspaceId,
    this.threadId,
    this.worktree,
  });

  final String id;
  final RecoveryIssueScope scope;
  final RecoveryIssueCategory category;
  final RecoveryIssueImpact impact;
  final List<RecoveryIssueAction> availableActions;
  final String? workspaceId;
  final String? threadId;
  final String detail;
  final WorktreeRecoveryPreview? worktree;

  bool get canCleanup =>
      availableActions.contains(RecoveryIssueAction.cleanupWorktree);

  bool get canRetry => availableActions.contains(RecoveryIssueAction.retry);

  bool get blocksAccess => impact == RecoveryIssueImpact.accessBlocked;

  bool get blocksExecution => impact != RecoveryIssueImpact.advisory;

  /// Match the exact canonical target, not its directory ancestry. Project
  /// issues constrain Project operations and new roots without a thread ID;
  /// existing Threads consume Application and their own Thread issues only.
  /// A Thread issue's project identity remains optional metadata, and when
  /// both project IDs are present they must agree.
  bool matchesTarget({required String? workspaceId, String? threadId}) =>
      switch (scope) {
        RecoveryIssueScope.application => true,
        RecoveryIssueScope.project =>
          threadId == null &&
              workspaceId != null &&
              this.workspaceId == workspaceId,
        RecoveryIssueScope.thread =>
          threadId != null &&
              this.threadId == threadId &&
              (workspaceId == null ||
                  this.workspaceId == null ||
                  this.workspaceId == workspaceId),
      };

  /// Actionable diagnostic text shared by UI entry points and rejected calls.
  String get diagnosticSummary {
    final owner = switch (scope) {
      RecoveryIssueScope.application => 'application',
      RecoveryIssueScope.project => 'project ${workspaceId ?? '(unknown)'}',
      RecoveryIssueScope.thread =>
        'project ${workspaceId ?? '(unknown)'}, thread ${threadId ?? '(unknown)'}',
    };
    final actions = availableActions.isEmpty
        ? 'none currently available'
        : availableActions.map((action) => action.name).join(', ');
    return 'Recovery issue $id ($owner; ${impact.name}): $detail. '
        'Available recovery actions: $actions.';
  }

  /// Keep recovery rejection in the existing structured Client failure type.
  StudioFailure blockedFailure() => StudioFailure(
    code: StudioFailureCode.permissionDenied,
    message: diagnosticSummary,
    retryable: false,
    correlationId: 'client-recovery-$id',
    detailsJson: jsonEncode({
      'kind': 'recovery',
      'issueId': id,
      'scope': scope.name,
      'owner': {
        'scope': scope.name,
        'id': switch (scope) {
          RecoveryIssueScope.application => null,
          RecoveryIssueScope.project => workspaceId,
          RecoveryIssueScope.thread => threadId,
        },
      },
      'category': category.name,
      'impact': impact.name,
      'workspaceId': workspaceId,
      'threadId': threadId,
      'detail': detail,
      'availableActions': availableActions
          .map((action) => action.name)
          .toList(),
    }),
  );
}

/// Rehydrates the typed recovery detail from the Client's structured failure
/// payload for localized presentation. Malformed or non-recovery failures have
/// no recovery projection and remain available through the original failure.
StudioRecoveryIssue? recoveryIssueFromFailure(StudioFailure? failure) {
  if (failure?.code != StudioFailureCode.permissionDenied) return null;
  final encoded = failure!.detailsJson;
  if (encoded == null) return null;
  try {
    final decoded = jsonDecode(encoded);
    if (decoded is! Map<String, dynamic> || decoded['kind'] != 'recovery') {
      return null;
    }
    final id = decoded['issueId'];
    final scopeName = decoded['scope'];
    final categoryName = decoded['category'];
    final impactName = decoded['impact'];
    final detail = decoded['detail'];
    final actionNames = decoded['availableActions'];
    final workspaceIdValue = decoded['workspaceId'];
    final threadIdValue = decoded['threadId'];
    final owner = decoded['owner'];
    if (id is! String ||
        id.trim().isEmpty ||
        scopeName is! String ||
        categoryName is! String ||
        impactName is! String ||
        detail is! String ||
        detail.trim().isEmpty ||
        actionNames is! List<dynamic> ||
        (workspaceIdValue != null && workspaceIdValue is! String) ||
        (threadIdValue != null && threadIdValue is! String) ||
        owner is! Map<String, dynamic>) {
      return null;
    }
    final scope = RecoveryIssueScope.values.byName(scopeName);
    final category = RecoveryIssueCategory.values.byName(categoryName);
    final impact = RecoveryIssueImpact.values.byName(impactName);
    final workspaceId = workspaceIdValue as String?;
    final threadId = threadIdValue as String?;
    if ((workspaceId != null && workspaceId.trim().isEmpty) ||
        (threadId != null && threadId.trim().isEmpty)) {
      return null;
    }
    switch (scope) {
      case RecoveryIssueScope.application:
        if (workspaceId != null || threadId != null) return null;
        break;
      case RecoveryIssueScope.project:
        if (workspaceId == null || threadId != null) return null;
        break;
      case RecoveryIssueScope.thread:
        if (threadId == null) return null;
        break;
    }
    final ownerId = switch (scope) {
      RecoveryIssueScope.application => null,
      RecoveryIssueScope.project => workspaceId,
      RecoveryIssueScope.thread => threadId,
    };
    if (owner['scope'] != scopeName || owner['id'] != ownerId) return null;
    final actions = <RecoveryIssueAction>[];
    for (final action in actionNames) {
      if (action is! String || action.trim().isEmpty) return null;
      actions.add(RecoveryIssueAction.values.byName(action));
    }
    if (actions.toSet().length != actions.length) return null;
    return StudioRecoveryIssue(
      id: id,
      scope: scope,
      category: category,
      impact: impact,
      availableActions: actions,
      workspaceId: workspaceId,
      threadId: threadId,
      detail: detail,
    );
  } on Object {
    return null;
  }
}

List<StudioRecoveryIssue> recoveryIssuesForTarget(
  Iterable<StudioRecoveryIssue> issues, {
  required String? workspaceId,
  String? threadId,
}) {
  final matching = issues
      .where(
        (issue) =>
            issue.matchesTarget(workspaceId: workspaceId, threadId: threadId),
      )
      .toList();
  matching.sort((left, right) {
    final impact = right.impact.index.compareTo(left.impact.index);
    if (impact != 0) return impact;
    final scope = right.scope.index.compareTo(left.scope.index);
    if (scope != 0) return scope;
    return left.id.compareTo(right.id);
  });
  return matching;
}

StudioRecoveryIssue? recoveryIssueBlockingAccess(
  Iterable<StudioRecoveryIssue> issues, {
  required String? workspaceId,
  String? threadId,
}) => recoveryIssuesForTarget(
  issues,
  workspaceId: workspaceId,
  threadId: threadId,
).where((issue) => issue.blocksAccess).firstOrNull;

StudioRecoveryIssue? recoveryIssueBlockingExecution(
  Iterable<StudioRecoveryIssue> issues, {
  required String? workspaceId,
  String? threadId,
}) => recoveryIssuesForTarget(
  issues,
  workspaceId: workspaceId,
  threadId: threadId,
).where((issue) => issue.blocksExecution).firstOrNull;
