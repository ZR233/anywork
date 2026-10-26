import 'package:anywork_client/workspace_ports.dart';

import '../../../../rust/api/studio/products/feed/startup_transport.dart'
    as progress;
import '../../../../rust/api/studio/products/read/startup.dart' as native;
import '../../../../rust/api/studio/types/runtime.dart' as runtime;
import '../../shared/bridge_failure.dart';
import '../../shared/exact_numbers.dart';
import '../../shared/read_converters.dart';
import '../source_converters.dart';

native.BridgeRuntimeStartupReadRef startupReadRefToBridge(
  RuntimeStartupReadRef value,
) => native.BridgeRuntimeStartupReadRef(
  entry: nativeU64(value.entry, 'startup read entry'),
  revision: nativeU64(value.revision, 'startup read revision'),
);

RuntimeStartupReadRef startupReadRefFromBridge(
  native.BridgeRuntimeStartupReadRef value,
) => RuntimeStartupReadRef(
  entry: exactU64(value.entry, 'startup read entry'),
  revision: exactU64(value.revision, 'startup read revision'),
);

RuntimeReady runtimeReadyFromBridge(native.BridgeRuntimeReady value) =>
    RuntimeReady(
      revision: exactU64(value.revision, 'runtime ready revision'),
      readyAt: exactI64(
        BigInt.from(value.readyAt),
        'runtime ready Unix seconds',
      ),
      details: startupReadRefFromBridge(value.details),
    );

StartupProgressFrame startupProgressFromBridge(
  progress.BridgeStartupProgressFrame value,
) => switch (value) {
  progress.BridgeStartupProgressFrame_Data(
    :final deliverySequence,
    :final stage,
  ) =>
    StartupProgressFrame.data(
      deliverySequence: exactU64(deliverySequence, 'startup delivery sequence'),
      stage: switch (stage) {
        runtime.BridgeStartupStage.preparing => StartupStage.preparing,
        runtime.BridgeStartupStage.waitingForSteps =>
          StartupStage.waitingForSteps,
        runtime.BridgeStartupStage.closingResources =>
          StartupStage.closingResources,
        runtime.BridgeStartupStage.backingUp => StartupStage.backingUp,
        runtime.BridgeStartupStage.resetting => StartupStage.resetting,
        runtime.BridgeStartupStage.startingServices =>
          StartupStage.startingServices,
        runtime.BridgeStartupStage.openingStorage =>
          StartupStage.openingStorage,
        runtime.BridgeStartupStage.loadingConfiguration =>
          StartupStage.loadingConfiguration,
        runtime.BridgeStartupStage.readingProjects =>
          StartupStage.readingProjects,
        runtime.BridgeStartupStage.preparingResources =>
          StartupStage.preparingResources,
        runtime.BridgeStartupStage.ready => StartupStage.ready,
        runtime.BridgeStartupStage.failed => StartupStage.failed,
      },
    ),
  progress.BridgeStartupProgressFrame_Failure(:final error) =>
    StartupProgressFrame.failure(error: bridgeFailure(error)),
  progress.BridgeStartupProgressFrame_Closed(:final reason) =>
    StartupProgressFrame.closed(
      reason: switch (reason) {
        progress.BridgeStartupCloseReason.requested =>
          StartupCloseReason.requested,
        progress.BridgeStartupCloseReason.attemptReplaced =>
          StartupCloseReason.attemptReplaced,
        progress.BridgeStartupCloseReason.completed =>
          StartupCloseReason.completed,
        progress.BridgeStartupCloseReason.runtimeStopped =>
          StartupCloseReason.runtimeStopped,
      },
    ),
};

RuntimeStartupReadHeader startupHeaderFromBridge(
  native.BridgeRuntimeStartupReadHeader value,
) => RuntimeStartupReadHeader(
  scope: RuntimeStartupScopeIdentity(
    scopeId: value.scope.scopeId,
    ownerEpoch: value.scope.ownerEpoch,
    attemptId: exactU64(value.scope.attemptId, 'startup scope attempt'),
    revision: exactU64(value.scope.revision, 'startup scope revision'),
  ),
  reference: startupReadRefFromBridge(value.reference),
  revision: exactU64(value.revision, 'startup header revision'),
  state: switch (value.state) {
    native.BridgeRuntimeStateRead_Uninitialized(:final at) =>
      RuntimeStateRead.uninitialized(
        at: exactI64(BigInt.from(at), 'runtime Unix seconds'),
      ),
    native.BridgeRuntimeStateRead_Initializing(:final at) =>
      RuntimeStateRead.initializing(
        at: exactI64(BigInt.from(at), 'runtime Unix seconds'),
      ),
    native.BridgeRuntimeStateRead_Ready(:final at) => RuntimeStateRead.ready(
      at: exactI64(BigInt.from(at), 'runtime Unix seconds'),
    ),
    native.BridgeRuntimeStateRead_ShuttingDown(:final at) =>
      RuntimeStateRead.shuttingDown(
        at: exactI64(BigInt.from(at), 'runtime Unix seconds'),
      ),
    native.BridgeRuntimeStateRead_Stopped(:final at) =>
      RuntimeStateRead.stopped(
        at: exactI64(BigInt.from(at), 'runtime Unix seconds'),
      ),
    native.BridgeRuntimeStateRead_Failed(:final failedAt, :final error) =>
      RuntimeStateRead.failed(
        failedAt: exactI64(
          BigInt.from(failedAt),
          'runtime failed Unix seconds',
        ),
        error: sourceErrorReadFromBridge(error),
      ),
  },
  startupRecovery: value.startupRecovery == null
      ? null
      : StartupRecoveryRead(
          backupPath: readTextFromBridge(value.startupRecovery!.backupPath),
          reason: readTextFromBridge(value.startupRecovery!.reason),
          createdAt: exactI64(
            BigInt.from(value.startupRecovery!.createdAt),
            'startup recovery Unix seconds',
          ),
        ),
  activeTurnCount: exactU64(value.activeTurnCount, 'startup active turn count'),
);

StartupActiveTurnReadPage startupActiveTurnsFromBridge(
  native.BridgeStartupActiveTurnReadPage value,
) => StartupActiveTurnReadPage(
  offset: exactU64(value.offset, 'startup active turn offset'),
  total: exactU64(value.total, 'startup active turn total'),
  items: List.unmodifiable([
    for (final item in value.items)
      StartupActiveTurnRead(
        threadId: readTextFromBridge(item.threadId),
        turnId: readTextFromBridge(item.turnId),
      ),
  ]),
  nextOffset: nullableU64(value.nextOffset, 'startup active turn next offset'),
);
