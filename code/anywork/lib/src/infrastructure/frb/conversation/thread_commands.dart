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
    String threadId,
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
        interactionId: interactionId,
        expectedInteractionRevision: revision,
        resolution: nativeResolution.resolution,
      ),
      receipt: (reply) => reply.receipt,
      convert: (reply, receipt) {
        if (reply.interaction.interactionId != interactionId ||
            reply.interaction.scope.threadId != threadId) {
          throw adapterProtocol('interaction-reply-target');
        }
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
  }) async {
    final N reply;
    try {
      reply = await invoke();
    } on Object catch (error, stack) {
      final failure = _threadCommandFailure(error);
      _threadFailures[failure] = (cause: error, stack: stack);
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

final class _UnusableRouteReply extends _UnusableThreadReply {
  _UnusableRouteReply(this.reply, super.cause, super.stack);
  final command.BridgeThreadModelRouteCommandReply reply;
}

final class _UnusableInteractionReply extends _UnusableThreadReply {
  _UnusableInteractionReply(this.reply, super.cause, super.stack);
  final command.BridgeInteractionCommandReply reply;
}
