import 'package:anywork_client/conversation.dart';
import 'package:anywork_client/resources.dart';
import 'package:test/test.dart';

/// 结构化失败原因的 canonical 标签契约。
///
/// 后端 `StudioErrorReason` 的 camelCase 标签是唯一 wire 身份：客户端必须能解析每个已
/// 批准的原因，并把枚举回写成同一标签；未知标签保持 `null`，不猜测成任何一个已知原因。
void main() {
  test(
    'every studio failure reason round-trips through its canonical label',
    () {
      for (final reason in StudioFailureReason.values) {
        expect(
          StudioFailureReason.fromLabel(reason.label),
          reason,
          reason: '${reason.name} must parse from its own label',
        );
        expect(reason.label, reason.name);
      }
    },
  );

  test('threadArchived is a typed reason, not a neutral message', () {
    expect(
      StudioFailureReason.fromLabel('threadArchived'),
      StudioFailureReason.threadArchived,
    );
    expect(StudioFailureReason.threadArchived.label, 'threadArchived');
    const failure = StudioFailure(
      code: StudioFailureCode.permissionDenied,
      message: 'Archived Thread is read-only',
      retryable: false,
      correlationId: 'archived-thread',
      details: StudioFailureDetails.reason(reason: 'threadArchived'),
    );
    expect(studioFailureReason(failure), StudioFailureReason.threadArchived);
  });

  test('retired or unknown reason labels stay untyped', () {
    expect(StudioFailureReason.fromLabel(null), isNull);
    expect(StudioFailureReason.fromLabel(''), isNull);
    expect(StudioFailureReason.fromLabel('ThreadArchived'), isNull);
    expect(StudioFailureReason.fromLabel('someFutureReason'), isNull);
  });

  test('Control and legacy Reason preserve the typed noExecution and continuationAccepted labels', () {
    const absent = StudioFailure(code: StudioFailureCode.conflict, message: 'No execution', retryable: false,
      correlationId: 'no-execution', details: StudioFailureDetails.control(reason: 'noExecution',
        facts: ControlFailureFacts.expectedExecution(threadId: 'thread', expectedExecutionId: 'ended')));
    const accepted = StudioFailure(code: StudioFailureCode.busy, message: 'Accepted while saving', retryable: true,
      correlationId: 'accepted', details: StudioFailureDetails.control(reason: 'continuationAccepted',
        facts: ControlFailureFacts.continuationAccepted(threadId: 'thread', operationId: 'original-op', accepted: true)));
    expect(studioFailureReason(absent), StudioFailureReason.noExecution);
    expect(studioFailureReason(accepted), StudioFailureReason.continuationAccepted);
    expect(studioFailureReason(accepted.copyWith(details: const StudioFailureDetails.reason(reason: 'continuationAccepted'))), StudioFailureReason.continuationAccepted);
    expect(studioFailureReason(accepted.copyWith(details: const StudioFailureDetails.control(reason: 'futureReason', facts: ControlFailureFacts.unspecified()))), isNull);
  });
}
