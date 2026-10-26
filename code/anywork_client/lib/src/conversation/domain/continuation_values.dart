import 'package:freezed_annotation/freezed_annotation.dart';

import '../../../operations.dart';
import '../../../resources.dart' show OperationId;

part 'continuation_values.freezed.dart';

@Freezed(toStringOverride: false)
abstract class ContinueThreadReply with _$ContinueThreadReply {
  const factory ContinueThreadReply({
    required String threadId,
    required String inputId,
    required String continuationId,
    required int cursor,
    required CommitReceipt receipt,
  }) = _ContinueThreadReply;
}

@freezed
sealed class ContinuationOperationState with _$ContinuationOperationState {
  const factory ContinuationOperationState.pending() = PendingContinuation;
  const factory ContinuationOperationState.consumed({required String turnId}) = ConsumedContinuation;
  const factory ContinuationOperationState.discarded() = DiscardedContinuation;
}

@Freezed(toStringOverride: false)
abstract class ContinuationOperationView with _$ContinuationOperationView {
  const factory ContinuationOperationView({
    required String threadId,
    required OperationId operationId,
    required String inputId,
    required String continuationId,
    required int acceptedSequence,
    required ContinuationOperationState state,
    required bool durable,
    required CommitReceipt receipt,
  }) = _ContinuationOperationView;
}
