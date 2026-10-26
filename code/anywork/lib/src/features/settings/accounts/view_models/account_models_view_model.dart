import 'dart:async';

import 'package:anywork_client/accounts.dart';
import 'package:anywork_client/model_directory.dart';
import 'package:anywork_client/studio_client.dart'
    show DraftStamp, OperationState, OperationPhase, ResourceStamp;
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../../presentation/providers/account_domains.dart';
import '../state/account_presentations.dart';
import '../state/account_view_state.dart';
import 'account_projection.dart';
import 'account_operation_result.dart';

part 'account_models_view_model.g.dart';

final class _CompactDraft {
  _CompactDraft(this.raw, this.revision, this.owner, {this.clearing = false});
  final Object owner;
  final bool clearing;
  final String raw;
  final int revision;
  String? error;
  bool saving = false;
  bool uncertain = false;
  Timer? timer;
}

/// Model controls are narrow intents, never part of an account card save.
@riverpod
class AccountModelsViewModel extends _$AccountModelsViewModel {
  late ModelsRepository _models;
  late NativeAccountIdentity _identity;
  late AccountDisplayKey _key;
  AccountStrings _strings = const AccountStrings.empty();
  int _revision = 0;
  final Map<String, _CompactDraft> _compact = {};
  final Map<String, String> _errors = {};
  final Set<String> _pending = {};
  final Map<String, Object> _pendingAttempts = {};
  Object _owner = Object();
  String? _ownerEpoch;
  int? _queryGeneration;
  bool _wasStale = false;
  final Map<String, AccountReadoutState> _readouts = {};
  final Map<String, DelegationModelDetail> _performance = {};
  final Map<String, (ResourceStamp?, int?, ResourceStamp?)> _readoutBindings =
      {};
  final Map<String, Object> _readoutTokens = {};
  final List<Observation> _operations = [];
  String? _syncError;
  bool _syncAdmitting = false;
  AccountDemand? _modelDemand;

  @override
  FutureOr<AccountModelsViewState> build(AccountDisplayKey key) {
    if (key.kind != AccountKind.native) {
      throw ArgumentError.value(key, 'key', 'Models require a native account');
    }
    _key = key;
    _identity = NativeAccountIdentity(key.id);
    _models = ref.read(modelsRepositoryProvider);
    _ownerEpoch =
        _models.state.value.accounts[_identity]?.stamp?.ownerEpoch ??
        _models.state.value.configurations[_identity]?.stamp?.ownerEpoch;
    _queryGeneration =
        _models.state.value.accounts[_identity]?.value?.status.queryGeneration;
    _wasStale =
        _models.state.value.accounts[_identity]?.stale == true ||
        _models.state.value.configurations[_identity]?.stale == true;
    _modelDemand = _models.observeAccount(_identity);
    final observation = _models.state.watch((_) => _catalogChanged());
    ref.onDispose(() {
      releaseAccountDemand(_modelDemand);
      observation.cancel();
      for (final operation in _operations) {
        operation.cancel();
      }
      for (final draft in _compact.values) {
        draft.timer?.cancel();
      }
    });
    return _derive();
  }

  /// Diagnostic consumers may read existing results; this getter never queries.
  Map<String, DelegationModelDetail> readObservedPerformance() =>
      Map.unmodifiable(_performance);
  void setStrings(AccountStrings strings) {
    _strings = strings;
    _publish();
  }

  bool get _ready =>
      _models.state.value.accounts[_identity]?.loaded == true &&
      _models.state.value.configurations[_identity]?.loaded == true;
  AccountModelIdentity _model(String id) =>
      AccountModelIdentity(account: _identity, modelId: id);

  Future<void> sync() async {
    final resource = _models.state.value.accounts[_identity];
    if (resource?.loaded != true) {
      releaseAccountDemand(_modelDemand);
      _modelDemand = _models.observeAccount(_identity);
      return;
    }
    if (resource?.value?.status.supported != true) return;
    if (_syncAdmitting ||
        _models.state.value.accounts[_identity]?.value?.status.probing ==
            true) {
      return;
    }
    _syncAdmitting = true;
    _syncError = null;
    _publish();
    try {
      // Admission is not catalog success; only canonical status ends progress.
      await _models.sync(_identity);
    } catch (error) {
      if (ref.mounted) _syncError = safeAccountError(error, _strings);
    } finally {
      if (ref.mounted) {
        _syncAdmitting = false;
        _publish();
      }
    }
  }

  Future<void> setEnabled(String id, bool enabled) =>
      _command(id, () => _models.setEnabled(_model(id), enabled));
  Future<void> setConnection(String id, AccountConnection connection) =>
      _command(
        id,
        () => _models.setConnection(_model(id), switch (connection) {
          AccountConnection.automatic => const ModelConnectionIntent.clear(),
          AccountConnection.http => const ModelConnectionIntent.set(
            AccountConnectionMode.http,
          ),
          AccountConnection.webSocket => const ModelConnectionIntent.set(
            AccountConnectionMode.webSocket,
          ),
        }),
      );
  Future<void> removeManual(String id) =>
      _command(id, () => _models.removeManual(_model(id)));

  Future<void> _command(
    String id,
    Future<OperationState> Function() action,
  ) async {
    if (!_ready || !_pending.add(id)) return;
    final attempt = Object();
    final owner = _owner;
    _pendingAttempts[id] = attempt;
    _errors.remove(id);
    _publish();
    try {
      if (!identical(owner, _owner) ||
          !identical(_pendingAttempts[id], attempt)) {
        return;
      }
      final result = await action();
      if (!ref.mounted ||
          !identical(owner, _owner) ||
          !identical(_pendingAttempts[id], attempt)) {
        return;
      }
      void apply(OperationState operation) {
        if (!ref.mounted ||
            !identical(owner, _owner) ||
            !identical(_pendingAttempts[id], attempt)) {
          return;
        }
        final message = operationMessage(operation, _strings);
        if (message == null) {
          _errors.remove(id);
        } else {
          _errors[id] = message;
        }
        if (operationSaved(operation) ||
            operation.failurePhase == OperationPhase.rejected) {
          _pending.remove(id);
        }
        _publish();
      }

      trackAccountOperation(ref, result, _operations, apply);
    } catch (error) {
      if (ref.mounted &&
          identical(owner, _owner) &&
          identical(_pendingAttempts[id], attempt)) {
        _errors[id] = safeAccountError(error, _strings);
        _pending.remove(id);
      }
    } finally {
      if (ref.mounted) _publish();
    }
  }

  void changeCompact(String id, String raw) {
    if (_compact[id]?.uncertain == true && _compact[id]?.raw == raw) return;
    _compact[id]?.timer?.cancel();
    final draft = _CompactDraft(raw, ++_revision, _owner);
    _compact[id] = draft;
    final parsed = positiveAccountInteger(raw);
    if (parsed == null) {
      draft.error = _strings['positiveInteger'];
    } else if (_ready) {
      draft.timer = Timer(
        const Duration(milliseconds: 450),
        () => unawaited(_saveCompact(id, draft, AutoCompactIntent.set(parsed))),
      );
    }
    _publish();
  }

  Future<void> resetCompact(String id) async {
    _compact[id]?.timer?.cancel();
    final draft = _CompactDraft('', ++_revision, _owner, clearing: true);
    _compact[id] = draft;
    await _saveCompact(id, draft, const AutoCompactIntent.clear());
  }

  Future<void> retryCompact(String id) async {
    final current = _compact[id];
    if (current == null || current.uncertain) return;
    current.timer?.cancel();
    final parsed = positiveAccountInteger(current.raw);
    if (!current.clearing && parsed == null) return;
    final draft = _CompactDraft(
      current.raw,
      ++_revision,
      _owner,
      clearing: current.clearing,
    );
    _compact[id] = draft;
    await _saveCompact(
      id,
      draft,
      parsed == null
          ? const AutoCompactIntent.clear()
          : AutoCompactIntent.set(parsed),
    );
  }

  Future<void> _saveCompact(
    String id,
    _CompactDraft draft,
    AutoCompactIntent intent,
  ) async {
    if (!_ready ||
        !identical(_compact[id], draft) ||
        !identical(draft.owner, _owner)) {
      return;
    }
    draft.saving = true;
    draft.error = null;
    _publish();
    try {
      if (!identical(draft.owner, _owner)) return;
      final operation = await _models.setAutoCompact(
        _model(id),
        intent,
        draft: DraftStamp(
          draftId: 'compact:${_identity.accountId}:$id',
          revision: draft.revision,
        ),
      );
      if (!ref.mounted ||
          !identical(_compact[id], draft) ||
          !identical(draft.owner, _owner)) {
        return;
      }
      void apply(OperationState result) {
        if (!ref.mounted ||
            !identical(_compact[id], draft) ||
            !identical(draft.owner, _owner)) {
          return;
        }
        draft.error = operationMessage(result, _strings);
        draft.uncertain =
            result.failurePhase == OperationPhase.unknownOutcome ||
            result.failurePhase == OperationPhase.syncFailed;
        draft.saving = result.failurePhase == null && !operationSaved(result);
        if (operationSaved(result)) _compact.remove(id);
        _publish();
      }

      trackAccountOperation(ref, operation, _operations, apply);
    } catch (error) {
      if (ref.mounted &&
          identical(_compact[id], draft) &&
          identical(draft.owner, _owner)) {
        draft.error = safeAccountError(error, _strings);
        draft.saving = false;
        _publish();
      }
    }
  }

  Future<void> loadReadout(String id) async {
    if (!resourceModelLoaded(id)) return;
    if (_readouts[id]?.phase == AccountReadoutPhase.loading) return;
    if (_readouts.length >= 16 && !_readouts.containsKey(id)) {
      final expired = _readouts.keys.firstWhere(
        (key) => _readouts[key]?.phase != AccountReadoutPhase.loading,
        orElse: () => '',
      );
      if (expired.isEmpty) return;
      _readouts.remove(expired);
      _performance.remove(expired);
      _readoutBindings.remove(expired);
      _readoutTokens.remove(expired);
    }
    final token = Object();
    _readoutTokens[id] = token;
    _readoutBindings[id] = _readoutBinding();
    _readouts[id] = AccountReadoutState(
      phase: AccountReadoutPhase.loading,
      performance: _readouts[id]?.performance ?? const [],
      evaluations: _readouts[id]?.evaluations ?? const [],
    );
    _publish();
    try {
      final detail = await _models.performance(_model(id));
      if (!ref.mounted ||
          _readoutTokens[id] != token ||
          _readoutBindings[id] != _readoutBinding()) {
        return;
      }
      _performance[id] = detail;
      final evaluations = [...detail.recentEvaluations]
        ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      _readouts[id] = AccountReadoutState(
        phase: AccountReadoutPhase.ready,
        performance: [
          AccountDisplayFact(
            label: _strings['samples'],
            value: '${detail.performance.sampleCount}',
          ),
          if (detail.performance.tokensPerSecond case final speed?)
            AccountDisplayFact(
              label: _strings['speed'],
              value: speed.toStringAsFixed(1),
            ),
          if (detail.performance.averageTtftMillis case final ttft?)
            AccountDisplayFact(
              label: _strings['ttft'],
              value: ttft.toStringAsFixed(0),
            ),
          if (detail.guide case final guide?)
            AccountDisplayFact(label: _strings['guide'], value: guide.summary),
          for (final limitation
              in detail.guide?.limitations ?? const <String>[])
            AccountDisplayFact(
              label: _strings['limitations'],
              value: limitation,
            ),
          for (final source in detail.guide?.sources ?? const [])
            AccountDisplayFact(
              label: _strings['sources'],
              value: '${source.url} · ${_strings.date(source.verifiedAt)}',
            ),
        ],
        evaluations: [
          for (final evaluation in evaluations.take(10))
            AccountModelEvaluation(
              title: _strings['task.${evaluation.taskCategory.name}'],
              outcome: _strings['outcome.${evaluation.outcome.name}'],
              updatedLabel: _strings.date(evaluation.updatedAt),
              comment: evaluation.comment,
              scores: [
                if (evaluation.quality case final quality?)
                  AccountDisplayFact(
                    label: _strings['quality'],
                    value: '$quality',
                  ),
                if (evaluation.instructionFollowing case final following?)
                  AccountDisplayFact(
                    label: _strings['following'],
                    value: '$following',
                  ),
              ],
            ),
        ],
      );
    } catch (error) {
      if (ref.mounted && _readoutTokens[id] == token) {
        _readouts[id] = AccountReadoutState(
          phase: AccountReadoutPhase.failed,
          error: safeAccountError(error, _strings),
          performance: _readouts[id]?.performance ?? const [],
          evaluations: _readouts[id]?.evaluations ?? const [],
        );
      }
    } finally {
      if (ref.mounted) _publish();
    }
  }

  AccountModelsViewState _derive() {
    final resource = _models.state.value.accounts[_identity];
    final configuration = _models.state.value.configurations[_identity];
    final status = resource?.value?.status;
    return AccountModelsViewState(
      stale: resource?.stale == true || configuration?.stale == true,
      readouts: Map.of(_readouts),
      catalog: AccountCatalogPresentation(
        models: [
          for (final model
              in resource?.value?.models ?? const <AccountModelView>[])
            _projectModel(model, configuration?.value),
        ],
        canSync: resource?.loaded == true && status?.supported == true,
        syncing:
            _syncAdmitting ||
            status?.probing == true ||
            (resource?.stamp == null && resource?.failure == null),
        canRetry:
            (status?.supported == true && status?.error != null) ||
            _syncError != null ||
            resource?.failure != null,
        checkedLabel: status?.checkedAt == null
            ? null
            : _strings.date(status?.checkedAt),
        sourceLabel: status == null
            ? null
            : _strings['source.${status.source.name}'],
        error: resource?.stale == true || configuration?.stale == true
            ? _strings['stale']
            : _syncError ??
                  resource?.failure?.message ??
                  configuration?.failure?.message ??
                  (status?.error == null ? null : _strings['catalogFailed']),
      ),
    );
  }

  AccountModelPresentation _projectModel(
    AccountModelView model,
    AccountModelConfiguration? configuration,
  ) {
    final draft = _compact[model.modelId];
    final readout = _readouts[model.modelId];
    final override = configuration?.autoCompactLimits[model.modelId];
    final connection = configuration?.connections[model.modelId];
    return AccountModelPresentation(
      key: AccountModelKey(account: _key, modelId: model.modelId),
      name: model.displayName,
      origin: switch (model.origin) {
        ModelOrigin.bundled => AccountModelOrigin.bundled,
        ModelOrigin.online => AccountModelOrigin.online,
        ModelOrigin.manual => AccountModelOrigin.manual,
      },
      enabled: model.enabled,
      canToggle: _ready,
      saving: _pending.contains(model.modelId),
      error: _errors[model.modelId],
      summary: model.description,
      capabilities: [
        AccountDisplayFact(label: _strings['modelId'], value: model.modelId),
        AccountDisplayFact(label: _strings['protocol'], value: model.wireApi),
        if (model.context.contextWindow case final window?)
          AccountDisplayFact(label: _strings['context'], value: '$window'),
        if (model.maxContextWindow case final window?)
          AccountDisplayFact(label: _strings['maxContext'], value: '$window'),
        if (model.context.inputTokenLimit case final input?)
          AccountDisplayFact(label: _strings['inputBudget'], value: '$input'),
        if (model.context.unavailable case final unavailable?)
          AccountDisplayFact(
            label: _strings['context'],
            value: _strings['contextUnavailable.${unavailable.name}'],
          ),
        if (model.maxOutputTokens case final output?)
          AccountDisplayFact(label: _strings['output'], value: '$output'),
        if (model.reasoningEfforts.isNotEmpty)
          AccountDisplayFact(
            label: _strings['efforts'],
            value: model.reasoningEfforts.join(' / '),
          ),
        for (final input in model.inputCapabilities)
          AccountDisplayFact(
            label: '${_strings['capability']} · ${input.modality.name}',
            value: input.sources.map((source) => source.name).join(' / '),
          ),
        if (model.outputModalities.isNotEmpty)
          AccountDisplayFact(
            label: _strings['outputModalities'],
            value: model.outputModalities
                .map((modality) => modality.name)
                .join(' / '),
          ),
        for (final capability in model.capabilities)
          AccountDisplayFact(label: _strings['capability'], value: capability),
      ],
      priceTiers: [
        if (model.priceSource.isNotEmpty)
          AccountDisplayFact(
            label: _strings['sources'],
            value: model.priceSource,
          ),
        if (model.priceVerifiedAt != null)
          AccountDisplayFact(
            label: _strings['verified'],
            value: _strings.date(model.priceVerifiedAt),
          ),
        for (final tier in model.priceTiers)
          AccountDisplayFact(
            label: tier.label,
            value:
                '${model.currency} · ${_strings['inputPrice']} ${tier.input} · ${_strings['outputPrice']} ${tier.output}${tier.cacheRead == null ? '' : ' · ${_strings['cacheReadPrice']} ${tier.cacheRead}'}${tier.cacheWrite == null ? '' : ' · ${_strings['cacheWritePrice']} ${tier.cacheWrite}'}',
          ),
      ],
      performance: readout?.performance ?? const [],
      evaluations: readout?.evaluations ?? const [],
      readoutLoading: readout?.phase == AccountReadoutPhase.loading,
      readoutError: readout?.error,
      canLoadReadout: resourceModelLoaded(model.modelId),
      connection: switch (connection) {
        null => AccountConnection.automatic,
        AccountConnectionMode.http => AccountConnection.http,
        AccountConnectionMode.webSocket => AccountConnection.webSocket,
      },
      allowedConnections: [
        AccountConnection.automatic,
        for (final mode in model.supportedConnectionModes)
          if (mode == 'http')
            AccountConnection.http
          else if (mode == 'web_socket')
            AccountConnection.webSocket,
      ],
      compact: AccountCompactPresentation(
        raw: draft?.raw ?? override?.toString() ?? '',
        overridden: override != null,
        effective: model.context.autoCompactLimit?.toString(),
        automatic: override == null
            ? model.context.autoCompactLimit?.toString()
            : null,
        error: draft?.error,
        saving: draft?.saving ?? false,
        canEdit: _ready,
        canReset: _ready && (override != null || draft != null),
        canRetry:
            _ready &&
            draft?.error != null &&
            !draft!.uncertain &&
            (draft.clearing || positiveAccountInteger(draft.raw) != null),
      ),
      canEdit: _ready && model.origin == ModelOrigin.manual,
      canDelete: _ready && model.origin == ModelOrigin.manual,
    );
  }

  bool resourceModelLoaded(String id) =>
      _models.state.value.accounts[_identity]?.loaded == true &&
      _models.state.value.model(_model(id)) != null;

  (ResourceStamp?, int?, ResourceStamp?) _readoutBinding() => (
    _models.state.value.accounts[_identity]?.stamp,
    _models.state.value.accounts[_identity]?.value?.status.queryGeneration,
    _models.state.value.configurations[_identity]?.stamp,
  );
  void _catalogChanged() {
    final resource = _models.state.value.accounts[_identity];
    final configuration = _models.state.value.configurations[_identity];
    final epoch =
        resource?.stamp?.ownerEpoch ?? configuration?.stamp?.ownerEpoch;
    final generation = resource?.value?.status.queryGeneration;
    final stale = resource?.stale == true || configuration?.stale == true;
    final changed =
        (stale && !_wasStale) ||
        (epoch != null && epoch != _ownerEpoch) ||
        (generation != null && generation != _queryGeneration);
    _wasStale = stale;
    _ownerEpoch = epoch ?? _ownerEpoch;
    _queryGeneration = generation ?? _queryGeneration;
    if (changed) {
      _owner = Object();
      _pending.clear();
      _pendingAttempts.clear();
      _errors.clear();
      for (final observation in _operations) {
        observation.cancel();
      }
      _operations.clear();
      for (final draft in _compact.values) {
        draft.timer?.cancel();
        draft.saving = false;
        draft.error = _strings['stale'];
      }
    }
    for (final id in _readoutBindings.keys.toList()) {
      if (_readoutBindings[id] == _readoutBinding() &&
          resourceModelLoaded(id)) {
        continue;
      }
      _readoutTokens.remove(id);
      _performance.remove(id);
      final old = _readouts[id];
      _readouts[id] = AccountReadoutState(
        phase: AccountReadoutPhase.failed,
        error: _strings['stale'],
        performance: old?.performance ?? const [],
        evaluations: old?.evaluations ?? const [],
      );
    }
    _publish();
  }

  void _publish() {
    if (ref.mounted) state = AsyncData(_derive());
  }
}
