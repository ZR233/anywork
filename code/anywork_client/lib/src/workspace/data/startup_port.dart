import 'package:freezed_annotation/freezed_annotation.dart';

import 'package:anywork_client/resources.dart';
import 'package:anywork_client/resources_ports.dart';

import '../domain/startup_values.dart';

part 'startup_port.freezed.dart';

enum StartupCloseReason { requested, attemptReplaced, completed, runtimeStopped }

@Freezed(toStringOverride: false)
sealed class StartupProgressFrame with _$StartupProgressFrame {
  const factory StartupProgressFrame.data({
    required int deliverySequence,
    required StartupStage stage,
  }) = DataStartupProgressFrame;
  const factory StartupProgressFrame.failure({required StudioFailure error}) =
      FailureStartupProgressFrame;
  const factory StartupProgressFrame.closed({required StartupCloseReason reason}) =
      ClosedStartupProgressFrame;
}

abstract interface class StartupPort {
  Future<void> initializeLibrary();
  Future<int> prepareStartupAttempt();
  Future<FeedConnection<StartupProgressFrame>> openStartupProgress(int attemptId);
  Future<RuntimeReady> startStudioRuntime(int attemptId);
  Future<RuntimeStartupReadConnection> openStartupRead(
    RuntimeStartupReadRef reference,
  );
}

abstract interface class ApplicationLifecyclePort {
  Future<void> beginRuntimeExit({required int remainingMs});
  Future<StudioExitReport> shutdownRuntime({
    required int remainingMs,
    required List<StudioShutdownIssue> externalIssues,
    required ExitIntent intent,
  });
  Future<void> finishShutdownDiagnostics();
}

@freezed
abstract class RuntimeStartupScopeIdentity with _$RuntimeStartupScopeIdentity {
  const factory RuntimeStartupScopeIdentity({
    required String scopeId,
    required String ownerEpoch,
    required int attemptId,
    required int revision,
  }) = _RuntimeStartupScopeIdentity;
}

@Freezed(toStringOverride: false)
sealed class RuntimeStateRead with _$RuntimeStateRead {
  const factory RuntimeStateRead.uninitialized({required int at}) =
      UninitializedRuntimeStateRead;
  const factory RuntimeStateRead.initializing({required int at}) =
      InitializingRuntimeStateRead;
  const factory RuntimeStateRead.ready({required int at}) = ReadyRuntimeStateRead;
  const factory RuntimeStateRead.shuttingDown({required int at}) =
      ShuttingDownRuntimeStateRead;
  const factory RuntimeStateRead.stopped({required int at}) = StoppedRuntimeStateRead;
  const factory RuntimeStateRead.failed({
    required int failedAt,
    required SourceStateErrorRead error,
  }) = FailedRuntimeStateRead;
}

@Freezed(toStringOverride: false)
abstract class StartupRecoveryRead with _$StartupRecoveryRead {
  const factory StartupRecoveryRead({
    required ReadText backupPath,
    required ReadText reason,
    required int createdAt,
  }) = _StartupRecoveryRead;
}

@freezed
abstract class StartupActiveTurnRead with _$StartupActiveTurnRead {
  const factory StartupActiveTurnRead({
    required ReadText threadId,
    required ReadText turnId,
  }) = _StartupActiveTurnRead;
}

@Freezed(toStringOverride: false)
abstract class RuntimeStartupReadHeader with _$RuntimeStartupReadHeader {
  const factory RuntimeStartupReadHeader({
    required RuntimeStartupScopeIdentity scope,
    required RuntimeStartupReadRef reference,
    required int revision,
    required RuntimeStateRead state,
    required StartupRecoveryRead? startupRecovery,
    required int activeTurnCount,
  }) = _RuntimeStartupReadHeader;
}

@freezed
abstract class StartupActiveTurnReadPage with _$StartupActiveTurnReadPage {
  const factory StartupActiveTurnReadPage({
    required int offset,
    required int total,
    required List<StartupActiveTurnRead> items,
    required int? nextOffset,
  }) = _StartupActiveTurnReadPage;
}

abstract interface class RuntimeStartupReadConnection {
  Future<RuntimeStartupReadHeader> header();
  Future<StartupActiveTurnReadPage> activeTurns({int offset = 0, int limit = 32});
  Future<TextChunk> text(int fieldId, {int offset = 0, int maxBytes = 65536});
  void requestClose();
  Future<FeedCloseReport> close();
  Future<FeedCloseReport> retryClose();
}
