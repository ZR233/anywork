import 'package:freezed_annotation/freezed_annotation.dart';

import '../../resources/domain/failures.dart';
import '../domain/operation_models.dart';

part 'command_dispatch_failure.freezed.dart';

/// Dispatch evidence comes from the actual native/adapter commit boundary,
/// never from an error code, retryable flag or diagnostic message.
@Freezed(toStringOverride: false)
sealed class CommandDispatchFailure with _$CommandDispatchFailure
    implements Exception {
  const factory CommandDispatchFailure.rejected({
    required StudioFailure failure,
  }) = RejectedCommandDispatchFailure;
  const factory CommandDispatchFailure.unknownOutcome({
    required StudioFailure failure,
  }) = UnknownOutcomeCommandDispatchFailure;
  const factory CommandDispatchFailure.committedButUnobserved({
    required CommitReceipt receipt,
    required StudioFailure failure,
  }) = CommittedButUnobservedCommandDispatchFailure;
  const factory CommandDispatchFailure.confirmedWithoutUsableReceipt({
    required StudioFailure failure,
  }) = ConfirmedWithoutUsableReceiptCommandDispatchFailure;
}
