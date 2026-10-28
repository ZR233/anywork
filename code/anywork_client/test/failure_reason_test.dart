import 'package:anywork_client/studio_client.dart';
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
      detailsJson: '{"reason":"threadArchived","threadId":"thread"}',
      reason: StudioFailureReason.threadArchived,
    );
    expect(studioFailureReason(failure), StudioFailureReason.threadArchived);
  });

  test('retired or unknown reason labels stay untyped', () {
    expect(StudioFailureReason.fromLabel(null), isNull);
    expect(StudioFailureReason.fromLabel(''), isNull);
    expect(StudioFailureReason.fromLabel('ThreadArchived'), isNull);
    expect(StudioFailureReason.fromLabel('someFutureReason'), isNull);
  });
}
