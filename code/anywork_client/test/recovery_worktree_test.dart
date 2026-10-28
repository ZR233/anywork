import 'dart:async';

import 'package:anywork_client/operations_ports.dart';
import 'package:anywork_client/recovery_ports.dart';
import 'package:anywork_client/resources_ports.dart';
import 'package:test/test.dart';

import 'support/profile_recovery_port.dart';

const _preview = WorktreeRecoveryPreviewRead(
  inspection: WorktreeInspection.unavailable,
  ownerKind: WorktreeOwner.child,
  ownerThreadId: ReadText.inline(text: 'actual-child-owner'),
  leaseRevision: 17,
  state: ReadText.inline(text: 'preserved'),
  repositoryRoot: ReadText.inline(text: '/repository'),
  path: ReadText.inline(text: '/child-worktree'),
  branch: ReadText.inline(text: 'child-branch'),
  baseCommit: ReadText.inline(text: 'saved-base'),
  headCommit: null,
  dirty: null,
  changedFiles: null,
);
const _issue = RecoveryIssueRead(
  id: ReadText.inline(text: 'worktree-child'),
  scope: RecoveryScope.thread,
  category: RecoveryCategory.repository,
  availableActions: [RecoveryAction.retry, RecoveryAction.cleanupWorktree],
  projectId: ReadText.inline(text: 'project'),
  threadId: ReadText.inline(text: 'actual-child-owner'),
  message: ReadText.inline(text: 'Remote inspection is unavailable'),
  worktree: _preview,
);

void main() {
  test('Retry-only and empty availableActions cannot authorize cleanup from a nonempty unknown worktree', () async {
    final budget = ResourceBudget();
    final operations = OperationRegistry(
      clientId: 'recovery-actions',
      budget: budget,
    );
    final port = ProfileRecoveryPort()
      ..preparedIssues = [
        _issue.copyWith(
          id: const ReadText.inline(text: 'retry-only'),
          availableActions: [RecoveryAction.retry],
        ),
        _issue.copyWith(
          id: const ReadText.inline(text: 'no-actions'),
          availableActions: [],
        ),
      ];
    final repository = createRecoveryRepository(
      port: port,
      budget: budget,
      operations: operations,
    );
    addTearDown(() async {
      await repository.close();
    });
    await port.establish(repository);
    final window =
        (repository.state.value.issues
                as CurrentCollectionMirror<RecoveryIssue>)
            .window;
    final issues = [
      for (final reference in window.entries)
        (window.rows[reference.entry]
                as ReadyReadValue<RecoveryIssue, ProductEntityRef>)
            .current
            .value,
    ];
    expect(issues.map((issue) => issue.availableActions), [
      [RecoveryAction.retry],
      <RecoveryAction>[],
    ]);
    expect((issues.first.canRetry, issues.first.canCleanup), (true, false));
    expect((issues.last.canRetry, issues.last.canCleanup), (false, false));
    for (final issue in issues) {
      expect(issue.worktree, isNotNull);
      expect(issue.worktree!.inspection, WorktreeInspection.unavailable);
      expect(issue.worktree!.dirty, isNull);
      expect(issue.worktree!.changedFiles, isNull);
      expect(
        issue.canCleanup,
        isFalse,
        reason: 'Only availableActions grants a cleanup action.',
      );
    }
  });
  test('Recovery preserves unknown inspection facts and actual child owner; cleanup does not hide Retry', () async {
    final budget = ResourceBudget();
    final operations = OperationRegistry(
      clientId: 'recovery-contract',
      budget: budget,
    );
    final port = ProfileRecoveryPort()..preparedIssues = [_issue];
    final repository = createRecoveryRepository(
      port: port,
      budget: budget,
      operations: operations,
    );
    addTearDown(() async {
      await repository.close();
    });
    await port.establish(repository);
    final window =
        (repository.state.value.issues
                as CurrentCollectionMirror<RecoveryIssue>)
            .window;
    final issue =
        (window.rows[window.entries.single.entry]
                as ReadyReadValue<RecoveryIssue, ProductEntityRef>)
            .current
            .value;
    expect(issue.threadId, 'actual-child-owner');
    expect(issue.worktree!.ownerThreadId, issue.threadId);
    expect(issue.worktree!.inspection, WorktreeInspection.unavailable);
    expect(issue.worktree!.headCommit, isNull);
    expect(issue.worktree!.dirty, isNull);
    expect(
      issue.worktree!.changedFiles,
      isNull,
      reason: 'Unknown is not an empty list claiming a clean worktree.',
    );
    expect((issue.canRetry, issue.canCleanup), (true, true));
    final entered = Completer<(WorktreeOwner, String, int)>();
    final native = Completer<void>();
    port.onCleanup = (owner, thread, revision) {
      entered.complete((owner, thread, revision));
      return native.future;
    };
    final ticket = repository.cleanupWorktree(
      issue.worktree!.ownerKind,
      issue.worktree!.ownerThreadId,
      issue.worktree!.leaseRevision,
    );
    expect(await entered.future, (
      WorktreeOwner.child,
      'actual-child-owner',
      17,
    ));
    var joined = false;
    final closing = repository.close().then((report) {
      joined = true;
      return report;
    });
    expect(joined, isFalse);
    native.complete();
    expect(await ticket.result, isA<AcknowledgedCommandResult<Unit>>());
    expect((await closing).complete, isTrue);
    expect(joined, isTrue);
  });
}
