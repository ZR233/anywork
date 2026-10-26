import 'dart:async';
import 'dart:io';

import 'package:anywork_client/resources_ports.dart';
import 'package:anywork_client/workspace_ports.dart';

/// Driver-only decoration at the real StartupPort injection boundary. Every
/// non-initialization capability forwards the same original production owner.
StartupPort decorateDriverStartup(StartupPort port) {
  final fault = Platform.environment['ANYWORK_DRIVER_SHUTDOWN_FAULT'];
  if (fault == null) return port;
  return switch (fault) {
    'pending-init' || 'bridge-load-error' => _DriverLibraryFault(port, fault),
    _ => port,
  };
}

final class _DriverLibraryFault implements StartupPort {
  _DriverLibraryFault(this.original, this.fault);
  final StartupPort original;
  final String fault;

  @override
  Future<void> initializeLibrary() => fault == 'pending-init'
      ? Completer<void>().future
      : Future<void>.error(
          const StudioFailure(
            code: StudioFailureCode.unavailable,
            message: 'Driver-injected library initialization failure',
            retryable: false,
            correlationId: 'driver-library-fault',
          ),
        );

  @override
  Future<int> prepareStartupAttempt() => original.prepareStartupAttempt();
  @override
  Future<FeedConnection<StartupProgressFrame>> openStartupProgress(
    int attemptId,
  ) => original.openStartupProgress(attemptId);
  @override
  Future<RuntimeReady> startStudioRuntime(int attemptId) =>
      original.startStudioRuntime(attemptId);
  @override
  Future<RuntimeStartupReadConnection> openStartupRead(
    RuntimeStartupReadRef reference,
  ) => original.openStartupRead(reference);
}
