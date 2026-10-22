import 'dart:async';

import '../../../anywork_client.dart'
    show
        Observation,
        OperationHandle,
        OperationState,
        ResourceKind,
        ResourcePermit;
import '../../../models.dart';
import '../../../studio_ports.dart';
import '../anywork_client.dart';
import 'command_lane.dart';

class BotsCommands {
  BotsCommands(this._client);
  final AnyworkClient _client;
  final CommandLane _lane = CommandLane();
  final Map<OperationId, Observation> _confirmations = {};
  BotSetupDraft _setupDraft = const BotSetupDraft();
  String? _secretBuffer;
  final Map<(String, String), _BotMessageDraft> _messageDrafts = {};

  String messageDraft(String botId, String chatId) =>
      _messageDrafts[(botId, chatId)]?.text ?? '';

  void updateMessageDraft(String botId, String chatId, String text) {
    if (_client.isClosed) throw StateError('Client is closed');
    final key = (botId, chatId);
    if (text.isEmpty) {
      _messageDrafts.remove(key)?.permit.release();
      return;
    }
    final draft = _messageDrafts.putIfAbsent(
      key,
      () => _BotMessageDraft(
        _client.budget.acquire(
          ResourceKind.draft,
          owner: 'bot-message:$botId:$chatId',
        ),
      ),
    );
    draft.text = text;
  }

  BotSetupDraft get setupDraft => _setupDraft;

  void updateSetupDraft(BotSetupDraft draft) {
    _setupDraft = draft;
  }

  /// Secret 只停留在瞬时内存，不进入普通草稿。
  void holdSecret(String? value) {
    _secretBuffer = value == null || value.isEmpty ? null : value;
  }

  void clearSecret() {
    _secretBuffer = null;
  }

  BotSecretUpdate consumeSecretUpdate({required bool clear}) {
    if (clear) {
      _secretBuffer = null;
      return const BotSecretClear();
    }
    final value = _secretBuffer;
    _secretBuffer = null;
    if (value == null) return const BotSecretPreserve();
    return BotSecretReplace(value);
  }

  Future<BotsStateSnapshot> saveBot({
    String? botId,
    required int expectedConfigRevision,
    required String name,
    required String projectId,
    required String appId,
    required BotSecretUpdate secret,
    bool enabled = false,
    bool toolsEnabled = false,
  }) {
    clearSecret();
    return _mutate(
      botId == null ? 'save-new' : 'save:$botId',
      (operationId) => _api.saveBot(
        SaveBotRequest(
          operationId: operationId,
          botId: botId,
          expectedConfigRevision: expectedConfigRevision,
          name: name,
          projectId: projectId,
          appId: appId,
          secret: secret,
          enabled: enabled,
          toolsEnabled: toolsEnabled,
        ),
      ),
    );
  }

  Future<BotsStateSnapshot> startRegistration({
    required String name,
    required String projectId,
  }) {
    return _mutate(
      'register',
      (operationId) => _api.startBotRegistration(
        StartBotRegistrationRequest(
          operationId: operationId,
          name: name,
          projectId: projectId,
        ),
      ),
    );
  }

  Future<BotsStateSnapshot> cancelRegistration({required String attemptId}) {
    return _mutate(
      'register-cancel:$attemptId',
      (operationId) => _api.cancelBotRegistration(
        CancelBotRegistrationRequest(
          operationId: operationId,
          attemptId: attemptId,
        ),
      ),
    );
  }

  Future<BotsStateSnapshot> setEnabled({
    required String botId,
    required int expectedConfigRevision,
    required bool enabled,
  }) {
    return _mutate(
      'enabled:$botId',
      (operationId) => _api.setBotEnabled(
        SetBotEnabledRequest(
          operationId: operationId,
          botId: botId,
          expectedConfigRevision: expectedConfigRevision,
          enabled: enabled,
        ),
      ),
    );
  }

  Future<BotsStateSnapshot> retryConnection({required String botId}) {
    return _mutate(
      'retry:$botId',
      (operationId) => _api.retryBotConnection(
        RetryBotConnectionRequest(operationId: operationId, botId: botId),
      ),
    );
  }

  Future<BotsStateSnapshot> setTrustedUser({
    required String botId,
    required int expectedConfigRevision,
    required String openId,
    required bool trusted,
  }) {
    return _mutate(
      'trusted-user:$botId:$openId',
      (operationId) => _api.setBotTrustedUser(
        SetBotTrustedUserRequest(
          operationId: operationId,
          botId: botId,
          expectedConfigRevision: expectedConfigRevision,
          openId: openId,
          trusted: trusted,
        ),
      ),
    );
  }

  Future<BotsStateSnapshot> setTrustedChat({
    required String botId,
    required int expectedConfigRevision,
    required String chatId,
    required bool trusted,
  }) {
    return _mutate(
      'trusted-chat:$botId:$chatId',
      (operationId) => _api.setBotTrustedChat(
        SetBotTrustedChatRequest(
          operationId: operationId,
          botId: botId,
          expectedConfigRevision: expectedConfigRevision,
          chatId: chatId,
          trusted: trusted,
        ),
      ),
    );
  }

  Future<BotConversationThreadReply> createConversationThread({
    required String botId,
    required String chatId,
    required int expectedConfigRevision,
    required int expectedBindingRevision,
  }) {
    if (_client.isClosed) return Future.error(StateError('Client is closed'));
    final frozenBotId = botId;
    final frozenChatId = chatId;
    final frozenConfigRevision = expectedConfigRevision;
    final frozenBindingRevision = expectedBindingRevision;
    final operation = _client.mutations.begin(
      target: 'bots:thread:$frozenBotId:$frozenChatId',
    );
    return _lane.enqueue(() async {
      try {
        final reply = await _api.createBotConversationThread(
          CreateBotConversationThreadRequest(
            operationId: operation.id.value,
            botId: frozenBotId,
            chatId: frozenChatId,
            expectedConfigRevision: frozenConfigRevision,
            expectedBindingRevision: frozenBindingRevision,
          ),
        );
        if (reply.binding.botId != frozenBotId ||
            reply.binding.chatId != frozenChatId) {
          throw const StudioFailure(
            code: StudioFailureCode.protocol,
            message: 'Thread binding response belongs to another conversation',
            retryable: false,
            correlationId: 'client-bots-binding',
          );
        }
        _client.botsQueries.applyBinding(reply.binding);
        operation.accept(reply.receipt.toCommitReceipt());
        for (final stamp in reply.receipt.targets) {
          if (stamp.resourceKey == 'bot:$frozenBotId:chat:$frozenChatId' &&
              stamp.revision <= reply.binding.revision) {
            _client.mutations.observe(stamp);
          }
        }
        _confirm(operation);
        return reply;
      } catch (error) {
        _fail(operation, error);
        rethrow;
      }
    });
  }

  /// 首次 await 前冻结 bot/chat/text/operation。未知结果不得由 Widget 重建自动重发。
  Future<BotSendResult> sendMessage({
    required String botId,
    required String chatId,
    required String text,
  }) {
    if (_client.isClosed) return Future.error(StateError('Client is closed'));
    final frozenBotId = botId;
    final frozenChatId = chatId;
    final frozenText = text;
    final operation = _client.mutations.begin(
      target: 'bots:send:$frozenBotId:$frozenChatId',
    );
    final frozenOperationId = operation.id;
    return _lane.enqueue(() async {
      try {
        final result = await _api.sendBotMessage(
          SendBotMessageRequest(
            operationId: frozenOperationId.value,
            botId: frozenBotId,
            chatId: frozenChatId,
            text: frozenText,
          ),
        );
        operation.accept(result.receipt.toCommitReceipt());
        if (!_client.isClosed) _client.botsSends.record(result);
        if (result.status == BotSendStatus.unknown ||
            result.status == BotSendStatus.partial) {
          operation.unknownOutcome(
            StudioFailure(
              code: StudioFailureCode.unavailable,
              message: 'Bot send finished with ${result.status.name}',
              retryable: false,
              correlationId: frozenOperationId.value,
            ),
          );
        }
        return result;
      } catch (error) {
        _fail(operation, error);
        rethrow;
      }
    });
  }

  Future<BotsStateSnapshot> _mutate(
    String key,
    Future<BotsCommandReply> Function(String operationId) request,
  ) {
    if (_client.isClosed) return Future.error(StateError('Client is closed'));
    final operation = _client.mutations.begin(target: 'bots:$key');
    return _lane.enqueue(() async {
      try {
        final reply = await request(operation.id.value);
        if (!_client.isClosed) {
          _client.bots.apply(reply.snapshot);
          final stamp = reply.stamp;
          if (stamp != null &&
              stamp.resourceKey == 'bots' &&
              stamp.revision == reply.snapshot.revision) {
            _client.mutations.observe(stamp);
          }
        }
        operation.accept(reply.receipt.toCommitReceipt());
        _confirm(operation);
        return reply.snapshot;
      } catch (error) {
        _fail(operation, error);
        rethrow;
      }
    });
  }

  void _fail(OperationHandle operation, Object error) {
    if (operation.state.value.receipt != null) {
      operation.syncFailed(error);
    } else if (_knownBotRejection(error)) {
      operation.reject(error);
    } else {
      operation.unknownOutcome(error);
    }
  }

  void _confirm(OperationHandle operation) {
    if (_client.isClosed) return;
    void settle(OperationState result) {
      if (!result.observed && result.failurePhase == null) return;
      _confirmations.remove(operation.id)?.cancel();
    }

    if (operation.state.value.observed) {
      settle(operation.state.value);
      return;
    }
    final watched = operation.state.watchLatest(settle);
    _confirmations[operation.id] = watched.observation;
    settle(watched.value);
  }

  void closeObservations() {
    for (final observation in _confirmations.values) {
      observation.cancel();
    }
    _confirmations.clear();
    clearSecret();
  }

  Future<void> close() {
    _lane.seal();
    clearSecret();
    for (final draft in _messageDrafts.values) {
      draft.permit.release();
    }
    _messageDrafts.clear();
    return _lane.join();
  }

  StudioTransport get _api => _client.transport;
}

class _BotMessageDraft {
  _BotMessageDraft(this.permit);
  final ResourcePermit permit;
  String text = '';
}

bool _knownBotRejection(Object error) =>
    error is StudioFailure &&
    switch (error.code) {
      StudioFailureCode.invalidArgument ||
      StudioFailureCode.notFound ||
      StudioFailureCode.busy ||
      StudioFailureCode.conflict ||
      StudioFailureCode.staleRevision ||
      StudioFailureCode.permissionDenied ||
      StudioFailureCode.overloaded ||
      StudioFailureCode.notInitialized => true,
      _ => false,
    };
