import 'dart:async';

import '../../../anywork_client.dart';
import '../../../models.dart';
import '../anywork_client.dart';
import 'command_lane.dart';

final class BotThreadSyncProgress {
  const BotThreadSyncProgress({
    required this.operation,
    required this.request,
    this.reply,
    this.error,
    this.inFlight = false,
    this.superseded = false,
  });
  final OperationHandle operation;
  final ChangeBotThreadSyncRequest request;
  final ChangeBotThreadSyncReply? reply;
  final Object? error;
  final bool inFlight;
  final bool superseded;
  bool get unknown =>
      operation.state.value.failurePhase == OperationPhase.unknownOutcome;
}

/// Controls are independently admitted and joined, never held behind Enable's
/// effective barrier. The host's full CAS is the only write arbitration point.
final class BotThreadSyncCommands
    extends ReadModel<Map<String, BotThreadSyncProgress>> {
  BotThreadSyncCommands(this._client) : super(const {});
  final AnyworkClient _client;
  final CommandLane _work = CommandLane();
  final Set<_SyncAttempt> _attempts = {};
  bool _closed = false;

  BotThreadSyncProgress? forThread(String threadId) => state[threadId];

  /// Legacy upgrade is an explicit new-Thread command, never Resume/Enable or
  /// a mutation of the frozen old Thread snapshot.
  Future<BotConversationThreadReply> createUpgradedConversation(
    String threadId, {
    required BotSyncCas expected,
  }) {
    if (_closed || _client.isClosed)
      return Future.error(StateError('Sync commands closed'));
    final known = _client.session(threadId).state.audience.known;
    final binding = known?.binding;
    if (binding is! BotThreadBindingPositionCurrent ||
        binding.cas != expected ||
        binding.sync is! BotCurrentSyncRequiresUpgrade) {
      return Future.error(
        _failure(StudioFailureCode.staleRevision, 'Upgrade target changed'),
      );
    }
    final target = known!.target;
    final permit = _client.budget.acquire(
      ResourceKind.pendingOperation,
      owner: 'bot-upgrade:$threadId',
    );
    return _work.run(() async {
      try {
        final snapshot = await _client.transport.readBots();
        final bots = snapshot.bots.where((b) => b.id == target.botId);
        if (bots.isEmpty)
          throw _failure(
            StudioFailureCode.unavailable,
            'Bot configuration unavailable',
          );
        return await _client.botsCommands.createConversationThread(
          botId: target.botId,
          chatId: target.chatId,
          expectedConfigRevision: bots.single.configRevision,
          expectedBindingRevision: expected.bindingRevision,
        );
      } finally {
        permit.release();
      }
    });
  }

  Future<ChangeBotThreadSyncReply> change(
    String threadId,
    BotThreadSyncAction action,
  ) {
    if (_closed || _client.isClosed)
      return Future.error(StateError('Sync commands closed'));
    final audience = _client.session(threadId).state.audience;
    final cas = audience.writableCas;
    final target = audience.known?.target;
    if (cas == null || target == null)
      return Future.error(
        _failure(
          StudioFailureCode.permissionDenied,
          'The current binding cannot be controlled',
        ),
      );
    final sync =
        (audience.known!.binding as BotThreadBindingPositionCurrent).sync;
    final allowed = switch ((sync, action)) {
      (
        BotCurrentSyncActive(),
        BotThreadSyncAction.pause || BotThreadSyncAction.close,
      ) =>
        true,
      (
        BotCurrentSyncPaused(),
        BotThreadSyncAction.resume || BotThreadSyncAction.close,
      ) =>
        true,
      (BotCurrentSyncPendingStart(), BotThreadSyncAction.close) => true,
      (BotCurrentSyncClosed(), BotThreadSyncAction.enable) => true,
      _ => false,
    };
    if (!allowed)
      return Future.error(
        _failure(
          StudioFailureCode.invalidArgument,
          'Action is not valid for this sync state',
        ),
      );
    final previous = state[threadId];
    if (previous != null &&
        previous.request.expected == cas &&
        previous.request.action == action &&
        (previous.inFlight ||
            previous.unknown ||
            previous.operation.state.value.isPending)) {
      return Future.error(
        _failure(
          StudioFailureCode.busy,
          'This intent is already owned; reconcile its original operation',
        ),
      );
    }
    final operation = _client.mutations.begin(
      target: 'bot-thread-sync:$threadId',
    );
    final attempt = _SyncAttempt(
      operation,
      ChangeBotThreadSyncRequest(
        operationId: operation.id.value,
        threadId: threadId,
        expected: cas,
        action: action,
      ),
      target,
    );
    _attempts.add(attempt);
    try {
      attempt.permit = _client.budget.acquire(
        ResourceKind.observer,
        owner: 'bot-sync:${operation.id.value}',
      );
      final watched = _client
          .session(threadId)
          .source
          .watchLatest((_) => _confirm(attempt));
      attempt.observation = watched.observation;
    } catch (error) {
      operation.reject(error);
      _release(attempt);
      return Future.error(error);
    }
    return _run(attempt);
  }

  /// Explicit re-read of the same stable input after an unknown result. No new
  /// operation ID, CAS refresh, automatic replay or second intent is created.
  Future<ChangeBotThreadSyncReply> reconcile(String threadId) {
    final latest = state[threadId];
    final matches = _attempts.where((a) => a.operation == latest?.operation);
    if (_closed ||
        _client.isClosed ||
        matches.isEmpty ||
        latest?.inFlight == true) {
      return Future.error(StateError('No reconcilable sync operation'));
    }
    return _run(matches.single);
  }

  Future<ChangeBotThreadSyncReply> _run(_SyncAttempt attempt) => _work.run(
    () async {
      _publish(attempt, inFlight: true);
      try {
        final reply = await _client.transport.changeBotThreadSync(
          attempt.request,
        );
        _validate(attempt, reply);
        attempt.reply = reply;
        // Identity confirmation is stricter than a numerically covered resource
        // stamp. In particular gen1 revision 100 cannot cover gen2 revision 1.
        final receipt = reply.receipt;
        attempt.operation.accept(
          CommitReceipt(
            operationId: receipt.operationId,
            disposition: receipt.disposition,
            targets: receipt.targets,
            effect: receipt.effect,
            durable: receipt.durable,
            effective:
                receipt.effective &&
                reply.state is! BotThreadSyncCommandStatePendingStart,
            requiresIdentityObservation: true,
          ),
        );
        if (reply.state is BotThreadSyncCommandStateSuperseded)
          attempt.superseded = true;
        _confirm(attempt);
        _publish(attempt);
        return reply;
      } catch (error) {
        if (attempt.operation.state.value.receipt != null) {
          attempt.operation.syncFailed(error);
        } else if (_knownRejection(error)) {
          attempt.operation.reject(error);
          _release(attempt);
        } else {
          attempt.operation.unknownOutcome(error);
        }
        _publish(attempt, error: error);
        rethrow;
      }
    },
  );

  void _validate(_SyncAttempt attempt, ChangeBotThreadSyncReply reply) {
    final target = reply.audience.known?.target;
    final authorization = switch (reply.state) {
      BotThreadSyncCommandStatePendingStart(:final authorization) ||
      BotThreadSyncCommandStateSuperseded(
        :final authorization,
      ) => authorization,
      BotThreadSyncCommandStateSettled() =>
        reply.audience.queryAuthorization?.id,
    };
    if (reply.threadId != attempt.request.threadId ||
        reply.receipt.operationId != attempt.operation.id ||
        target == null ||
        target.botId != attempt.target.botId ||
        target.chatId != attempt.target.chatId ||
        authorization == null ||
        authorization.botId != target.botId ||
        authorization.chatId != target.chatId ||
        reply.receipt.targets.length != 1 ||
        reply.receipt.targets.single.resourceKey !=
            'bot-audience:${reply.threadId}:${authorization.generation}') {
      throw _failure(
        StudioFailureCode.protocol,
        'Sync receipt identity mismatch',
      );
    }
    attempt.authorization = authorization;
    final old = attempt.request.expected.authorizationHead;
    if (attempt.request.action == BotThreadSyncAction.enable &&
        old is BotAuthorizationHeadPresent &&
        authorization.generation <= old.authorization.id.generation) {
      throw _failure(
        StudioFailureCode.protocol,
        'Enable did not create a new authorization generation',
      );
    }
    if (attempt.request.action != BotThreadSyncAction.enable &&
        old is BotAuthorizationHeadPresent &&
        old.authorization.id != authorization) {
      throw _failure(
        StudioFailureCode.protocol,
        'Sync receipt changed authorization',
      );
    }
  }

  void _confirm(_SyncAttempt attempt) {
    if (_closed ||
        _client.isClosed ||
        attempt.reply == null ||
        attempt.authorization == null)
      return;
    final audience = _client.session(attempt.request.threadId).state.audience;
    final known = audience.known;
    if (known == null ||
        known.target.botId != attempt.target.botId ||
        known.target.chatId != attempt.target.chatId)
      return;
    final id = attempt.authorization!;
    final observed = audience.queryAuthorization;
    final closed = known.latestClosed?.authorization;
    final receipt = attempt.reply!.receipt;
    if (!_client.isCommandOwner(receipt.targets.single.ownerEpoch)) return;
    final same = observed?.id == id
        ? observed
        : closed?.id == id
        ? closed
        : null;
    final superseded =
        attempt.superseded ||
        known.binding is BotThreadBindingPositionReplaced ||
        (observed != null && observed.id.generation > id.generation);
    if (superseded) {
      attempt.superseded = true;
      attempt.operation.markObserved();
      _release(attempt);
      _publish(attempt);
      return;
    }
    if (same == null || same.revision < receipt.targets.single.revision) return;
    // The same owner epoch is essential; observeResource uses the bootstrap
    // command owner epoch, never the Thread stream's unrelated numeric epoch.
    _client.observeResource(
      'bot-audience:${attempt.request.threadId}:${id.generation}',
      same.revision,
    );
    if (!_client.isCommandOwner(receipt.targets.single.ownerEpoch)) return;
    attempt.operation.markObserved();
    final sync = switch (known.binding) {
      BotThreadBindingPositionCurrent(:final sync) => sync,
      BotThreadBindingPositionReplaced() => null,
    };
    final effective = switch ((attempt.request.action, sync)) {
      (
        BotThreadSyncAction.enable || BotThreadSyncAction.resume,
        BotCurrentSyncActive(),
      ) =>
        true,
      (BotThreadSyncAction.pause, BotCurrentSyncPaused()) => true,
      (BotThreadSyncAction.close, BotCurrentSyncClosed()) => true,
      _ => false,
    };
    if (effective) attempt.operation.markEffective();
    if (attempt.reply!.state is BotThreadSyncCommandStatePendingStart &&
        sync is BotCurrentSyncPendingStart) {
      // Durable prepare is observed but remains owned until effective/closed.
      _publish(attempt);
      return;
    }
    if (!effective) attempt.superseded = true;
    _release(attempt);
    _publish(attempt);
  }

  void _publish(_SyncAttempt attempt, {bool inFlight = false, Object? error}) {
    if (_closed || _client.isClosed) return;
    // Latest intent is not synonymous with latest response arrival.
    if (_client.mutations.latest(
          'bot-thread-sync:${attempt.request.threadId}',
        ) !=
        attempt.operation)
      return;
    final next = Map<String, BotThreadSyncProgress>.of(state);
    next.remove(attempt.request.threadId);
    next[attempt.request.threadId] = BotThreadSyncProgress(
      operation: attempt.operation,
      request: attempt.request,
      reply: attempt.reply,
      inFlight: inFlight,
      error: error,
      superseded: attempt.superseded,
    );
    while (next.length > 32) {
      next.remove(next.keys.first);
    }
    state = Map.unmodifiable(next);
  }

  void _release(_SyncAttempt attempt) {
    attempt.observation?.cancel();
    attempt.permit?.release();
    _attempts.remove(attempt);
  }

  Future<void> close() async {
    _closed = true;
    _work.seal();
    await _work.join();
    for (final attempt in List.of(_attempts)) {
      _release(attempt);
    }
  }
}

final class _SyncAttempt {
  _SyncAttempt(this.operation, this.request, this.target);
  final OperationHandle operation;
  final ChangeBotThreadSyncRequest request;
  final BotAudienceTarget target;
  Observation? observation;
  ResourcePermit? permit;
  ChangeBotThreadSyncReply? reply;
  BotAuthorizationId? authorization;
  bool superseded = false;
}

StudioFailure _failure(StudioFailureCode code, String message) => StudioFailure(
  code: code,
  message: message,
  retryable: false,
  correlationId: 'client-bot-sync',
);
bool _knownRejection(Object error) =>
    error is StudioFailure &&
    switch (error.code) {
      StudioFailureCode.invalidArgument ||
      StudioFailureCode.permissionDenied ||
      StudioFailureCode.conflict ||
      StudioFailureCode.staleRevision ||
      StudioFailureCode.busy ||
      StudioFailureCode.notFound ||
      StudioFailureCode.overloaded ||
      StudioFailureCode.notInitialized => true,
      _ => false,
    };
