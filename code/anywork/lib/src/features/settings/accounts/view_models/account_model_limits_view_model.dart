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
import '../../view_models/coalesced_publish.dart';
import '../../view_models/visible_read_demand.dart';
import '../state/account_model_details_state.dart';
import '../state/model_limits_state.dart';
import 'account_detail_participant.dart';
import 'account_model_details_target.dart';
import 'accounts_view_model.dart';

part 'account_model_limits_view_model.g.dart';

@riverpod
class AccountModelLimitsViewModel extends _$AccountModelLimitsViewModel
    implements ApplicationEditProducer, AccountDetailParticipant {
  late ConfigurationRepository _configuration;
  late ModelsRepository _models;
  late String _accountId;
  late VisibleReadDemand<(ProductReadOrigin, ConfigurationReadRef)>
  _accountRead;
  late VisibleReadDemand<(ProductReadOrigin, ModelCatalogReadRef)> _modelRead;
  ApplicationEditRegistration? _registration;
  final _timers = <String, Timer>{};
  final _observations = <String, Observation>{};
  final _enabledObservations = <String, Observation>{};
  Observation? _billingObservation;
  int _intent = 0;
  int _lifetime = 0;
  bool _alive = true;
  bool _sealed = false;
  bool _visible = true;
  void Function()? _releaseRetention;

  @override
  Future<AccountModelLimitsViewState> build(String accountId) async {
    final accounts = ref.read(accountsViewModelProvider.notifier);
    if (!accounts.detailRequested(accountId)) {
      throw const StudioFailure(
        code: StudioFailureCode.cancelled,
        message: 'Account details are no longer visible.',
        retryable: false,
        correlationId: 'settings-account-limits',
      );
    }
    _accountId = accountId;
    _alive = true;
    _sealed = false;
    final lifetime = ++_lifetime;
    _configuration = ref.watch(configurationRepositoryProvider);
    _models = ref.watch(modelsRepositoryProvider);
    _releaseRetention = ref.keepAlive().close;
    final detach = accounts.attachDetail(accountId, this);
    _accountRead = VisibleReadDemand(
      read: (target) async {
        final source = _configuration.state.value;
        if (source.projection.stamp?.origin != target.$1 ||
            source.projection.header?.reference != target.$2) {
          return;
        }
        final account = await _configuration.loadAccount(accountId);
        if (!_owns(lifetime) ||
            _configuration.state.value.projection.stamp?.origin != target.$1 ||
            _configuration.state.value.projection.header?.reference !=
                target.$2) {
          return;
        }
        state = AsyncData(
          _confirm(state.requireValue.copyWith(canonical: account)),
        );
      },
      changed: (target, error, current) => _readChanged(
        ModelLimitsReadField.configuration,
        error,
        current,
        lifetime,
      ),
    );
    _modelRead = VisibleReadDemand(
      read: (target) async {
        final source = _models.state.value;
        if (source.projection.stamp?.origin != target.$1 ||
            source.projection.header?.reference != target.$2) {
          return;
        }
        final catalog = await _models.loadAccount(accountId);
        if (!_owns(lifetime) ||
            _models.state.value.projection.stamp?.origin != target.$1 ||
            _models.state.value.projection.header?.reference != target.$2) {
          return;
        }
        state = AsyncData(
          _confirm(state.requireValue.copyWith(catalog: catalog)),
        );
      },
      changed: (target, error, current) =>
          _readChanged(ModelLimitsReadField.catalog, error, current, lifetime),
    );
    Observation? configurationObservation;
    Observation? modelObservation;
    ref.onDispose(() {
      _alive = false;
      _lifetime++;
      for (final timer in _timers.values) {
        timer.cancel();
      }
      for (final observation in _observations.values) {
        observation.cancel();
      }
      _cancelFieldObservations();
      configurationObservation?.cancel();
      modelObservation?.cancel();
      _accountRead.dispose();
      _modelRead.dispose();
      _registration?.unregister();
      detach();
      // Disposal never starts a write or cancels Repository-owned work.
    });
    // Sources can publish while another provider is still building; one trailing
    // microtask applies the latest account/catalog pair and refreshes the reads.
    final sourcePublish = CoalescedPublish(() {
      if (_owns(lifetime)) _publishSources(lifetime, accountId);
    });
    ref.onDispose(sourcePublish.dispose);
    final configurationWatch = _configuration.state.watchLatest((_) {
      if (_owns(lifetime)) sourcePublish.mark();
    });
    configurationObservation = configurationWatch.observation;
    final modelWatch = _models.state.watchLatest((_) {
      if (_owns(lifetime)) sourcePublish.mark();
    });
    modelObservation = modelWatch.observation;
    _registration = ref
        .read(applicationEditProducerRegistryProvider)
        .register(this);
    await Future.wait<void>([
      _configuration.loadAccount(accountId).then((_) {}),
      _models.loadAccount(accountId).then((_) {}),
    ]);
    final source = _configuration.state.value;
    final modelSource = _models.state.value;
    final account = currentCollectionRow(
      source.accounts,
      source.projection.stamp?.origin,
      (item) => item.accountId == accountId,
    )?.value;
    final catalog = currentCollectionRow(
      modelSource.accounts,
      modelSource.projection.stamp?.origin,
      (item) => item.accountId == accountId,
    )?.value;
    if (account == null || catalog == null) {
      throw const StudioFailure(
        code: StudioFailureCode.superseded,
        message: 'The account changed while its details were loading.',
        retryable: true,
        correlationId: 'settings-account-limits',
      );
    }
    Future<void>(() {
      if (_owns(lifetime)) _refreshReads();
    });
    return _confirm(
      AccountModelLimitsViewState(
        accountId: accountId,
        source: source,
        modelSource: modelSource,
        canonical: account,
        catalog: catalog,
      ),
    );
  }

  bool _owns(int lifetime) =>
      _alive && lifetime == _lifetime && state.asData != null;

  /// Applies the latest account/catalog pair in one write, then refreshes the
  /// visible-read demand it drives.
  void _publishSources(int lifetime, String accountId) {
    final source = _configuration.state.value;
    final modelSource = _models.state.value;
    final account = currentCollectionRow(
      source.accounts,
      source.projection.stamp?.origin,
      (value) => value.accountId == accountId,
    )?.value;
    final catalog = currentCollectionRow(
      modelSource.accounts,
      modelSource.projection.stamp?.origin,
      (value) => value.accountId == accountId,
    )?.value;
    state = AsyncData(
      _confirm(
        state.requireValue.copyWith(
          source: source,
          canonical: account ?? state.requireValue.canonical,
          modelSource: modelSource,
          catalog: catalog ?? state.requireValue.catalog,
        ),
      ),
    );
    _refreshReads();
  }

  void _readChanged(
    ModelLimitsReadField field,
    StudioFailure? error,
    bool current,
    int lifetime,
  ) {
    if (!_owns(lifetime)) return;
    final issues = {...state.requireValue.readIssues};
    if (current) {
      if (error == null) {
        issues.remove(field);
      } else {
        issues[field] = error;
      }
    }
    state = AsyncData(
      state.requireValue.copyWith(
        readIssues: issues,
        readPending: _accountRead.reading || _modelRead.reading,
      ),
    );
  }

  void retryRead() {
    if (!_alive || _sealed || state.asData == null) return;
    _refreshReads();
    _accountRead.retry();
    _modelRead.retry();
  }

  bool _hasModel(String modelId) =>
      state.asData?.value.catalog.effectiveModels.any(
        (model) => model.modelId == modelId,
      ) ??
      false;

  AccountFieldBinding? _binding(AccountModelLimitsViewState value) {
    final account = currentCollectionRow(
      value.source.accounts,
      value.source.projection.stamp?.origin,
      (item) => item.accountId == value.accountId,
    );
    final catalog = currentCollectionRow(
      value.modelSource.accounts,
      value.modelSource.projection.stamp?.origin,
      (item) => item.accountId == value.accountId,
    );
    if (account == null || catalog == null) return null;
    return AccountFieldBinding(
      configurationOrigin: account.origin,
      accountEntry: account.reference.entry,
      catalogOrigin: catalog.origin,
      catalogEntry: catalog.reference.entry,
    );
  }

  bool _canChangeField(AccountFieldBinding? binding) =>
      _alive &&
      !_sealed &&
      _visible &&
      state.asData != null &&
      binding != null &&
      binding == state.requireValue.binding &&
      binding ==
          _binding(
            state.requireValue.copyWith(
              source: _configuration.state.value,
              modelSource: _models.state.value,
            ),
          );

  Future<void> setModelEnabled(
    String modelId,
    bool enabled,
    AccountFieldBinding binding,
  ) async {
    if (!_canChangeField(binding) || !_hasModel(modelId)) return;
    final previous = state.requireValue.enabledActions[modelId];
    if (previous != null &&
        previous.binding == binding &&
        (previous.action.uncertain ||
            previous.action.outcome ==
                SettingsActionOutcome.synchronizationFailed ||
            (previous.action.pending && previous.enabled == enabled))) {
      return;
    }
    // Freeze the original VM/member/field/intent and Repository before await.
    final accountId = _accountId;
    final configuration = _configuration;
    final lifetime = _lifetime;
    final intent = ++_intent;
    bool owns() =>
        _owns(lifetime) &&
        state.requireValue.enabledActions[modelId]?.binding == binding &&
        state.requireValue.enabledActions[modelId]?.action.intent == intent;
    void update(SettingsAction action) {
      if (!owns()) return;
      state = AsyncData(
        state.requireValue.copyWith(
          enabledActions: {
            ...state.requireValue.enabledActions,
            modelId: AccountModelEnabledAction(
              binding: binding,
              enabled: enabled,
              action: action,
            ),
          },
        ),
      );
    }

    state = AsyncData(
      state.requireValue.copyWith(
        enabledActions: {
          ...state.requireValue.enabledActions,
          modelId: AccountModelEnabledAction(
            binding: binding,
            enabled: enabled,
            action: SettingsAction(intent: intent, pending: true),
          ),
        },
      ),
    );
    if (!owns()) return;
    _enabledObservations.remove(modelId)?.cancel();
    await _runField(
      () {
        _requireFieldBinding(binding);
        return configuration.setAccountModelEnabled(
          accountId,
          modelId,
          enabled,
        );
      },
      intent,
      owns,
      update,
      (observation) => _enabledObservations[modelId] = observation,
    );
  }

  Future<void> setBillingKind(
    BillingKind? kind,
    AccountFieldBinding binding,
  ) async {
    if (!_canChangeField(binding)) return;
    final previous = state.requireValue.billingAction;
    if (previous != null &&
        previous.binding == binding &&
        (previous.action.uncertain ||
            previous.action.outcome ==
                SettingsActionOutcome.synchronizationFailed ||
            (previous.action.pending && previous.requestedOverride == kind))) {
      return;
    }
    final accountId = _accountId;
    final configuration = _configuration;
    final lifetime = _lifetime;
    final intent = ++_intent;
    bool owns() =>
        _owns(lifetime) &&
        state.requireValue.billingAction?.binding == binding &&
        state.requireValue.billingAction?.action.intent == intent;
    void update(SettingsAction action) {
      if (owns()) {
        state = AsyncData(
          state.requireValue.copyWith(
            billingAction: AccountBillingAction(
              binding: binding,
              requestedOverride: kind,
              action: action,
            ),
          ),
        );
      }
    }

    state = AsyncData(
      state.requireValue.copyWith(
        billingAction: AccountBillingAction(
          binding: binding,
          requestedOverride: kind,
          action: SettingsAction(intent: intent, pending: true),
        ),
      ),
    );
    if (!owns()) return;
    _billingObservation?.cancel();
    _billingObservation = null;
    // null is an automatic-category intent; unknown remains an explicit value.
    await _runField(
      () {
        _requireFieldBinding(binding);
        return configuration.setAccountBillingKind(accountId, kind);
      },
      intent,
      owns,
      update,
      (observation) => _billingObservation = observation,
    );
  }

  Future<void> _runField(
    OperationTicket<Unit> Function() admit,
    int intent,
    bool Function() owns,
    void Function(SettingsAction) update,
    void Function(Observation) retain,
  ) async {
    if (!owns()) return;
    OperationTicket<Unit> ticket;
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
    var action = SettingsAction(intent: intent, pending: true);
    StudioFailure? observationError;
    if (owns()) {
      try {
        final watch = ticket.state.watchLatest((operation) {
          if (owns()) {
            action = action.copyWith(operation: operation);
            update(action);
          }
        });
        if (owns() && _visible && !_sealed) {
          retain(watch.observation);
        } else {
          watch.observation.cancel();
        }
        action = action.copyWith(operation: watch.value);
      } on StudioFailure catch (error) {
        observationError = error;
      }
      action = action.copyWith(observationError: observationError);
      update(action);
    }
    // This await observes accepted Repository work; leaving never cancels it.
    final result = await ticket.result;
    if (!owns()) return;
    action = settledSettingsAction(
      intent,
      result,
      operation: ticket.state.value,
    ).copyWith(observationError: observationError);
    update(action);
  }

  void _requireFieldBinding(AccountFieldBinding binding) {
    if (!_canChangeField(binding)) {
      throw const StudioFailure(
        code: StudioFailureCode.superseded,
        message: 'The original account/model member no longer owns this field intent.',
        retryable: true,
        correlationId: 'settings-account-model-action',
      );
    }
  }

  AccountModelDetailsEntry? openModelDetails(
    String modelId,
    AccountFieldBinding? binding,
  ) {
    if (!_alive ||
        _sealed ||
        !_visible ||
        state.asData == null ||
        state.requireValue.binding != binding ||
        !_hasModel(modelId)) {
      return null;
    }
    return captureModelDetailsEntry(
      AccountModelKey(accountId: _accountId, modelId: modelId),
      state.requireValue.source,
    );
  }

  void _cancelFieldObservations() {
    for (final observation in _enabledObservations.values) {
      observation.cancel();
    }
    _enabledObservations.clear();
    _billingObservation?.cancel();
    _billingObservation = null;
  }

  @override
  void setVisible(bool visible) {
    if (!_alive || _sealed) return;
    _visible = visible;
    if (visible) {
      _registration ??= ref
          .read(applicationEditProducerRegistryProvider)
          .register(this);
    }
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
    _accountRead.target(
      origin == null || reference == null ? null : (origin, reference),
      needed:
          currentCollectionRow(
            config.accounts,
            origin,
            (value) => value.accountId == _accountId,
          ) ==
          null,
    );
    _modelRead.target(
      modelOrigin == null || modelReference == null
          ? null
          : (modelOrigin, modelReference),
      needed:
          currentCollectionRow(
            models.accounts,
            modelOrigin,
            (value) => value.accountId == _accountId,
          ) ==
          null,
    );
    _accountRead.visible(_visible && !_sealed);
    _modelRead.visible(_visible && !_sealed);
  }

  void edit(String modelId, String raw) {
    if (!_alive || _sealed || !_hasModel(modelId)) return;
    _registration ??= ref
        .read(applicationEditProducerRegistryProvider)
        .register(this);
    final current = _draft(modelId);
    if (current.raw == raw && !current.restoreDefault) return;
    _timers.remove(modelId)?.cancel();
    final parsed = _parse(raw);
    final draft = current.copyWith(
      raw: raw,
      intent: ++_intent,
      dirty: true,
      restoreDefault: false,
      validation: parsed == null
          ? ModelLimitValidation.positiveAsciiInteger
          : null,
    );
    _replace(modelId, draft);
    if (parsed != null && !draft.composing) _schedule(modelId);
  }

  void setComposing(String modelId, bool composing) {
    if (!_alive || _sealed || !_hasModel(modelId)) return;
    final draft = _draft(modelId);
    _replace(modelId, draft.copyWith(composing: composing));
    if (composing) {
      _timers.remove(modelId)?.cancel();
    } else if (draft.dirty && draft.validation == null) {
      _schedule(modelId);
    }
  }

  void restoreDefault(String modelId) {
    if (!_alive || _sealed || !_hasModel(modelId)) return;
    _registration ??= ref
        .read(applicationEditProducerRegistryProvider)
        .register(this);
    final previous = _draft(modelId);
    if (previous.restoreDefault &&
        (previous.action?.preventsResubmission ?? false)) {
      return;
    }
    _timers.remove(modelId)?.cancel();
    _replace(
      modelId,
      previous.copyWith(
        raw: '',
        restoreDefault: true,
        composing: false,
        validation: null,
        dirty: true,
        intent: ++_intent,
      ),
    );
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

  @override
  void leave() {
    _visible = false;
    _accountRead.visible(false);
    _modelRead.visible(false);
    _cancelFieldObservations();
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
    _cancelFieldObservations();
    _handoff();
  }

  void _handoff() {
    for (final timer in _timers.values) {
      timer.cancel();
    }
    _timers.clear();
    if (state.asData == null) return;
    for (final modelId in state.requireValue.drafts.keys.toList()) {
      _dispatch(modelId);
    }
  }

  void _dispatch(String modelId) {
    if (!_alive || state.asData == null) return;
    final frozen = _draft(modelId);
    if (!frozen.dirty ||
        frozen.composing ||
        frozen.validation != null ||
        frozen.action?.intent == frozen.intent) {
      return;
    }
    final value = frozen.restoreDefault ? null : _parse(frozen.raw);
    if (!frozen.restoreDefault && value == null) return;
    final lifetime = _lifetime;
    _replace(
      modelId,
      frozen.copyWith(
        action: SettingsAction(intent: frozen.intent, pending: true),
      ),
    );
    OperationTicket<Unit> ticket;
    try {
      ticket = _configuration.saveAccount(
        AccountEdit(
          accountId: _accountId,
          create: false,
          rebuildModelConfiguration: false,
          templateId: const FieldEdit.keep(),
          protocol: const FieldEdit.keep(),
          name: const FieldEdit.keep(),
          baseUrl: const FieldEdit.keep(),
          pricingEnabled: const FieldEdit.keep(),
          secret: const AccountSecretUpdate.preserve(),
          customModels: [],
          connections: [],
          autoCompactLimits: [
            ModelLimitChange(modelId: modelId, overrideLimit: value),
          ],
        ),
      );
    } on StudioFailure catch (error) {
      if (!_owns(lifetime) || _draft(modelId).action?.intent != frozen.intent) {
        return;
      }
      _replace(
        modelId,
        _draft(modelId).copyWith(
          action: SettingsAction(
            intent: frozen.intent,
            outcome: SettingsActionOutcome.rejected,
            error: error,
          ),
        ),
      );
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
        if (!_owns(lifetime) ||
            _draft(modelId).action?.intent != frozen.intent) {
          return;
        }
        final current = _draft(modelId);
        _replace(
          modelId,
          current.copyWith(
            action: current.action?.copyWith(operation: operation),
          ),
        );
      });
      _observations[modelId] = watch.observation;
    } on StudioFailure catch (error) {
      observationError = error;
    }
    _replace(
      modelId,
      _draft(modelId).copyWith(
        action: SettingsAction(
          intent: frozen.intent,
          pending: true,
          operation: ticket.state.value,
          observationError: observationError,
        ),
      ),
    );
    unawaited(
      _settle(modelId, frozen.intent, ticket, lifetime, observationError),
    );
  }

  Future<void> _settle(
    String modelId,
    int intent,
    OperationTicket<Unit> ticket,
    int lifetime,
    StudioFailure? observationError,
  ) async {
    final result = await ticket.result;
    if (!_owns(lifetime) || _draft(modelId).action?.intent != intent) return;
    final current = _draft(modelId);
    _replace(
      modelId,
      current.copyWith(
        action: settledSettingsAction(
          intent,
          result,
          operation: ticket.state.value,
        ).copyWith(observationError: observationError),
      ),
    );
    state = AsyncData(_confirm(state.requireValue));
    _refreshReads();
  }

  AccountModelLimitsViewState _confirm(AccountModelLimitsViewState value) {
    value = value.copyWith(binding: _binding(value));
    final ready = currentCollectionRow(
      value.source.accounts,
      value.source.projection.stamp?.origin,
      (account) => account.accountId == _accountId,
    );
    if (ready == null) return value;
    final drafts = {...value.drafts};
    for (final entry in drafts.entries.toList()) {
      final draft = entry.value;
      final canonical = ready.value.modelAutoCompactLimits
          .where((limit) => limit.modelId == entry.key)
          .firstOrNull
          ?.overrideLimit;
      if (!draft.dirty) {
        if (canonical != _parse(draft.raw)) {
          drafts[entry.key] = draft.copyWith(
            raw: canonical?.toString() ?? '',
            restoreDefault: false,
          );
        }
        continue;
      }
      if (!(draft.action?.succeeded ?? false) ||
          draft.action!.intent != draft.intent) {
        continue;
      }
      final intended = draft.restoreDefault ? null : _parse(draft.raw);
      if (canonical == intended) {
        drafts[entry.key] = draft.copyWith(dirty: false);
      }
    }
    return value.copyWith(drafts: drafts);
  }

  ModelLimitDraft _draft(String modelId) =>
      state.requireValue.drafts[modelId] ??
      ModelLimitDraft(
        raw:
            state.requireValue.canonical.modelAutoCompactLimits
                .where((limit) => limit.modelId == modelId)
                .firstOrNull
                ?.overrideLimit
                ?.toString() ??
            '',
        intent: 0,
      );
  void _replace(String modelId, ModelLimitDraft draft) => state = AsyncData(
    state.requireValue.copyWith(
      drafts: {...state.requireValue.drafts, modelId: draft},
    ),
  );
  static int? _parse(String raw) {
    if (!RegExp(r'^[0-9]+$').hasMatch(raw)) return null;
    final value = int.tryParse(raw);
    return value != null && value > 0 ? value : null;
  }
}
