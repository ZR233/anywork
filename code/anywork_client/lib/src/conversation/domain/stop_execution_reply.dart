import 'package:freezed_annotation/freezed_annotation.dart';

import '../../../operations.dart';

part 'stop_execution_reply.freezed.dart';

/// Native cancellation acceptance, not proof that the original execution stopped.
@Freezed(toStringOverride: false)
abstract class StopExecutionReply with _$StopExecutionReply {
  const factory StopExecutionReply({
    required String threadId,
    required String executionId,
    required bool stopped,
    required CommitReceipt receipt,
  }) = _StopExecutionReply;
}
