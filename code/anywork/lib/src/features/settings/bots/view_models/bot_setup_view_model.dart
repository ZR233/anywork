import 'package:anywork_client/bots.dart';
import 'package:anywork_client/operations.dart';
import 'package:anywork_client/resources.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../../app/app_bindings.dart';
import '../../state/settings_action.dart';
import '../state/bot_setup_state.dart';
import '../state/bots_settings_view_state.dart';

part 'bot_setup_view_model.g.dart';

/// One bot create/edit session. It freezes the command inputs before waiting,
/// keeps pending/rejected/unknown presentation for its own intent, and never
/// turns a receipt into a configuration fact: the canonical snapshot is the
/// only source for what actually got saved.
@riverpod
class BotSetupViewModel extends _$BotSetupViewModel {
  late BotsRepository _repository;
  final _observations = <Observation>[];
  bool _alive = false;
  int _lifetime = 0;
  int _intent = 0;

  @override
  Future<BotSetupViewState> build(BotSetupKey key) async {
    _alive = true;
    final lifetime = ++_lifetime;
    _repository = ref.watch(botsRepositoryProvider);
    ref.onDispose(() {
      _alive = false;
      _lifetime++;
      for (final observation in _observations) {
        observation.cancel();
      }
      _observations.clear();
      // An admitted save still belongs to the Repository; closing the editor
      // never replays it and never pretends it was rolled back.
    });
    final source = _repository.state.value;
    _observe(lifetime, key);
    if (key.botId case final id?) {
      if (!isCurrentBotsSnapshot(source)) {
        throw _failure(
          StudioFailureCode.unavailable,
          'The bot configuration is not current.',
        );
      }
      final bot = _currentBot(source, id);
      if (bot == null) {
        throw _failure(
          StudioFailureCode.notFound,
          'The bot is no longer part of the current configuration.',
        );
      }
      return BotSetupViewState(
        key: key,
        mode: BotSetupMode.edit,
        source: source,
        canonical: bot,
        name: bot.name,
        appId: bot.appId,
        projectId: bot.projectId,
        canChangeAppId: bot.canChangeAppId,
      );
    }
    return BotSetupViewState(
      key: key,
      mode: BotSetupMode.create,
      source: source,
    );
  }

  int get lifetime => _lifetime;

  bool ownsEditor(int lifetime, BotSetupKey key) =>
      _owns(lifetime) && state.requireValue.key == key;

  bool _owns(int lifetime) =>
      _alive && lifetime == _lifetime && state.asData != null;

  BotSnapshot? _currentBot(BotsState source, String id) =>
      isCurrentBotsSnapshot(source)
      ? source.snapshot!.value.bots.where((bot) => bot.id == id).firstOrNull
      : null;

  /// Canonical updates refresh provenance and the identity constraints. They
  /// never overwrite a field the user is editing or a settled editor result.
  void _observe(int lifetime, BotSetupKey key) {
    _observations.add(
      _repository.state.watchLatest((source) {
        if (!_owns(lifetime) || state.requireValue.key != key) return;
        final current = state.requireValue;
        final fresh = current.create ? null : _currentBot(source, key.botId!);
        state = AsyncData(
          current.copyWith(
            source: source,
            canonical: fresh ?? current.canonical,
            canChangeAppId: fresh?.canChangeAppId ?? current.canChangeAppId,
          ),
        );
      }).observation,
    );
  }

  bool get _editable =>
      _alive && state.asData != null && state.requireValue.editable;

  void _changed(BotSetupViewState value) {
    state = AsyncData(
      value.copyWith(
        draftRevision: value.draftRevision + 1,
        validation: {...value.validation},
      ),
    );
  }

  void setName(String value) {
    if (!_editable || state.requireValue.name == value) return;
    final current = state.requireValue;
    _changed(
      current.copyWith(
        name: value,
        validation: {...current.validation}..remove(BotSetupField.name),
      ),
    );
  }

  void setAppId(String value) {
    if (!_editable ||
        !state.requireValue.create && !state.requireValue.canChangeAppId) {
      return;
    }
    if (state.requireValue.appId == value) return;
    final current = state.requireValue;
    _changed(
      current.copyWith(
        appId: value,
        validation: {...current.validation}..remove(BotSetupField.appId),
      ),
    );
  }

  /// The create flow states the remote-execution risk before it can register
  /// or save; it is a draft acknowledgement, not a stored permission.
  void setRiskAcknowledged(bool value) {
    if (!_editable || !state.requireValue.create) return;
    if (state.requireValue.riskAcknowledged == value) return;
    _changed(state.requireValue.copyWith(riskAcknowledged: value));
  }

  /// "连接已有应用" reveals the manual App ID/Secret entry, exactly like the
  /// overview's manual setup section: scanning and manual entry stay separate.
  void openManual() {
    if (!_editable || !state.requireValue.create) return;
    if (state.requireValue.manualOpen) return;
    _changed(state.requireValue.copyWith(manualOpen: true));
  }

  void setSecretIntent(BotSecretIntent intent) {
    if (!_editable || state.requireValue.secretIntent == intent) return;
    final current = state.requireValue;
    _changed(
      current.copyWith(
        secretIntent: intent,
        validation: {...current.validation}..remove(BotSetupField.secret),
      ),
    );
  }

  /// Called by the editor's local secret owner. Only presence crosses into the
  /// ViewModel; the text itself stays in the owner.
  void secretPresenceChanged(bool present) {
    if (!_alive || state.asData == null) return;
    final current = state.requireValue;
    if (current.secretIntent == BotSecretIntent.clear) return;
    final intent = present ? BotSecretIntent.replace : BotSecretIntent.preserve;
    if (current.secretIntent == intent) return;
    state = AsyncData(
      current.copyWith(
        secretIntent: intent,
        validation: {...current.validation}..remove(BotSetupField.secret),
      ),
    );
  }

  BotSetupViewState _validate(BotSetupViewState value, String? secret) {
    final fields = <BotSetupField, BotSetupValidation>{};
    if (value.name.trim().isEmpty) {
      fields[BotSetupField.name] = BotSetupValidation.required;
    }
    if (value.create && value.appId.trim().isEmpty) {
      fields[BotSetupField.appId] = BotSetupValidation.required;
    }
    // A create always replaces the (absent) secret; an edit only replaces it
    // when the owner actually holds a new value.
    if ((value.create || value.secretIntent == BotSecretIntent.replace) &&
        (secret == null || secret.trim().isEmpty)) {
      fields[BotSetupField.secret] = BotSetupValidation.required;
    }
    return value.copyWith(validation: fields);
  }

  /// Freezes one save intent. A rejected or unknown outcome keeps every draft
  /// value for correction and never re-admits the command.
  Future<bool> save({required String? secret}) async {
    if (!_alive ||
        state.asData == null ||
        !state.requireValue.editable ||
        !state.requireValue.snapshotCurrent) {
      return false;
    }
    final validated = _validate(state.requireValue, secret);
    state = AsyncData(validated);
    if (validated.validation.isNotEmpty) return false;
    if (validated.create && !validated.riskAcknowledged) return false;
    final canonical = validated.canonical;
    if (!validated.create && canonical == null) return false;

    final lifetime = _lifetime;
    final intent = ++_intent;
    final frozen = validated;
    void update(SettingsAction action) {
      if (!_owns(lifetime) || state.requireValue.saveAction?.intent != intent) {
        return;
      }
      state = AsyncData(state.requireValue.copyWith(saveAction: action));
    }

    state = AsyncData(
      frozen.copyWith(
        saveAction: SettingsAction(intent: intent, pending: true),
        sourceError: null,
      ),
    );
    final BotEdit edit = frozen.create
        ? BotEdit(
            botId: null,
            expectedConfigRevision: 0,
            name: frozen.name.trim(),
            // An empty project lets the runtime place the bot in its own
            // managed workspace; the editor never invents a project identity.
            projectId: '',
            appId: frozen.appId.trim(),
            secret: BotSecretReplace(value: secret!.trim()),
            enabled: true,
            toolsEnabled: false,
            modelRoute: null,
          )
        : BotEdit(
            botId: canonical!.id,
            expectedConfigRevision: canonical.configRevision,
            name: frozen.name.trim(),
            projectId: canonical.projectId,
            appId: frozen.canChangeAppId
                ? frozen.appId.trim()
                : canonical.appId,
            secret: switch (frozen.secretIntent) {
              BotSecretIntent.preserve => const BotSecretUpdate.preserve(),
              BotSecretIntent.replace => BotSecretReplace(
                value: secret!.trim(),
              ),
              BotSecretIntent.clear => const BotSecretUpdate.clear(),
            },
            // Enablement and project tools keep their own detail actions; this
            // editor only edits the credential identity and the name.
            enabled: canonical.enabled,
            toolsEnabled: canonical.toolsEnabled,
            // The route belongs to the configuration owner; this editor shows
            // no route field, so it preserves whatever is canonical.
            modelRoute: canonical.modelRoute,
          );

    final OperationTicket<BotSnapshot> ticket;
    try {
      ticket = _repository.saveBot(edit);
    } on StudioFailure catch (error) {
      update(
        SettingsAction(
          intent: intent,
          outcome: SettingsActionOutcome.rejected,
          error: error,
        ),
      );
      return false;
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
    if (!_owns(lifetime)) return false;
    final action = state.requireValue.saveAction;
    return action?.intent == intent && action!.succeeded;
  }

  static StudioFailure _failure(StudioFailureCode code, String message) =>
      StudioFailure(
        code: code,
        message: message,
        retryable: true,
        correlationId: 'settings-bot-setup',
      );
}
