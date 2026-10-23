import 'dart:async';

import 'package:anywork_client/configuration.dart';
import 'package:anywork_client/models.dart';
import 'package:anywork_client/operations.dart';
import 'package:anywork_client/resources.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../../app/app_bindings.dart';
import '../../../../app/lifecycle/exit_participant.dart';
import '../../state/settings_action.dart';
import '../../view_models/collection_values.dart';
import '../../view_models/visible_read_demand.dart';
import '../state/model_limits_state.dart';
import 'account_detail_participant.dart';
import 'accounts_view_model.dart';

part 'account_model_limits_view_model.g.dart';

@riverpod
class AccountModelLimitsViewModel extends _$AccountModelLimitsViewModel
    implements ApplicationEditProducer, AccountDetailParticipant {
  late ConfigurationRepository _configuration;
  late ModelsRepository _models;
  late String _accountId;
  late VisibleReadDemand<(ProductReadOrigin, ConfigurationReadRef)> _accountRead;
  late VisibleReadDemand<(ProductReadOrigin, ModelCatalogReadRef)> _modelRead;
  ApplicationEditRegistration? _registration;
  final _timers = <String, Timer>{};
  final _observations = <String, Observation>{};
  int _intent = 0;
  int _lifetime = 0;
  bool _alive = true;
  bool _sealed = false;
  bool _visible = true;
  void Function()? _releaseRetention;

  @override
  Future<AccountModelLimitsViewState> build(String accountId) async {
    final accounts = ref.read(accountsViewModelProvider.notifier);
    if (!accounts.detailRequested(accountId)) throw const StudioFailure(
      code: StudioFailureCode.cancelled, message: 'Account details are no longer visible.',
      retryable: false, correlationId: 'settings-account-limits');
    _accountId = accountId;
    _alive = true;
    _sealed = false;
    final lifetime = ++_lifetime;
    _configuration = ref.watch(configurationRepositoryProvider);
    _models = ref.watch(modelsRepositoryProvider);
    _releaseRetention = ref.keepAlive().close;
    final detach = accounts.attachDetail(accountId, this);
    _accountRead = VisibleReadDemand(read: (target) async {
      final source = _configuration.state.value;
      if (source.projection.stamp?.origin != target.$1 || source.projection.header?.reference != target.$2) return;
      final account = await _configuration.loadAccount(accountId);
      if (!_owns(lifetime) || _configuration.state.value.projection.stamp?.origin != target.$1 ||
          _configuration.state.value.projection.header?.reference != target.$2) return;
      state = AsyncData(_confirm(state.requireValue.copyWith(canonical: account)));
    }, changed: (target, error, current) => _readChanged(ModelLimitsReadField.configuration, error, current, lifetime));
    _modelRead = VisibleReadDemand(read: (target) async {
      final source = _models.state.value;
      if (source.projection.stamp?.origin != target.$1 || source.projection.header?.reference != target.$2) return;
      final catalog = await _models.loadAccount(accountId);
      if (!_owns(lifetime) || _models.state.value.projection.stamp?.origin != target.$1 ||
          _models.state.value.projection.header?.reference != target.$2) return;
      state = AsyncData(state.requireValue.copyWith(catalog: catalog));
    }, changed: (target, error, current) => _readChanged(ModelLimitsReadField.catalog, error, current, lifetime));
    Observation? configurationObservation;
    Observation? modelObservation;
    ref.onDispose(() {
      _alive = false;
      _lifetime++;
      for (final timer in _timers.values) { timer.cancel(); }
      for (final observation in _observations.values) { observation.cancel(); }
      configurationObservation?.cancel();
      modelObservation?.cancel();
      _accountRead.dispose();
      _modelRead.dispose();
      _registration?.unregister();
      detach();
      // Disposal never starts a write or cancels Repository-owned work.
    });
    final configurationWatch = _configuration.state.watchLatest((source) {
      if (!_owns(lifetime)) return;
      final account = currentCollectionRow(source.accounts, source.projection.stamp?.origin,
        (value) => value.accountId == accountId)?.value;
      state = AsyncData(_confirm(state.requireValue.copyWith(source: source,
        canonical: account ?? state.requireValue.canonical)));
      _refreshReads();
    });
    configurationObservation = configurationWatch.observation;
    final modelWatch = _models.state.watchLatest((source) {
      if (!_owns(lifetime)) return;
      final catalog = currentCollectionRow(source.accounts, source.projection.stamp?.origin,
        (value) => value.accountId == accountId)?.value;
      state = AsyncData(state.requireValue.copyWith(modelSource: source,
        catalog: catalog ?? state.requireValue.catalog));
      _refreshReads();
    });
    modelObservation = modelWatch.observation;
    _registration = ref.read(applicationEditProducerRegistryProvider).register(this);
    late AccountConfiguration account;
    late AccountCatalogEntry catalog;
    await Future.wait<void>([
      _configuration.loadAccount(accountId).then((value) { account = value; }),
      _models.loadAccount(accountId).then((value) { catalog = value; }),
    ]);
    Future<void>(() { if (_owns(lifetime)) _refreshReads(); });
    return AccountModelLimitsViewState(accountId: accountId, source: _configuration.state.value,
      modelSource: _models.state.value, canonical: account, catalog: catalog);
  }

  bool _owns(int lifetime) => _alive && lifetime == _lifetime && state.asData != null;

  void _readChanged(ModelLimitsReadField field, StudioFailure? error, bool current, int lifetime) {
    if (!_owns(lifetime)) return;
    final issues = {...state.requireValue.readIssues};
    if (current) {
      if (error == null) { issues.remove(field); }
      else { issues[field] = error; }
    }
    state = AsyncData(state.requireValue.copyWith(readIssues: issues,
      readPending: _accountRead.reading || _modelRead.reading));
  }

  void retryRead() {
    if (!_alive || _sealed || state.asData == null) return;
    _refreshReads();
    _accountRead.retry();
    _modelRead.retry();
  }

  bool _hasModel(String modelId) => state.asData?.value.catalog.effectiveModels
    .any((model) => model.modelId == modelId) ?? false;

  void setVisible(bool visible) {
    if (!_alive || _sealed) return;
    _visible = visible;
    if (visible) _registration ??= ref.read(applicationEditProducerRegistryProvider).register(this);
    _refreshReads();
  }
  void _refreshReads() {
    if (state.asData == null || !_alive) return;
    final config = _configuration.state.value;
    final models = _models.state.value;
    final origin = config.projection.stamp?.origin;
    final reference = config.projection.header?.reference;
    final modelOrigin = models.projection.stamp?.origin;
    final modelReference = models.projection.header?.reference;
    _accountRead.visible(false);
    _modelRead.visible(false);
    _accountRead.target(origin == null || reference == null ? null : (origin, reference),
      needed: currentCollectionRow(config.accounts, origin, (value) => value.accountId == _accountId) == null);
    _modelRead.target(modelOrigin == null || modelReference == null ? null : (modelOrigin, modelReference),
      needed: currentCollectionRow(models.accounts, modelOrigin, (value) => value.accountId == _accountId) == null);
    _accountRead.visible(_visible && !_sealed);
    _modelRead.visible(_visible && !_sealed);
  }

  void edit(String modelId, String raw) {
    if (!_alive || _sealed || !_hasModel(modelId)) return;
    _registration ??= ref.read(applicationEditProducerRegistryProvider).register(this);
    final current = _draft(modelId);
    if (current.raw == raw && !current.restoreDefault) return;
    _timers.remove(modelId)?.cancel();
    final parsed = _parse(raw);
    final draft = current.copyWith(raw: raw, intent: ++_intent, dirty: true,
      restoreDefault: false, validation: parsed == null ? ModelLimitValidation.positiveAsciiInteger : null);
    _replace(modelId, draft);
    if (parsed != null && !draft.composing) _schedule(modelId);
  }

  void setComposing(String modelId, bool composing) {
    if (!_alive || _sealed || !_hasModel(modelId)) return;
    final draft = _draft(modelId);
    _replace(modelId, draft.copyWith(composing: composing));
    if (composing) _timers.remove(modelId)?.cancel();
    else if (draft.dirty && draft.validation == null) _schedule(modelId);
  }

  void restoreDefault(String modelId) {
    if (!_alive || _sealed || !_hasModel(modelId)) return;
    _registration ??= ref.read(applicationEditProducerRegistryProvider).register(this);
    final previous = _draft(modelId);
    if (previous.restoreDefault && (previous.action?.preventsResubmission ?? false)) return;
    _timers.remove(modelId)?.cancel();
    _replace(modelId, previous.copyWith(raw: '', restoreDefault: true,
      composing: false, validation: null, dirty: true, intent: ++_intent));
    _dispatch(modelId);
  }

  void commit(String modelId) {
    if (!_alive || _sealed || !_hasModel(modelId)) return;
    _timers.remove(modelId)?.cancel();
    final draft = _draft(modelId);
    if (draft.action?.outcome == SettingsActionOutcome.rejected) {
      _replace(modelId, draft.copyWith(intent: ++_intent));
    }
    _dispatch(modelId);
  }

  void _schedule(String modelId) {
    _timers.remove(modelId)?.cancel();
    _timers[modelId] = Timer(const Duration(milliseconds: 650), () {
      _timers.remove(modelId);
      if (!_sealed) _dispatch(modelId);
    });
  }

  void leave() {
    _visible = false;
    _accountRead.visible(false);
    _modelRead.visible(false);
    _handoff();
    _registration?.unregister();
    _registration = null;
  }
  @override
  void endEditing() {
    leave();
    _sealed = true;
    _releaseRetention?.call();
    _releaseRetention = null;
    // accountId is the family key: retiring the edit lifetime must not leave a
    // sealed instance for a rapid back/select of the same account. A rebuild
    // checks the list owner's actual demand before it can register or read.
    ref.invalidateSelf();
  }
  @override
  void sealAndHandoff() {
    if (_sealed) return;
    _sealed = true;
    _visible = false;
    _accountRead.visible(false);
    _modelRead.visible(false);
    _handoff();
  }
  void _handoff() {
    for (final timer in _timers.values) { timer.cancel(); }
    _timers.clear();
    if (state.asData == null) return;
    for (final modelId in state.requireValue.drafts.keys.toList()) { _dispatch(modelId); }
  }

  void _dispatch(String modelId) {
    if (!_alive || state.asData == null) return;
    final frozen = _draft(modelId);
    if (!frozen.dirty || frozen.composing || frozen.validation != null || frozen.action?.intent == frozen.intent) return;
    final value = frozen.restoreDefault ? null : _parse(frozen.raw);
    if (!frozen.restoreDefault && value == null) return;
    final lifetime = _lifetime;
    _replace(modelId, frozen.copyWith(action: SettingsAction(intent: frozen.intent, pending: true)));
    OperationTicket<Unit> ticket;
    try {
      ticket = _configuration.saveAccount(AccountEdit(accountId: _accountId, create: false,
        templateId: const FieldEdit.keep(), protocol: const FieldEdit.keep(), name: const FieldEdit.keep(),
        baseUrl: const FieldEdit.keep(), pricingEnabled: const FieldEdit.keep(), secret: const AccountSecretUpdate.preserve(),
        customModels: [], connections: [], autoCompactLimits: [ModelLimitChange(modelId: modelId, overrideLimit: value)]));
    } on StudioFailure catch (error) {
      if (!_owns(lifetime) || _draft(modelId).action?.intent != frozen.intent) return;
      _replace(modelId, _draft(modelId).copyWith(action: SettingsAction(intent: frozen.intent,
        outcome: SettingsActionOutcome.rejected, error: error)));
      return;
    }
    if (!_owns(lifetime) || _draft(modelId).action?.intent != frozen.intent) {
      unawaited(_settle(modelId, frozen.intent, ticket, lifetime, null));
      return;
    }
    _observations.remove(modelId)?.cancel();
    StudioFailure? observationError;
    try {
      final watch = ticket.state.watchLatest((operation) {
        if (!_owns(lifetime) || _draft(modelId).action?.intent != frozen.intent) return;
        final current = _draft(modelId);
        _replace(modelId, current.copyWith(action: current.action?.copyWith(operation: operation)));
      });
      _observations[modelId] = watch.observation;
    } on StudioFailure catch (error) { observationError = error; }
    _replace(modelId, _draft(modelId).copyWith(action: SettingsAction(intent: frozen.intent, pending: true,
      operation: ticket.state.value, observationError: observationError)));
    unawaited(_settle(modelId, frozen.intent, ticket, lifetime, observationError));
  }

  Future<void> _settle(String modelId, int intent, OperationTicket<Unit> ticket,
      int lifetime, StudioFailure? observationError) async {
    final result = await ticket.result;
    if (!_owns(lifetime) || _draft(modelId).action?.intent != intent) return;
    final current = _draft(modelId);
    _replace(modelId, current.copyWith(action: settledSettingsAction(intent, result,
      operation: ticket.state.value).copyWith(observationError: observationError)));
    state = AsyncData(_confirm(state.requireValue));
    _refreshReads();
  }

  AccountModelLimitsViewState _confirm(AccountModelLimitsViewState value) {
    final ready = currentCollectionRow(value.source.accounts, value.source.projection.stamp?.origin,
      (account) => account.accountId == _accountId);
    if (ready == null) return value;
    final drafts = {...value.drafts};
    for (final entry in drafts.entries.toList()) {
      final draft = entry.value;
      final canonical = ready.value.modelAutoCompactLimits.where((limit) => limit.modelId == entry.key).firstOrNull?.overrideLimit;
      if (!draft.dirty) {
        if (canonical != _parse(draft.raw)) drafts[entry.key] = draft.copyWith(
          raw: canonical?.toString() ?? '', restoreDefault: false);
        continue;
      }
      if (!(draft.action?.succeeded ?? false) || draft.action!.intent != draft.intent) continue;
      final intended = draft.restoreDefault ? null : _parse(draft.raw);
      if (canonical == intended) drafts[entry.key] = draft.copyWith(dirty: false);
    }
    return value.copyWith(drafts: drafts);
  }

  ModelLimitDraft _draft(String modelId) => state.requireValue.drafts[modelId] ?? ModelLimitDraft(
    raw: state.requireValue.canonical.modelAutoCompactLimits.where((limit) => limit.modelId == modelId)
      .firstOrNull?.overrideLimit?.toString() ?? '', intent: 0);
  void _replace(String modelId, ModelLimitDraft draft) => state = AsyncData(state.requireValue.copyWith(
    drafts: {...state.requireValue.drafts, modelId: draft}));
  static int? _parse(String raw) {
    if (!RegExp(r'^[0-9]+$').hasMatch(raw)) return null;
    final value = int.tryParse(raw);
    return value != null && value > 0 ? value : null;
  }
}
