import 'package:anywork/src/infrastructure/frb/products/recovery/read_values.dart';
import 'package:anywork/src/rust/api/studio/observation.dart' as primitive;
import 'package:anywork/src/rust/api/studio/products/read/recovery.dart'
    as wire;
import 'package:anywork/src/rust/api/studio/types/runtime.dart' as runtime;
import 'package:anywork_client/recovery_ports.dart';
import 'package:anywork_client/resources.dart';
import 'package:flutter_test/flutter_test.dart';

wire.BridgeWorktreeRecoveryPreviewRead _worktree(
  runtime.BridgeWorktreeInspection inspection, {
  primitive.BridgeTypedListRef? changedFiles,
  bool? dirty,
  primitive.BridgeReadText? head,
}) => wire.BridgeWorktreeRecoveryPreviewRead(
  inspection: inspection,
  ownerKind: runtime.BridgeWorktreeOwner.session,
  ownerThreadId: const primitive.BridgeReadText.inline(
    text: 'thread-archive-1',
  ),
  leaseRevision: BigInt.from(9),
  state: const primitive.BridgeReadText.inline(text: 'preserved'),
  repositoryRoot: const primitive.BridgeReadText.inline(text: '/projects/demo'),
  path: const primitive.BridgeReadText.inline(
    text: '/projects/demo/.anywork/worktrees/thread-archive-1/session',
  ),
  branch: const primitive.BridgeReadText.inline(
    text: 'pure-session-thread-archive-1',
  ),
  baseCommit: const primitive.BridgeReadText.inline(text: 'base-commit'),
  headCommit: head,
  dirty: dirty,
  changedFiles: changedFiles,
);

void main() {
  test('recovery FRB read preserves four inspection states, nullable facts and original cleanup identity/path', () {
    for (final (native, expected) in const [
      (
        runtime.BridgeWorktreeInspection.available,
        WorktreeInspection.available,
      ),
      (runtime.BridgeWorktreeInspection.missing, WorktreeInspection.missing),
      (
        runtime.BridgeWorktreeInspection.identityMismatch,
        WorktreeInspection.identityMismatch,
      ),
      (
        runtime.BridgeWorktreeInspection.unavailable,
        WorktreeInspection.unavailable,
      ),
    ]) {
      final converted = worktreePreviewFromBridge(_worktree(native));
      expect(
        converted,
        WorktreeRecoveryPreviewRead(
          inspection: expected,
          ownerKind: WorktreeOwner.session,
          ownerThreadId: const ReadText.inline(text: 'thread-archive-1'),
          leaseRevision: 9,
          state: const ReadText.inline(text: 'preserved'),
          repositoryRoot: const ReadText.inline(text: '/projects/demo'),
          path: const ReadText.inline(
            text: '/projects/demo/.anywork/worktrees/thread-archive-1/session',
          ),
          branch: const ReadText.inline(text: 'pure-session-thread-archive-1'),
          baseCommit: const ReadText.inline(text: 'base-commit'),
          headCommit: null,
          dirty: null,
          changedFiles: null,
        ),
      );
    }
  });

  test('unknown changedFiles reference differs from known total=0; false dirty and known head remain concrete', () {
    final unknown = worktreePreviewFromBridge(
      _worktree(runtime.BridgeWorktreeInspection.unavailable),
    );
    final known = worktreePreviewFromBridge(
      _worktree(
        runtime.BridgeWorktreeInspection.available,
        changedFiles: primitive.BridgeTypedListRef(
          listId: BigInt.from(17),
          total: BigInt.zero,
        ),
        dirty: false,
        head: const primitive.BridgeReadText.inline(text: 'head-commit'),
      ),
    );
    expect(unknown.changedFiles, isNull);
    expect(unknown.dirty, isNull);
    expect(unknown.headCommit, isNull);
    expect(known.changedFiles, const TypedListRef(listId: 17, total: 0));
    expect(known.dirty, isFalse);
    expect(known.headCommit, const ReadText.inline(text: 'head-commit'));
  });

  test('[] grants no action; Retry and Cleanup coexist and preserve original issue fields', () {
    for (final (native, expected)
        in <(List<wire.BridgeRecoveryAction>, List<RecoveryAction>)>[
          ([], []),
          ([wire.BridgeRecoveryAction.retry], [RecoveryAction.retry]),
          (
            [
              wire.BridgeRecoveryAction.retry,
              wire.BridgeRecoveryAction.cleanupWorktree,
            ],
            [RecoveryAction.retry, RecoveryAction.cleanupWorktree],
          ),
          (
            [
              wire.BridgeRecoveryAction.cleanupWorktree,
              wire.BridgeRecoveryAction.retry,
            ],
            [RecoveryAction.cleanupWorktree, RecoveryAction.retry],
          ),
        ]) {
      final converted = recoveryIssueFromBridge(
        wire.BridgeRecoveryIssueRead(
          id: const primitive.BridgeReadText.inline(text: 'worktree-issue'),
          scope: wire.BridgeRecoveryScope.thread,
          category: wire.BridgeRecoveryCategory.repository,
          availableActions: native,
          projectId: const primitive.BridgeReadText.inline(text: 'project'),
          threadId: const primitive.BridgeReadText.inline(
            text: 'thread-archive-1',
          ),
          message: const primitive.BridgeReadText.inline(
            text: 'inspection needs attention',
          ),
          worktree: _worktree(runtime.BridgeWorktreeInspection.unavailable),
        ),
      );
      expect(converted.availableActions, expected);
      expect(converted.id, const ReadText.inline(text: 'worktree-issue'));
      expect(
        converted.threadId,
        const ReadText.inline(text: 'thread-archive-1'),
      );
      expect(
        converted.message,
        const ReadText.inline(text: 'inspection needs attention'),
      );
      expect(
        converted.worktree!.dirty,
        isNull,
        reason: 'Actions do not turn unknown inspection into clean',
      );
    }
  });
}
