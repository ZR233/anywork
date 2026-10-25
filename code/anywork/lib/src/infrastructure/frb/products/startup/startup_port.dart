import 'package:anywork_client/operations_ports.dart';
import 'package:anywork_client/resources_ports.dart';
import 'package:anywork_client/workspace_ports.dart';

import '../../../../rust/api/studio/products/feed/startup_transport.dart'
    as native;
import '../../../../rust/frb_generated.dart';
import '../../shared/bridge_failure.dart';
import '../../shared/exact_numbers.dart';
import 'startup_progress_connection.dart';
import 'startup_read_connection.dart';
import 'startup_values.dart';

StartupPort createStartupPort() => FrbStartupPort();

/// Construction only installs an owner. Library loading belongs to the explicit
/// StartupRepository.start flow, after its operation and permit are registered.
final class FrbStartupPort implements StartupPort {
  FrbStartupPort();

  Future<void>? _initialization;

  @override
  Future<void> initializeLibrary() => _initialization ??= _initialize();

  Future<void> _initialize() async {
    try {
      await bridgeQuery(() async {
        if (!RustLib.instance.initialized) await RustLib.init();
        await native.initializeLibrary();
      });
    } catch (_) {
      // Explicit startup retry may retry loading; an already-loaded FRB library
      // is not initialized a second time if only the native initializer failed.
      _initialization = null;
      rethrow;
    }
  }

  @override
  Future<int> prepareStartupAttempt() => bridgeQuery(
    () async =>
        exactU64(await native.prepareStartupAttempt(), 'startup attempt'),
  );

  @override
  Future<FeedConnection<StartupProgressFrame>> openStartupProgress(
    int attemptId,
  ) async {
    final connection = FrbStartupProgressConnection(attemptId);
    await connection.opened;
    return connection;
  }

  @override
  Future<RuntimeReady> startStudioRuntime(int attemptId) async {
    final BigInt attempt;
    try {
      attempt = nativeU64(attemptId, 'startup attempt');
    } on Object catch (error, stack) {
      Error.throwWithStackTrace(
        CommandDispatchFailure.rejected(failure: bridgeFailure(error)),
        stack,
      );
    }
    final result = await bridgeQuery(
      () => native.startStudioRuntime(attemptId: attempt),
    );
    try {
      return runtimeReadyFromBridge(result);
    } on Object catch (error, stack) {
      Error.throwWithStackTrace(
        CommandDispatchFailure.confirmedWithoutUsableReceipt(
          failure: bridgeFailure(error),
        ),
        stack,
      );
    }
  }

  @override
  Future<RuntimeStartupReadConnection> openStartupRead(
    RuntimeStartupReadRef reference,
  ) async {
    final connection = FrbStartupReadConnection(reference);
    await connection.opened;
    return connection;
  }
}
