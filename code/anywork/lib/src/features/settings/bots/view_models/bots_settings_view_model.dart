import 'dart:async';

import 'package:anywork_client/bots.dart';
import 'package:anywork_client/operations.dart';
import 'package:anywork_client/resources.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../../app/app_bindings.dart';
import '../../state/settings_action.dart';
import '../../state/settings_navigation_state.dart';
import '../../view_models/read_values.dart';
import '../../view_models/settings_navigation_view_model.dart';
import '../../view_models/settings_tab_lifecycle.dart';
import '../../view_models/visible_read_demand.dart';
import '../state/bots_settings_view_state.dart';

part 'bots_settings_view_model.g.dart';

@riverpod
class BotsSettingsViewModel extends _$BotsSettingsViewModel {
  late BotsRepository _repository;
  final _observations = <Observation>[];
  VisibleReadDemand<(ProductReadOrigin, ProductSourceStatusRef)>? _status;
  bool _alive = false;
  bool _visible = false;
  bool _bootstrapAttempted = false;
  int _lifetime = 0;
  int _visibility = 0;
  int _messageRead = 0;
  int _intent = 0;

  @override
  Future<BotsSettingsViewState> build() async {
    _alive = true;
    _bootstrapAttempted = false;
    final lifetime = ++_lifetime;
    _repository = ref.watch(botsRepositoryProvider);
    final tab = ref
        .read(settingsNavigationViewModelProvider.notifier)
        .register(
          SettingsTab.bots,
          SettingsTabLifecycle(visibility: setVisible),
        );
    _visible = tab.visible;
    ref.onDispose(() {
      _alive = false;
      _lifetime++;
      tab.unregister();
      _detach();
      // Accepted tickets and message drafts still belong to the Repository.
    });
    unawaited(
      Future<void>(() {
        if (_owns(lifetime) && _visible) _attach();
      }),
    );
    return _adopt(
      BotsSettingsViewState(
        source: _repository.state.value,
        messages: _repository.messages.value,
        sends: _repository.sends.value,
        visible: _visible,
      ),
    );
  }

  bool _owns(int lifetime) =>
      _alive && lifetime == _lifetime && state.asData != null;

  BotsSettingsViewState _adopt(BotsSettingsViewState value) {
    final bots = value.bots;
    final selected = bots?.any((bot) => bot.id == value.selectedBotId) == true
        ? value.selectedBotId
        : bots?.firstOrNull?.id;
    final target = selected == null || value.chatId.trim().isEmpty
        ? null
        : (botId: selected, chatId: value.chatId.trim());
    return value.copyWith(
      selectedBotId: selected,
      draftIssue: selected == value.selectedBotId ? value.draftIssue : null,
      messageDraft: value.draftIssue != null && selected == value.selectedBotId
          ? value.messageDraft
          : target == null
          ? ''
          : _repository.messageDraft(target.botId, target.chatId),
    );
  }

  void setVisible(bool visible) {
    if (!_alive || _visible == visible) return;
    _visible = visible;
    if (state.asData == null) return;
    if (visible) {
      _attach();
    } else {
      _detach();
      state = AsyncData(
        state.requireValue.copyWith(
          visible: false,
          readingStatus: false,
          readingMessages: false,
        ),
      );
    }
  }

  void _detach() {
    _visibility++;
    _messageRead++;
    for (final observation in _observations) {
      observation.cancel();
    }
    _observations.clear();
    _status?.dispose();
    _status = null;
  }

  void _attach() {
    if (!_alive ||
        !_visible ||
        state.asData == null ||
        _observations.isNotEmpty) {
      return;
    }
    final lifetime = _lifetime;
    final visibility = ++_visibility;
    bool owns() => _owns(lifetime) && _visible && visibility == _visibility;
    try {
      _status = VisibleReadDemand(
        read: (target) async {
          if (!owns()) return;
          final source = _repository.state.value;
          if (source.projection.stamp?.origin == target.$1 &&
              source.projection.header?.source.status == target.$2) {
            await _repository.loadSourceStatus();
          }
        },
        changed: (target, error, current) {
          if (!owns()) return;
          state = AsyncData(
            state.requireValue.copyWith(
              readingStatus: _status?.reading ?? false,
              statusIssue: current ? error : state.requireValue.statusIssue,
            ),
          );
        },
      );
      _observations.add(
        _repository.state.watchLatest((source) {
          if (!owns()) return;
          state = AsyncData(
            _adopt(state.requireValue.copyWith(source: source)),
          );
          _refreshStatus();
        }).observation,
      );
      _observations.add(
        _repository.messages.watchLatest((messages) {
          if (owns()) {
            state = AsyncData(state.requireValue.copyWith(messages: messages));
          }
        }).observation,
      );
      _observations.add(
        _repository.sends.watchLatest((sends) {
          if (owns()) {
            state = AsyncData(state.requireValue.copyWith(sends: sends));
          }
        }).observation,
      );
      state = AsyncData(
        _adopt(
          state.requireValue.copyWith(
            source: _repository.state.value,
            messages: _repository.messages.value,
            sends: _repository.sends.value,
            visible: true,
            observationIssue: null,
          ),
        ),
      );
      if (!owns()) return;
      if (failedReadIdentity(_repository.state.value.sourceStatus)
          case final target?) {
        _status?.remember(target);
      }
      _refreshStatus();
    } on StudioFailure catch (error) {
      _detach();
      if (_owns(lifetime) && _visible) {
        state = AsyncData(
          state.requireValue.copyWith(visible: true, observationIssue: error),
        );
      }
      return;
    }
    if (owns() && !_bootstrapAttempted) {
      _bootstrapAttempted = true;
      unawaited(_synchronize(retry: false));
    }
  }

  void _refreshStatus() {
    if (!_alive || !_visible || state.asData == null) return;
    final source = _repository.state.value;
    final origin = source.projection.stamp?.origin;
    final reference = source.projection.header?.source.status;
    _status?.target(
      origin == null || reference == null ? null : (origin, reference),
      needed:
          source.projection.sync.phase == ResourceSyncPhase.ready &&
          !isCurrentRead(source.sourceStatus, reference, origin),
    );
    _status?.visible(true);
  }

  Future<void> retrySource() async {
    if (!_alive || !_visible || state.asData == null) return;
    if (_observations.isEmpty) _attach();
    await _synchronize(retry: true);
    if (_alive && _visible) _status?.retry();
  }

  Future<void> _synchronize({required bool retry}) async {
    if (!_alive ||
        !_visible ||
        state.asData == null ||
        state.requireValue.synchronizing) {
      return;
    }
    final lifetime = _lifetime;
    state = AsyncData(
      state.requireValue.copyWith(synchronizing: true, syncIssue: null),
    );
    StudioFailure? issue;
    try {
      if (!_owns(lifetime) || !_visible) return;
      await (retry ? _repository.retrySync() : _repository.synchronize());
    } on StudioFailure catch (error) {
      issue = error;
    } finally {
      if (_owns(lifetime)) {
        state = AsyncData(
          _adopt(
            state.requireValue.copyWith(
              source: _repository.state.value,
              synchronizing: false,
              syncIssue: issue,
            ),
          ),
        );
        _refreshStatus();
      }
    }
  }

  void selectBot(String id) {
    if (!_alive ||
        !_visible ||
        state.asData == null ||
        state.requireValue.bots?.any((bot) => bot.id == id) != true) {
      return;
    }
    _messageRead++;
    state = AsyncData(
      _adopt(
        state.requireValue.copyWith(
          selectedBotId: id,
          readingMessages: false,
          messageIssue: null,
          draftIssue: null,
          draftRevision: state.requireValue.draftRevision + 1,
        ),
      ),
    );
  }

  void setChatId(String value) {
    if (!_alive || !_visible || state.asData == null) return;
    _messageRead++;
    state = AsyncData(
      _adopt(
        state.requireValue.copyWith(
          chatId: value,
          readingMessages: false,
          messageIssue: null,
          draftIssue: null,
          draftRevision: state.requireValue.draftRevision + 1,
        ),
      ),
    );
  }

  void editMessage(String text) {
    if (!_alive || !_visible || state.asData == null) return;
    final target = state.requireValue.chatTarget;
    if (target == null) return;
    try {
      _repository.updateMessageDraft(target.botId, target.chatId, text);
      state = AsyncData(
        state.requireValue.copyWith(
          messageDraft: _repository.messageDraft(target.botId, target.chatId),
          draftRevision: state.requireValue.draftRevision + 1,
          draftIssue: null,
        ),
      );
    } on StudioFailure catch (error) {
      // Preserve the rejected input for correction; never pretend it was saved.
      state = AsyncData(
        state.requireValue.copyWith(
          messageDraft: text,
          draftRevision: state.requireValue.draftRevision + 1,
          draftIssue: error,
        ),
      );
    }
  }

  Future<void> readMessages({bool nextPage = false}) async {
    if (!_alive ||
        !_visible ||
        state.asData == null ||
        !state.requireValue.editable ||
        state.requireValue.messagesPending) {
      return;
    }
    final target = state.requireValue.chatTarget;
    if (target == null) return;
    final cursor = nextPage ? state.requireValue.messagePage?.nextCursor : null;
    if (nextPage && cursor == null) return;
    final lifetime = _lifetime;
    final generation = ++_messageRead;
    state = AsyncData(
      state.requireValue.copyWith(readingMessages: true, messageIssue: null),
    );
    StudioFailure? issue;
    try {
      if (!_owns(lifetime) || !_visible || generation != _messageRead) return;
      await _repository.readMessages(
        target.botId,
        target.chatId,
        cursor: cursor,
      );
    } on StudioFailure catch (error) {
      issue = error;
    } finally {
      if (_owns(lifetime) && generation == _messageRead) {
        state = AsyncData(
          state.requireValue.copyWith(
            messages: _repository.messages.value,
            readingMessages: false,
            messageIssue: issue,
          ),
        );
      }
    }
  }

  BotSnapshot? _currentBot(String id) =>
      isCurrentBotsSnapshot(_repository.state.value)
      ? _repository.state.value.snapshot!.value.bots
            .where((bot) => bot.id == id)
            .firstOrNull
      : null;

  Future<void> setEnabled(String id, bool enabled) => _changeBot(
    id,
    (bot) => _repository.setEnabled(
      botId: bot.id,
      expectedConfigRevision: bot.configRevision,
      enabled: enabled,
    ),
  );

  Future<void> retryConnection(String id) =>
      _changeBot(id, (bot) => _repository.retryConnection(botId: bot.id));

  Future<void> setTrustedUser(String id, String openId, bool trusted) =>
      _changeBot(
        id,
        (bot) => _repository.setTrustedUser(
          botId: bot.id,
          expectedConfigRevision: bot.configRevision,
          openId: openId,
          trusted: trusted,
        ),
      );

  /// Clearing one pairing request writes the canonical trust value back; it can
  /// never widen the trusted set.
  Future<void> clearPairingRequest(String id, String openId) => _changeBot(
    id,
    (bot) => _repository.setTrustedUser(
      botId: bot.id,
      expectedConfigRevision: bot.configRevision,
      openId: openId,
      trusted: bot.trustedOpenIds.contains(openId),
    ),
  );

  Future<void> setTrustedChat(String id, String chatId, bool trusted) =>
      _changeBot(
        id,
        (bot) => _repository.setTrustedChat(
          botId: bot.id,
          expectedConfigRevision: bot.configRevision,
          chatId: chatId,
          trusted: trusted,
        ),
      );

  /// Project tools stay a configuration write of their own, preserving every
  /// other canonical field instead of inventing a second configuration fact.
  Future<void> setToolsEnabled(String id, bool enabled) => _changeBot(
    id,
    (bot) => _repository.saveBot(
      BotEdit(
        botId: bot.id,
        expectedConfigRevision: bot.configRevision,
        name: bot.name,
        projectId: bot.projectId,
        appId: bot.appId,
        secret: const BotSecretUpdate.preserve(),
        enabled: bot.enabled,
        toolsEnabled: enabled,
        modelRoute: bot.modelRoute,
      ),
    ),
  );

  /// The bot route is the single model source of every chat it owns; a save
  /// carries the canonical identity of that bot and freezes the new route.
  Future<void> setModelRoute(
    String id, {
    required String accountId,
    required String modelId,
    required String? effort,
  }) => _changeBot(
    id,
    (bot) => _repository.saveBot(
      BotEdit(
        botId: bot.id,
        expectedConfigRevision: bot.configRevision,
        name: bot.name,
        projectId: bot.projectId,
        appId: bot.appId,
        secret: const BotSecretUpdate.preserve(),
        enabled: bot.enabled,
        toolsEnabled: bot.toolsEnabled,
        modelRoute: BotModelRoute(
          accountId: accountId,
          modelId: modelId,
          effort: effort,
        ),
      ),
    ),
  );

  /// Creates the local session context of one platform conversation. The
  /// binding revision comes from the conversation the user acted on, so a newer
  /// binding is a rejected submission instead of a silent rebind.
  Future<void> createConversationThread(
    String id, {
    required String chatId,
    required int expectedBindingRevision,
  }) => _changeBot(
    id,
    (bot) => _repository.createConversationThread(
      botId: bot.id,
      chatId: chatId,
      expectedConfigRevision: bot.configRevision,
      expectedBindingRevision: expectedBindingRevision,
    ),
  );

  Future<void> startRegistration({required String name}) => _registration(
    () => _repository.startRegistration(name: name.trim(), projectId: ''),
  );

  Future<void> cancelRegistration() async {
    if (!_alive || state.asData == null) return;
    final attempt = state.requireValue.registration;
    if (attempt == null) return;
    await _registration(
      () => _repository.cancelRegistration(attemptId: attempt.attemptId),
    );
  }

  /// Start/cancel receipts only confirm the transient action; the attempt the
  /// page shows is always the canonical one, and a busy cancel stays a typed
  /// failure instead of a fake cancellation.
  Future<void> _registration(
    OperationTicket<BotRegistrationAttempt> Function() admit,
  ) async {
    if (!_alive || !_visible || state.asData == null) return;
    if (!state.requireValue.editable ||
        state.requireValue.registrationBlocked) {
      return;
    }
    final lifetime = _lifetime;
    final intent = ++_intent;
    void update(SettingsAction action) {
      if (!_owns(lifetime) ||
          state.requireValue.registrationAction?.intent != intent) {
        return;
      }
      state = AsyncData(
        state.requireValue.copyWith(registrationAction: action),
      );
    }

    state = AsyncData(
      state.requireValue.copyWith(
        registrationAction: SettingsAction(intent: intent, pending: true),
      ),
    );
    if (!_owns(lifetime)) return;
    await _execute(admit, intent, update);
  }

  Future<void> _changeBot<T>(
    String id,
    OperationTicket<T> Function(BotSnapshot) admit,
  ) async {
    if (!_alive ||
        !_visible ||
        state.asData == null ||
        !state.requireValue.editable ||
        (state.requireValue.botActions[id]?.preventsResubmission ?? false)) {
      return;
    }
    final bot = _currentBot(id);
    if (bot == null) return;
    final previous = state.requireValue.botActions[id];
    final lifetime = _lifetime;
    final intent = ++_intent;
    void update(SettingsAction action) {
      if (!_owns(lifetime) ||
          state.requireValue.botActions[id]?.intent != intent) {
        return;
      }
      state = AsyncData(
        state.requireValue.copyWith(
          botActions: {...state.requireValue.botActions, id: action},
        ),
      );
    }

    state = AsyncData(
      state.requireValue.copyWith(
        botActions: {
          ...state.requireValue.botActions,
          id: SettingsAction(intent: intent, pending: true),
        },
      ),
    );
    if (!_owns(lifetime)) return;
    if (!_visible || state.requireValue.botActions[id]?.intent != intent) {
      if (state.requireValue.botActions[id]?.intent == intent) {
        final actions = <String, SettingsAction>{
          ...state.requireValue.botActions,
        }..remove(id);
        if (previous != null) actions[id] = previous;
        state = AsyncData(state.requireValue.copyWith(botActions: actions));
      }
      return;
    }
    await _execute(() => admit(bot), intent, update);
    // No command return value is installed as a configuration/connection fact.
  }

  Future<void> sendMessage() async {
    if (!_alive ||
        !_visible ||
        state.asData == null ||
        !state.requireValue.canSend) {
      return;
    }
    await _send();
  }

  Future<void> retrySend(BotsSendRetry expected) async {
    if (!_alive || !_visible || state.asData == null) return;
    final current = state.requireValue.sendRetry;
    if (current == null ||
        current.target != expected.target ||
        current.text != expected.text ||
        current.draftRevision != expected.draftRevision ||
        current.intent != expected.intent ||
        current.operationId != expected.operationId) {
      return;
    }
    await _send();
  }

  Future<void> _send() async {
    final BotsSettingsViewState frozen = state.requireValue;
    final target = frozen.chatTarget!;
    final text = frozen.messageDraft;
    final lifetime = _lifetime;
    final intent = ++_intent;
    final previous = frozen.messageActions[target];
    void update(SettingsAction action) {
      if (!_owns(lifetime) ||
          state.requireValue.messageActions[target]?.action.intent != intent) {
        return;
      }
      state = AsyncData(
        state.requireValue.copyWith(
          messageActions: {
            ...state.requireValue.messageActions,
            target: BotsMessageAction(text: text, action: action),
          },
        ),
      );
    }

    state = AsyncData(
      frozen.copyWith(
        messageActions: {
          ...frozen.messageActions,
          target: BotsMessageAction(
            text: text,
            action: SettingsAction(intent: intent, pending: true),
          ),
        },
      ),
    );
    if (!_owns(lifetime)) return;
    if (!_visible ||
        state.requireValue.chatTarget != target ||
        state.requireValue.messageActions[target]?.action.intent != intent) {
      if (state.requireValue.messageActions[target]?.action.intent == intent) {
        final actions = <BotsChatTarget, BotsMessageAction>{
          ...state.requireValue.messageActions,
        }..remove(target);
        if (previous != null) actions[target] = previous;
        state = AsyncData(state.requireValue.copyWith(messageActions: actions));
      }
      return;
    }
    await _execute(
      () => _repository.sendMessage(
        botId: target.botId,
        chatId: target.chatId,
        text: text,
      ),
      intent,
      update,
    );
    if (!_owns(lifetime)) return;
    final SettingsAction? action =
        state.requireValue.messageActions[target]?.action;
    final result = _repository.sends.value.byOperationId[action?.operation?.id];
    // A local committed ledger result can still mean external rejection.
    // Old completion must not clear a newer edit, selection or retyped draft.
    if (_visible &&
        action != null &&
        action.intent == intent &&
        action.succeeded &&
        result?.status == BotSendStatus.succeeded &&
        state.requireValue.chatTarget == target &&
        state.requireValue.draftRevision == frozen.draftRevision &&
        _repository.messageDraft(target.botId, target.chatId) == text) {
      try {
        _repository.updateMessageDraft(target.botId, target.chatId, '');
        state = AsyncData(
          state.requireValue.copyWith(
            messageDraft: '',
            draftRevision: state.requireValue.draftRevision + 1,
          ),
        );
      } on StudioFailure catch (error) {
        state = AsyncData(state.requireValue.copyWith(draftIssue: error));
      }
    }
  }

  /// Borrow only the original ticket's result. No observation or Future owns
  /// cancellation of the accepted command, and no failure path re-admits it.
  Future<void> _execute<T>(
    OperationTicket<T> Function() admit,
    int intent,
    void Function(SettingsAction) update,
  ) async {
    final OperationTicket<T> ticket;
    try {
      ticket = admit();
    } on StudioFailure catch (error) {
      update(
        SettingsAction(
          intent: intent,
          outcome: SettingsActionOutcome.rejected,
          error: error,
        ),
      );
      return;
    }
    update(
      SettingsAction(
        intent: intent,
        pending: true,
        operation: ticket.state.value,
      ),
    );
    try {
      final result = await ticket.result;
      update(
        settledSettingsAction(intent, result, operation: ticket.state.value),
      );
    } on StudioFailure catch (error) {
      // Once admitted, an exceptional result is not proof of no side effect.
      update(
        SettingsAction(
          intent: intent,
          operation: ticket.state.value,
          outcome: SettingsActionOutcome.unknownOutcome,
          error: error,
        ),
      );
    }
  }
}
