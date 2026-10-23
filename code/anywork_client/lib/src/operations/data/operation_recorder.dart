import '../../resources/domain/failures.dart';
import '../../resources/domain/identity.dart';
import '../domain/operation_models.dart';
import '../domain/operations.dart';

abstract interface class OperationRecorder {
  Operations get observations;
  OperationWriter<T> begin<T>({required String target, DraftStamp? draft});
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
  void synchronizationFailed(StudioFailure error, {T? value, CommitReceipt? receipt});
  void acknowledgedSynchronizationFailed(StudioFailure error, {T? value});
}
