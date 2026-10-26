import 'package:anywork/src/infrastructure/frb/studio_api.dart';
import 'package:anywork/src/rust/api/studio/types/product_topic.dart'
    as topic_dto;
import 'package:anywork/src/rust/api/studio/types/response.dart'
    as response_dto;
import 'package:anywork/src/rust/api/studio/types/runtime.dart' as runtime_dto;
import 'package:anywork_client/studio_client.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'recovery FRB frames preserve inspection and unknown cleanup evidence',
    () {
      const cases =
          <(runtime_dto.BridgeWorktreeInspection, WorktreeInspection)>[
            (
              runtime_dto.BridgeWorktreeInspection.available,
              WorktreeInspection.available,
            ),
            (
              runtime_dto.BridgeWorktreeInspection.missing,
              WorktreeInspection.missing,
            ),
            (
              runtime_dto.BridgeWorktreeInspection.identityMismatch,
              WorktreeInspection.identityMismatch,
            ),
            (
              runtime_dto.BridgeWorktreeInspection.unavailable,
              WorktreeInspection.unavailable,
            ),
          ];

      for (final (wireInspection, expectedInspection) in cases) {
        final issue = runtime_dto.BridgeStudioRecoveryIssueDto(
          id: 'worktree-recovery',
          scope: runtime_dto.BridgeRecoveryIssueScope.thread,
          category: runtime_dto.BridgeRecoveryIssueCategory.repository,
          availableActions: const [runtime_dto.BridgeRecoveryIssueAction.retry],
          detail: 'worktree inspection needs attention',
          worktree: runtime_dto.BridgeWorktreeRecoveryPreviewDto(
            inspection: wireInspection,
            ownerKind: runtime_dto.BridgeWorktreeOwner.session,
            ownerThreadId: 'thread-archive-1',
            leaseRevision: BigInt.from(9),
            state: 'preserved',
            repositoryRoot: '/projects/demo',
            path: '/projects/demo/.anywork/worktrees/thread-archive-1/session',
            branch: 'pure-session-thread-archive-1',
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
        final worktree = convertedIssue.worktree!;
        expect(worktree.inspection, expectedInspection);
        expect(worktree.dirty, isNull);
        expect(worktree.changedFiles, isNull);
        expect(worktree.headCommit, isNull);
        expect(
          worktree.path,
          '/projects/demo/.anywork/worktrees/thread-archive-1/session',
        );
        expect(convertedIssue.availableActions, [RecoveryIssueAction.retry]);
        expect(convertedIssue.canCleanup, isFalse);
      }
    },
  );
}
