import 'package:anywork_client/resources.dart';

import '../../../rust/api/studio/types/shutdown.dart' as native;

StudioShutdownIssue shutdownIssueFromBridge(native.BridgeShutdownIssue value) =>
    StudioShutdownIssue(
      stage: value.stage,
      code: value.code,
      message: value.message,
      retryable: value.retryable,
      correlationId: value.correlationId,
    );

native.BridgeShutdownIssue shutdownIssueToBridge(StudioShutdownIssue value) =>
    native.BridgeShutdownIssue(
      stage: value.stage,
      code: value.code,
      message: value.message,
      retryable: value.retryable,
      correlationId: value.correlationId,
    );
