import 'package:anywork/src/infrastructure/frb/studio_api.dart';
import 'package:anywork/src/rust/api/studio/types/product_topic.dart'
    as topic_dto;
import 'package:anywork/src/rust/api/studio/types/response.dart'
    as response_dto;
import 'package:anywork/src/rust/api/studio/types/runtime.dart' as runtime_dto;
import 'package:anywork_client/studio_client.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('recovery FRB frames preserve impact gates, inspection and unknown cleanup evidence', () {
    const cases =
        <
          (
            runtime_dto.BridgeWorktreeInspection,
            WorktreeInspection,
            String?,
            runtime_dto.BridgeRecoveryImpact,
            RecoveryIssueImpact,
          )
        >[
          (
            runtime_dto.BridgeWorktreeInspection.available,
            WorktreeInspection.available,
            null,
            runtime_dto.BridgeRecoveryImpact.advisory,
            RecoveryIssueImpact.advisory,
          ),
          (
            runtime_dto.BridgeWorktreeInspection.missing,
            WorktreeInspection.missing,
            null,
            runtime_dto.BridgeRecoveryImpact.executionBlocked,
            RecoveryIssueImpact.executionBlocked,
          ),
          (
            runtime_dto.BridgeWorktreeInspection.missing,
            WorktreeInspection.missing,
            'topic/kept',
            runtime_dto.BridgeRecoveryImpact.executionBlocked,
            RecoveryIssueImpact.executionBlocked,
          ),
          (
            runtime_dto.BridgeWorktreeInspection.identityMismatch,
            WorktreeInspection.identityMismatch,
            null,
            runtime_dto.BridgeRecoveryImpact.executionBlocked,
            RecoveryIssueImpact.executionBlocked,
          ),
          (
            runtime_dto.BridgeWorktreeInspection.unavailable,
            WorktreeInspection.unavailable,
            null,
            runtime_dto.BridgeRecoveryImpact.accessBlocked,
            RecoveryIssueImpact.accessBlocked,
          ),
        ];

    for (final (
          wireInspection,
          expectedInspection,
          branch,
          wireImpact,
          expectedImpact,
        )
        in cases) {
      final issue = runtime_dto.BridgeStudioRecoveryIssueDto(
        id: 'worktree-recovery',
        scope: runtime_dto.BridgeRecoveryIssueScope.thread,
        category: expectedImpact == RecoveryIssueImpact.accessBlocked
            ? runtime_dto.BridgeRecoveryIssueCategory.storage
            : runtime_dto.BridgeRecoveryIssueCategory.repository,
        impact: wireImpact,
        availableActions: const [runtime_dto.BridgeRecoveryIssueAction.retry],
        threadId: 'thread-archive-1',
        detail: 'worktree inspection needs attention',
        worktree: runtime_dto.BridgeWorktreeRecoveryPreviewDto(
          inspection: wireInspection,
          ownerKind: runtime_dto.BridgeWorktreeOwner.session,
          ownerThreadId: 'thread-archive-1',
          leaseRevision: BigInt.from(9),
          state: 'preserved',
          repositoryRoot: '/projects/demo',
          path: '/projects/demo/.anywork/worktrees/thread-archive-1/session',
          branch: branch,
          baseCommit: 'base-commit',
          headCommit: null,
          dirty: null,
          changedFiles: null,
        ),
      );
      final frame = productTopicFrameFromEnvelope(
        const RecoveryTopic(),
        topic_dto.BridgeProductTopicStreamEnvelope.baseline(
          topic: const topic_dto.BridgeProductTopic.recovery(),
          revision: BigInt.from(12),
          state: topic_dto.BridgeProductBaseline.recovery(
            response_dto.BridgeRecoveryStateSnapshot.ready(
              resource: runtime_dto.BridgeReadyResource(
                revision: BigInt.from(12),
                updatedAt: 1718000000,
              ),
              value: response_dto.BridgeRecoveryStateData(issues: [issue]),
            ),
          ),
        ),
      );

      expect(frame, isA<ProductTopicBaselineFrame>());
      final baseline = frame! as ProductTopicBaselineFrame;
      expect(baseline.state, isA<RecoveryBaseline>());
      final recovery = (baseline.state as RecoveryBaseline).state;
      final convertedIssue = recovery.values.single;
      expect(convertedIssue.impact, expectedImpact);
      expect(
        recoveryIssueBlockingAccess(
          recovery.values,
          projectId: null,
          threadId: 'thread-archive-1',
        ),
        expectedImpact == RecoveryIssueImpact.accessBlocked
            ? same(convertedIssue)
            : isNull,
      );
      expect(
        recoveryIssueBlockingExecution(
          recovery.values,
          projectId: null,
          threadId: 'thread-archive-1',
        ),
        expectedImpact == RecoveryIssueImpact.advisory
            ? isNull
            : same(convertedIssue),
      );
      expect(
        recoveryIssueBlockingExecution(
          recovery.values,
          projectId: null,
          threadId: 'healthy-root',
        ),
        isNull,
      );
      final worktree = convertedIssue.worktree!;
      expect(worktree.inspection, expectedInspection);
      expect(worktree.dirty, isNull);
      expect(worktree.changedFiles, isNull);
      expect(worktree.headCommit, isNull);
      expect(worktree.branch, branch);
      expect(
        worktree.path,
        '/projects/demo/.anywork/worktrees/thread-archive-1/session',
      );
      expect(convertedIssue.availableActions, [RecoveryIssueAction.retry]);
      expect(convertedIssue.canCleanup, isFalse);
    }
  });
}
