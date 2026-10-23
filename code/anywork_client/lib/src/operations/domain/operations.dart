import '../../resources/domain/identity.dart';
import '../../resources/domain/observation.dart';
import 'operation_models.dart';

abstract interface class OperationObservation {
  OperationId get id;
  ReadonlyLatestValue<OperationState> get state;
}

/// A borrowed read-only result, never the registry's settlement capability.
abstract interface class OperationTicket<T> implements OperationObservation {
  Future<CommandResult<T>> get result;
}

abstract interface class Operations {
  OperationObservation? lookup(OperationId id);
  OperationObservation? latest(String target);
  ReadonlyLatestValue<List<OperationState>> get records;
}
