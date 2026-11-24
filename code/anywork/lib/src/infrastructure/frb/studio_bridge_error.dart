import 'package:anywork_client/models.dart' show StudioFailureCode;

import '../../rust/api/studio/types/error.dart' as frb_error;

/// Maps each generated FRB error code to the transport-neutral failure code.
StudioFailureCode studioFailureCodeFromBridge(frb_error.BridgeErrorCode code) {
  return switch (code) {
    frb_error.BridgeErrorCode.notInitialized =>
      StudioFailureCode.notInitialized,
    frb_error.BridgeErrorCode.runtimeStopped =>
      StudioFailureCode.runtimeStopped,
    frb_error.BridgeErrorCode.instanceBusy => StudioFailureCode.instanceBusy,
    frb_error.BridgeErrorCode.invalidArgument =>
      StudioFailureCode.invalidArgument,
    frb_error.BridgeErrorCode.notFound => StudioFailureCode.notFound,
    frb_error.BridgeErrorCode.busy => StudioFailureCode.busy,
    frb_error.BridgeErrorCode.conflict => StudioFailureCode.conflict,
    frb_error.BridgeErrorCode.staleRevision => StudioFailureCode.staleRevision,
    frb_error.BridgeErrorCode.permissionDenied =>
      StudioFailureCode.permissionDenied,
    frb_error.BridgeErrorCode.cancelled => StudioFailureCode.cancelled,
    frb_error.BridgeErrorCode.cancellationTooLate =>
      StudioFailureCode.cancellationTooLate,
    frb_error.BridgeErrorCode.overloaded => StudioFailureCode.overloaded,
    frb_error.BridgeErrorCode.unavailable => StudioFailureCode.unavailable,
    frb_error.BridgeErrorCode.protocol => StudioFailureCode.protocol,
    frb_error.BridgeErrorCode.storage => StudioFailureCode.storage,
    frb_error.BridgeErrorCode.update => StudioFailureCode.update,
    frb_error.BridgeErrorCode.internal => StudioFailureCode.internal,
  };
}
