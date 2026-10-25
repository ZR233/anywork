import 'package:anywork_client/recovery_ports.dart';

import '../../../../rust/api/studio/products/read/recovery.dart' as native;
import '../../../../rust/api/studio/types/runtime.dart' as runtime;
import '../../shared/exact_numbers.dart';
import '../../shared/read_converters.dart';
import '../identity_converters.dart';

runtime.BridgeWorktreeOwner worktreeOwnerToBridge(WorktreeOwner value) =>
    switch (value) {
      WorktreeOwner.session => runtime.BridgeWorktreeOwner.session,
      WorktreeOwner.child => runtime.BridgeWorktreeOwner.child,
    };

WorktreeOwner worktreeOwnerFromBridge(runtime.BridgeWorktreeOwner value) =>
    switch (value) {
      runtime.BridgeWorktreeOwner.session => WorktreeOwner.session,
      runtime.BridgeWorktreeOwner.child => WorktreeOwner.child,
    };

RecoveryScope recoveryScopeFromBridge(native.BridgeRecoveryScope value) =>
    switch (value) {
      native.BridgeRecoveryScope.application => RecoveryScope.application,
      native.BridgeRecoveryScope.project => RecoveryScope.project,
      native.BridgeRecoveryScope.thread => RecoveryScope.thread,
    };

RecoveryCategory recoveryCategoryFromBridge(
  native.BridgeRecoveryCategory value,
) => switch (value) {
  native.BridgeRecoveryCategory.processLease => RecoveryCategory.processLease,
  native.BridgeRecoveryCategory.toolCatalog => RecoveryCategory.toolCatalog,
  native.BridgeRecoveryCategory.repository => RecoveryCategory.repository,
  native.BridgeRecoveryCategory.storage => RecoveryCategory.storage,
};

RecoveryAction recoveryActionFromBridge(native.BridgeRecoveryAction value) =>
    switch (value) {
      native.BridgeRecoveryAction.none => RecoveryAction.none,
      native.BridgeRecoveryAction.retry => RecoveryAction.retry,
      native.BridgeRecoveryAction.cleanupThread => RecoveryAction.cleanupThread,
      native.BridgeRecoveryAction.removeProject => RecoveryAction.removeProject,
      native.BridgeRecoveryAction.cleanupWorktree =>
        RecoveryAction.cleanupWorktree,
    };

RecoveryReadHeader recoveryReadHeaderFromBridge(
  native.BridgeRecoveryReadHeader value,
) => RecoveryReadHeader(issues: typedListFromBridge(value.issues));

WorktreeRecoveryPreviewRead worktreePreviewFromBridge(
  native.BridgeWorktreeRecoveryPreviewRead value,
) => WorktreeRecoveryPreviewRead(
  ownerKind: worktreeOwnerFromBridge(value.ownerKind),
  ownerThreadId: readTextFromBridge(value.ownerThreadId),
  leaseRevision: exactU64(value.leaseRevision, 'worktree lease revision'),
  state: readTextFromBridge(value.state),
  repositoryRoot: readTextFromBridge(value.repositoryRoot),
  path: readTextFromBridge(value.path),
  branch: readTextFromBridge(value.branch),
  baseCommit: readTextFromBridge(value.baseCommit),
  headCommit: nullableReadText(value.headCommit),
  dirty: value.dirty,
  changedFiles: typedListFromBridge(value.changedFiles),
);

RecoveryIssueRead recoveryIssueFromBridge(
  native.BridgeRecoveryIssueRead value,
) => RecoveryIssueRead(
  id: readTextFromBridge(value.id),
  scope: recoveryScopeFromBridge(value.scope),
  category: recoveryCategoryFromBridge(value.category),
  action: recoveryActionFromBridge(value.action),
  projectId: nullableReadText(value.projectId),
  threadId: nullableReadText(value.threadId),
  message: readTextFromBridge(value.message),
  worktree: value.worktree == null
      ? null
      : worktreePreviewFromBridge(value.worktree!),
);

RecoveryEntityRead recoveryEntityFromBridge(
  native.BridgeRecoveryEntityRead value,
) => RecoveryEntityRead(
  reference: entityRefFromBridge(value.reference),
  value: recoveryIssueFromBridge(value.value),
);

RecoveryEntryPage recoveryEntriesFromBridge(
  native.BridgeRecoveryEntryPage value,
) => RecoveryEntryPage(
  collection: collectionRefFromBridge(value.collection),
  offset: exactU64(value.offset, 'recovery entries offset'),
  items: value.items.map(entityRefFromBridge).toList(growable: false),
  nextOffset: nullableU64(value.nextOffset, 'recovery next entries offset'),
);

RecoveryIssueReadPage recoveryIssuesFromBridge(
  native.BridgeRecoveryIssueReadPage value,
) => RecoveryIssueReadPage(
  listId: exactU64(value.listId, 'recovery issues list'),
  offset: exactU64(value.offset, 'recovery issues offset'),
  total: exactU64(value.total, 'recovery issues total'),
  items: value.items.map(recoveryIssueFromBridge).toList(growable: false),
  nextOffset: nullableU64(value.nextOffset, 'recovery next issues offset'),
);
