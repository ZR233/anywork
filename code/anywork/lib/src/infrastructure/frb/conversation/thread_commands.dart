part of 'command_port.dart';

mixin _ThreadCommands implements ConversationCommandPort {
  // A successful but unusable DTO belongs to its original typed failure. This
  // retains evidence only, never a native resource or a second transport path.
  final _unusableThreadReplies = Expando<_UnusableThreadReply>(
    'native-thread-command-evidence',
  );
  final _threadFailures = Expando<({Object cause, StackTrace stack})>(
    'native-thread-command-failures',
  );

  @override
  Future<void> compactThread(
    String threadId, {
    required OperationId operationId,
  }) async {
    try {
      // operationId is local association only: this native API accepts no ID.
      await threads.compactThread(threadId: threadId);
    } on Object catch (error, stack) {
      final failure = _threadCommandFailure(error);
      _threadFailures[failure] = (cause: error, stack: stack);
      Error.throwWithStackTrace(
        CommandDispatchFailure.unknownOutcome(failure: failure),
        stack,
      );
    }
  }

  @override
  Future<StopExecutionReply> stopExecution(
    String threadId,
    String executionId, {
    required OperationId operationId,
  }) => _threadCommand<command.BridgeStopThreadReply, StopExecutionReply>(
    operationId: operationId,
    invoke: () => queries.stopThread(
      operationId: operationId.value,
      threadId: threadId,
      expectedExecutionId: executionId,
    ),
    receipt: (reply) => reply.receipt,
    convert: (reply, receipt) {
      if (reply.threadId != threadId || reply.executionId != executionId) {
        throw adapterProtocol('stop-reply-target');
      }
      return StopExecutionReply(
        threadId: reply.threadId,
        executionId: reply.executionId,
        stopped: reply.stopped,
        receipt: receipt,
      );
    },
    retain: (reply, error, stack) => _UnusableStopReply(reply, error, stack),
  );

  @override
  Future<ContinueThreadReply> continueThread(
    String threadId, {
    required OperationId operationId,
    required String expectedContinuationId,
    required int expectedModelRouteRevision,
  }) {
    final BigInt routeRevision;
    try {
      routeRevision = nativeU64(
        expectedModelRouteRevision,
        'expected continuation model route revision',
      );
    } on Object catch (error) {
      throw CommandDispatchFailure.rejected(
        failure: _threadCommandFailure(error),
      );
    }
    return _threadCommand<
      command.BridgeContinueThreadReply,
      ContinueThreadReply
    >(
      operationId: operationId,
      invoke: () => queries.continueThread(
        operationId: operationId.value,
        threadId: threadId,
        expectedContinuationId: expectedContinuationId,
        expectedModelRouteRevision: routeRevision,
      ),
      receipt: (reply) => reply.receipt,
      convert: (reply, receipt) {
        if (reply.threadId != threadId ||
            reply.inputId != operationId.value ||
            reply.continuationId != expectedContinuationId) {
          throw adapterProtocol('continue-reply-target');
        }
        return ContinueThreadReply(
          threadId: reply.threadId,
          inputId: reply.inputId,
          continuationId: reply.continuationId,
          cursor: exactU64(reply.cursor, 'continuation accepted sequence'),
          receipt: receipt,
        );
      },
      retain: (reply, error, stack) =>
          _UnusableContinueReply(reply, error, stack),
      confirmsAcceptance: (failure) => switch (failure.details) {
        ControlFailureDetails(
          facts: ContinuationAcceptedControlFailureFacts(
            threadId: final acceptedThreadId,
            operationId: final acceptedOperationId,
            accepted: true,
          ),
        ) =>
          acceptedThreadId == threadId &&
              acceptedOperationId == operationId.value,
        _ => false,
      },
    );
  }

  @override
  Future<ContinuationOperationView?> readContinuationOperation(
    String threadId,
    OperationId operationId,
  ) => bridgeQuery(() async {
    final command.BridgeContinuationOperationView view;
    try {
      view = await queries.readContinuationOperation(
        threadId: threadId,
        operationId: operationId.value,
      );
    } on errors.BridgeError catch (error) {
      // Native uses this exact typed absence instead of an optional DTO.
      // Other NotFound errors, identities and unreadable accepted rows stay errors.
      if (error.code == errors.BridgeErrorCode.notFound) {
        if (error.details case errors.BridgeErrorDetails_Control(
          reason: 'continuationUnavailable',
          facts: errors.BridgeControlFailureFacts_ContinuationOperation(
            threadId: final missingThreadId,
            operationId: final missingOperationId,
          ),
        )) {
          if (missingThreadId == threadId &&
              missingOperationId == operationId.value) {
            return null;
          }
        }
      }
      rethrow;
    }
    final receipt = commitReceiptFromBridge(view.receipt);
    if (view.threadId != threadId ||
        view.operationId != operationId.value ||
        receipt.operationId != operationId) {
      throw adapterProtocol('continuation-operation-target');
    }
    return ContinuationOperationView(
      threadId: view.threadId,
      operationId: OperationId(view.operationId),
      inputId: view.inputId,
      continuationId: view.continuationId,
      acceptedSequence: exactU64(
        view.acceptedSequence,
        'continuation operation accepted sequence',
      ),
      state: switch (view.state) {
        command.BridgeContinuationOperationState_Pending() =>
          const ContinuationOperationState.pending(),
        command.BridgeContinuationOperationState_Consumed(:final turnId) =>
          ContinuationOperationState.consumed(turnId: turnId),
        command.BridgeContinuationOperationState_Discarded() =>
          const ContinuationOperationState.discarded(),
      },
      durable: view.durable,
      receipt: receipt,
    );
  });

  @override
  Future<CommitReceipt> setThreadMode(
    String threadId,
    String mode, {
    required OperationId operationId,
  }) => _threadCommand<command.BridgeThreadModeCommandReply, CommitReceipt>(
    operationId: operationId,
    invoke: () => threads.setThreadMode(
      operationId: operationId.value,
      threadId: threadId,
      mode: mode,
    ),
    receipt: (reply) => reply.receipt,
    convert: (_, receipt) => receipt,
    retain: (reply, error, stack) => _UnusableModeReply(reply, error, stack),
  );

  @override
  Future<ThreadModelRouteCommandReply> setThreadModelRoute(
    String threadId, {
    required OperationId operationId,
    required String accountId,
    required String modelId,
    required String? effort,
    required int expectedModelRouteRevision,
    required int expectedSettingsRevision,
  }) {
    final BigInt routeRevision;
    final BigInt settingsRevision;
    try {
      routeRevision = nativeU64(
        expectedModelRouteRevision,
        'expected model route revision',
      );
      settingsRevision = nativeU64(
        expectedSettingsRevision,
        'expected settings revision',
      );
    } on Object catch (error) {
      throw CommandDispatchFailure.rejected(
        failure: _threadCommandFailure(error),
      );
    }
    return _threadCommand<
      command.BridgeThreadModelRouteCommandReply,
      ThreadModelRouteCommandReply
    >(
      operationId: operationId,
      invoke: () => threads.setThreadModelRoute(
        operationId: operationId.value,
        threadId: threadId,
        accountId: accountId,
        modelId: modelId,
        effort: effort,
        expectedModelRouteRevision: routeRevision,
        expectedSettingsRevision: settingsRevision,
      ),
      receipt: (reply) => reply.receipt,
      convert: (reply, receipt) {
        if (reply.runtime.threadId != threadId) {
          throw adapterProtocol('route-reply-Thread');
        }
        return ThreadModelRouteCommandReply(
          runtime: commandRuntimeFromBridge(reply.runtime),
          settings: commandSettingsFromBridge(reply.settings),
          modeDefaultSaved: reply.modeDefaultSaved,
          warning: reply.warning,
          receipt: receipt,
        );
      },
      retain: (reply, error, stack) => _UnusableRouteReply(reply, error, stack),
      rejectsStaleRevision: true,
    );
  }

  @override
  Future<InteractionCommandReply> respondInteraction(
    String hostThreadId,
    String interactionId, {
    required OperationId operationId,
    required int expectedInteractionRevision,
    required InteractionResolutionCommand resolution,
  }) {
    final BigInt revision;
    final nativeResolution = _prepareResolution(
      resolution,
      expectedInteractionRevision,
    );
    revision = nativeResolution.revision;
    return _threadCommand<
      command.BridgeInteractionCommandReply,
      InteractionCommandReply
    >(
      operationId: operationId,
      invoke: () => queries.respondInteraction(
        operationId: operationId.value,
        hostThreadId: hostThreadId,
        expectedRevision: revision,
        interactionId: interactionId,
        resolution: nativeResolution.resolution,
      ),
      receipt: (reply) => reply.receipt,
      convert: (reply, receipt) {
        if (reply.interaction.interactionId != interactionId) {
          throw adapterProtocol('interaction-reply-target');
        }
        // scope.threadId is the actual target, possibly a direct child. The
        // SDK validates it against its frozen read; host is not the target.
        return InteractionCommandReply(
          interaction: commandInteractionFromBridge(reply.interaction),
          receipt: receipt,
        );
      },
      retain: (reply, error, stack) =>
          _UnusableInteractionReply(reply, error, stack),
      rejectsStaleRevision: true,
    );
  }

  Future<R> _threadCommand<N, R>({
    required OperationId operationId,
    required Future<N> Function() invoke,
    required command.BridgeStudioCommandReceipt Function(N) receipt,
    required R Function(N, CommitReceipt) convert,
    required _UnusableThreadReply Function(N, Object, StackTrace) retain,
    bool rejectsStaleRevision = false,
    bool Function(StudioFailure)? confirmsAcceptance,
  }) async {
    final N reply;
    try {
      reply = await invoke();
    } on Object catch (error, stack) {
      final failure = _threadCommandFailure(error);
      _threadFailures[failure] = (cause: error, stack: stack);
      final confirmed =
          error is errors.BridgeError &&
          confirmsAcceptance?.call(failure) == true;
      if (confirmed) {
        // Control acceptance has no receipt on this error path. Only the SDK's
        // original operation query may recover one; never manufacture it here.
        Error.throwWithStackTrace(
          CommandDispatchFailure.confirmedWithoutUsableReceipt(
            failure: failure,
          ),
          stack,
        );
      }
      // These two native CAS checks reject before mutation. Other typed codes,
      // including generic Conflict, do not establish that dispatch was rejected.
      // Interaction's typed StaleRevision intentionally has no revision-detail
      // payload. Do not require optional details to recognize that real CAS
      // rejection, or infer rejection from an arbitrary transport exception.
      final rejected =
          rejectsStaleRevision &&
          error is errors.BridgeError &&
          error.code == errors.BridgeErrorCode.staleRevision;
      Error.throwWithStackTrace(
        rejected
            ? CommandDispatchFailure.rejected(failure: failure)
            : CommandDispatchFailure.unknownOutcome(failure: failure),
        stack,
      );
    }
    CommitReceipt? mapped;
    try {
      mapped = commitReceiptFromBridge(receipt(reply));
      if (mapped.operationId != operationId) {
        throw adapterProtocol('thread-command-operation');
      }
      return convert(reply, mapped);
    } on Object catch (error, stack) {
      final failure = _threadCommandFailure(error);
      _unusableThreadReplies[failure] = retain(reply, error, stack);
      Error.throwWithStackTrace(
        mapped != null && mapped.operationId == operationId
            ? CommandDispatchFailure.committedButUnobserved(
                receipt: mapped,
                failure: failure,
              )
            : CommandDispatchFailure.confirmedWithoutUsableReceipt(
                failure: failure,
              ),
        stack,
      );
    }
  }
}

// Kept typed even before invoking native. No JSON/dynamic request is admitted.
({BigInt revision, stream.BridgeInteractionResolution resolution})
_prepareResolution(
  InteractionResolutionCommand resolution,
  int expectedRevision,
) {
  try {
    return (
      revision: nativeU64(expectedRevision, 'expected interaction revision'),
      resolution: interactionResolutionToBridge(resolution),
    );
  } on Object catch (error) {
    throw CommandDispatchFailure.rejected(
      failure: _threadCommandFailure(error),
    );
  }
}

StudioFailure _threadCommandFailure(Object error) {
  try {
    return bridgeFailure(error);
  } on Object catch (mappingError) {
    return adapterFailure(
      mappingError,
      operation: 'thread-command-error-conversion',
    );
  }
}

sealed class _UnusableThreadReply {
  _UnusableThreadReply(this.cause, this.stack);
  final Object cause;
  final StackTrace stack;
}

final class _UnusableModeReply extends _UnusableThreadReply {
  _UnusableModeReply(this.reply, super.cause, super.stack);
  final command.BridgeThreadModeCommandReply reply;
}

final class _UnusableStopReply extends _UnusableThreadReply {
  _UnusableStopReply(this.reply, super.cause, super.stack);
  final command.BridgeStopThreadReply reply;
}

final class _UnusableContinueReply extends _UnusableThreadReply {
  _UnusableContinueReply(this.reply, super.cause, super.stack);
  final command.BridgeContinueThreadReply reply;
}

final class _UnusableRouteReply extends _UnusableThreadReply {
  _UnusableRouteReply(this.reply, super.cause, super.stack);
  final command.BridgeThreadModelRouteCommandReply reply;
}

final class _UnusableInteractionReply extends _UnusableThreadReply {
  _UnusableInteractionReply(this.reply, super.cause, super.stack);
  final command.BridgeInteractionCommandReply reply;
}
