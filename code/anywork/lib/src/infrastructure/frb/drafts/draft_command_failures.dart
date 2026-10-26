import 'package:anywork_client/operations_ports.dart';
import 'package:anywork_client/resources.dart';

import '../../../rust/api/studio/draft_commands/types.dart' as native;
import '../shared/adapter_failure.dart';
import '../shared/bridge_failure.dart';

StudioFailure draftCommandFailure(Object error) {
  if (error case CommandDispatchFailure(:final failure)) return failure;
  try {
    return bridgeFailure(error);
  } on Object catch (mappingError) {
    return adapterFailure(mappingError, operation: 'draft-command-error');
  }
}

/// Only the native registration boundary can prove rejection after invocation.
CommandDispatchFailure draftBeginFailure(Object error) => switch (error) {
  native.BridgeDraftCommandBeginFailure_Rejected(:final error) =>
    CommandDispatchFailure.rejected(failure: draftCommandFailure(error)),
  native.BridgeDraftCommandBeginFailure_UnknownOutcome(:final error) =>
    CommandDispatchFailure.unknownOutcome(failure: draftCommandFailure(error)),
  _ => CommandDispatchFailure.unknownOutcome(
    failure: draftCommandFailure(error),
  ),
};
