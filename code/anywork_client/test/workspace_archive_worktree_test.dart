import 'package:anywork_client/operations_ports.dart';
import 'package:anywork_client/recovery_ports.dart';
import 'package:anywork_client/resources_ports.dart';
import 'package:anywork_client/workspace_ports.dart';
import 'package:test/test.dart';

import 'support/conversation_fixture.dart';
import 'support/profile_native_pin.dart';
import 'support/profile_recovery_port.dart';
import 'support/workspace_selection_fixture.dart';

const _worktree = WorktreeRecoveryPreviewRead(
  inspection: WorktreeInspection.unavailable,
  ownerKind: WorktreeOwner.session,
  ownerThreadId: ReadText.inline(text: 'root'),
  leaseRevision: 7,
  state: ReadText.inline(text: 'preserved'),
  repositoryRoot: ReadText.inline(text: '/repository'),
  path: ReadText.inline(text: '/missing-or-offline'),
  branch: ReadText.inline(text: 'preserved-branch'),
  baseCommit: ReadText.inline(text: 'saved-base'),
  headCommit: null,
  dirty: null,
  changedFiles: null,
);
const _issue = RecoveryIssueRead(
  id: ReadText.inline(text: 'root-worktree'),
  scope: RecoveryScope.thread,
  category: RecoveryCategory.repository,
  availableActions: [RecoveryAction.retry],
  projectId: ReadText.inline(text: 'project'),
  threadId: ReadText.inline(text: 'root'),
  message: ReadText.inline(text: 'The remote worktree cannot be inspected'),
  worktree: _worktree,
);
const _saveFailed = StudioFailure(
  code: StudioFailureCode.storage,
  message: 'Actual original save failed',
  retryable: true,
  correlationId: 'original-save',
);
const _denied = StudioFailure(
  code: StudioFailureCode.permissionDenied,
  message: 'Original archive permission denied',
  retryable: false,
  correlationId: 'original-permission',
);

Future<WorkspaceSelectionFixture> _fixture() async {
  final fixture = WorkspaceSelectionFixture();
  addTearDown(() async {
    await fixture.close();
  });
  fixture.recoveryPort.preparedIssues = [_issue];
  await fixture.establishAccess();
  return fixture;
}

Future<CommandResult<ArchiveThreadResult>> _archive(
  WorkspaceSelectionFixture fixture,
) async {
  final ticket = fixture.workspace.archiveThread('root');
  await fixture.directory.threadBaseline(
    0,
    fixtureThread('root').copyWith(
      workspaceMode: ThreadWorkspaceMode.worktree,
      workspacePath: '/missing-or-offline',
    ),
  );
  return ticket.result;
}

void main() {
  for (final nativeFailure in [_saveFailed, _denied]) {
    test(
      'worktree inspection failure does not block archive; actual ${nativeFailure.code.name} rejection stays visible',
      () async {
        final fixture = await _fixture();
        final calls = <(String, OperationId)>[];
        fixture.directory.onArchiveThread = (thread, operation) async {
          calls.add((thread, operation));
          throw CommandDispatchFailure.rejected(failure: nativeFailure);
        };
        final result = await _archive(fixture);
        expect(
          calls.single.$1,
          'root',
          reason: 'Worktree Recovery must not preempt the original archive/save command.',
        );
        expect(result, isA<RejectedCommandResult<ArchiveThreadResult>>());
        expect(
          (result as RejectedCommandResult<ArchiveThreadResult>).error,
          nativeFailure,
        );
        expect(fixture.directory.activations, isEmpty);
        expect(fixture.conversations.facets.execution, isEmpty);
      },
    );
  }

  test('archive still rejects an unavailable original Recovery source rather than trusting retained worktree facts', () async {
    final fixture = await _fixture();
    fixture.recoveryPort.feed.emit(
      RecoveryFrame.failure(
        identity: profileIdentity(
          fixture.recoveryPort.feed.feedId,
          ProfileRecoveryPort.origin,
          ProductResource.recovery,
        ),
        error: _saveFailed,
      ),
    );
    await fixture.recovery.state.waitFor(
      (state) => state.projection.sync.phase == ResourceSyncPhase.failed,
    );
    var calls = 0;
    fixture.directory.onArchiveThread = (_, __) async {
      calls++;
      throw const CommandDispatchFailure.rejected(failure: _denied);
    };
    final result = await _archive(fixture);
    expect(result, isA<RejectedCommandResult<ArchiveThreadResult>>());
    expect(
      calls,
      0,
      reason: 'Purpose-specific worktree exemption does not remove source/window/identity validation.',
    );
    expect(fixture.directory.activations, isEmpty);
  });
}
