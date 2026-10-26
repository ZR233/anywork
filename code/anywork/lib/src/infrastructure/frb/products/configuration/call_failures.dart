import 'package:anywork_client/operations_ports.dart';
import 'package:anywork_client/resources.dart';

import '../../../../rust/api/studio/types/error.dart' as native;
import '../../shared/adapter_failure.dart';
import '../../shared/bridge_failure.dart';

StudioFailure configurationCallFailure(Object error) {
  if (error case CommandDispatchFailure(:final failure)) return failure;
  try {
    return bridgeFailure(error);
  } on Object catch (mappingError) {
    return adapterFailure(mappingError, operation: 'configuration-call-error');
  }
}

/// This is used only around the actual native begin invocation. A decoded
/// BridgeError is that API's explicit no-call admission Result-Err. Generic
/// transport/codec/lost replies have no such evidence and remain Unknown.
CommandDispatchFailure configurationBeginFailure(Object error) =>
    error is native.BridgeError
    ? CommandDispatchFailure.rejected(failure: configurationCallFailure(error))
    : CommandDispatchFailure.unknownOutcome(
        failure: configurationCallFailure(error),
      );

CommandDispatchFailure configurationUnknownFailure(Object error) =>
    error is CommandDispatchFailure
    ? error
    : CommandDispatchFailure.unknownOutcome(
        failure: configurationCallFailure(error),
      );

void requireConfigurationOperation(String actual, OperationId expected) {
  if (actual != expected.value || actual.trim().isEmpty) {
    throw adapterProtocol('configuration-call-operation');
  }
}
