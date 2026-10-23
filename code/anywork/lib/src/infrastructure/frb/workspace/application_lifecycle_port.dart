import 'package:anywork_client/resources.dart';
import 'package:anywork_client/workspace_ports.dart';

import '../../../rust/api/studio/handlers/lifecycle.dart' as native;
import '../../../rust/api/studio/types/shutdown.dart' as wire;
import '../shared/bridge_failure.dart';
import '../shared/shutdown_issue_converters.dart';
import 'shutdown_converters.dart';

/// The app's U3 coordinator owns intent, first deadline and finalizer admission.
/// This port only forwards the original remaining budget and typed results.
final class FrbApplicationLifecyclePort implements ApplicationLifecyclePort {
  const FrbApplicationLifecyclePort();

  @override
  Future<void> beginRuntimeExit({required int remainingMs}) => bridgeQuery(
    () => native.beginRuntimeExit(remainingMs: _milliseconds(remainingMs)),
  );

  @override
  Future<StudioExitReport> shutdownRuntime({
    required int remainingMs,
    required List<StudioShutdownIssue> externalIssues,
    required ExitIntent intent,
  }) {
    // Freeze exact caller evidence before the first await, without a second
    // issue collector or a post-Clean merge.
    final issues = List<wire.BridgeShutdownIssue>.unmodifiable([
      for (final issue in externalIssues) shutdownIssueToBridge(issue),
    ]);
    final budget = _milliseconds(remainingMs);
    final nativeIntent = switch (intent) {
      ExitIntent.exit => wire.BridgeExitIntent.exit,
      ExitIntent.updateRestart => wire.BridgeExitIntent.updateRestart,
    };
    return bridgeQuery(() async => exitReportFromBridge(
      await native.shutdownRuntime(
        remainingMs: budget,
        externalIssues: issues,
        intent: nativeIntent,
      ),
    ));
  }

  @override
  Future<void> finishShutdownDiagnostics() =>
      bridgeQuery(native.finishShutdownDiagnostics);
}

int _milliseconds(int value) {
  if (value < 0 || value > 0xffffffff) {
    throw const StudioFailure(
      code: StudioFailureCode.invalidArgument,
      message: 'The remaining exit budget is outside the native millisecond range',
      retryable: false,
      correlationId: 'adapter-exit-budget',
    );
  }
  return value;
}
