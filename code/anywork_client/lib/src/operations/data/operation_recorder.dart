import '../../resources/domain/failures.dart';
import '../../resources/domain/identity.dart';
import '../domain/operation_models.dart';
import '../domain/operations.dart';

abstract interface class OperationRecorder {
  Operations get observations;

  /// Freezes an additional owner obligation without changing a native receipt.
  /// identityObserved must cover every applicable native and owner obligation.
  /// operationId explicitly resumes a retained, known CAS-rejected intent.
  /// Each attempt has its own immutable result Future; old tickets never resettle.
  OperationWriter<T> begin<T>({
    required String target,
    DraftStamp? draft,
    OperationId? operationId,
    bool requireIdentityObservation = false,
  });
  void observe(ObservationStamp stamp);
  void seal();
}

abstract interface class OperationWriter<T> {
  OperationTicket<T> get ticket;
  void accepted(T value, CommitReceipt receipt);
  void acknowledged(T value);
  void identityObserved();
  void effective();
  void durable();
  void evidenceFailed(StudioFailure error);
  void rejected(StudioFailure error);
  void unknownOutcome(StudioFailure error);
  void synchronizationFailed(
    StudioFailure error, {
    T? value,
    CommitReceipt? receipt,
  });
  void acknowledgedSynchronizationFailed(StudioFailure error, {T? value});
}
