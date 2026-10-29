import 'dart:async';

import 'package:anywork_client/accounts.dart';
import 'package:anywork_client/model_directory.dart';
import 'package:anywork_client/studio_client.dart'
    show DraftStamp, OperationId, OperationState, OperationPhase, ResourceStamp;
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../../presentation/providers/account_domains.dart';
import '../state/account_presentations.dart';
import '../state/account_view_state.dart';
import 'account_projection.dart';
import 'account_operation_result.dart';
import 'accounts_view_model.dart';

part 'account_models_view_model.g.dart';

final class _CompactDraft {
  _CompactDraft(this.raw, this.revision, this.owner, {this.clearing = false});
  final Object owner;
  final bool clearing;
  final String raw;
  final int revision;
  String? error;
}

final class _ModelAttempt {
  _ModelAttempt(this.owner, this.lifetime, {this.removing = false});
  final Object owner;
  final Ref lifetime;
  final bool removing;
  final observations = <Observation>[];
  OperationId? operationId;
  void Function()? closeRetention;
  bool waiting = true;
  bool terminal = false;
  bool retired = false;

  void closeLocal() {
    for (final observation in observations.toList()) {
      observation.cancel();
    }
    observations.clear();
    closeRetention?.call();
    closeRetention = null;
  }
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
  final Map<String, Object> _compactAttempts = {};
  final Set<String> _compactUncertain = {};
  final Map<String, AccountEvaluationFilter> _evaluationFilters = {};
  final Map<String, String> _errors = {};
  final Set<String> _pending = {};
  final Map<String, _ModelAttempt> _pendingAttempts = {};
  Object _owner = Object();
  String? _ownerEpoch;
  final Map<String, AccountReadoutState> _readouts = {};
  final Map<String, DelegationModelDetail> _performance = {};
  final Map<String, (ResourceStamp?, int?, ResourceStamp?)> _readoutBindings =
      {};
  final Map<String, Object> _readoutTokens = {};
  AccountsViewModel? _accountActions;
  Ref? _accountActionsLifetime;
  String? _syncError;
  bool _syncAdmitting = false;
  AccountDemand? _modelDemand;

  @override
  FutureOr<AccountModelsViewState> build(AccountDisplayKey key) {
    final lifetime = ref;
    if (key.kind != AccountKind.native) {
      throw ArgumentError.value(key, 'key', 'Models require a native account');
    }
    _key = key;
    _identity = NativeAccountIdentity(key.id);
    _models = ref.read(modelsRepositoryProvider);
    _ownerEpoch =
        _models.state.value.accounts[_identity]?.stamp?.ownerEpoch ??
        _models.state.value.configurations[_identity]?.stamp?.ownerEpoch;
    _modelDemand = _models.observeAccount(_identity);
    // Strong listen keeps the unique command owner for this business cycle
    // without watching its AsyncValue. Capture this Ref here, and the owner
    // only when an event arrives, so a queued notification cannot publish on
    // a later Ref or owner epoch.
    ref.listen(
      accountsViewModelProvider,
      (_, _) {
        final ownerAtEvent = _owner;
        Future<void>(() {
          if (!lifetime.mounted) return;
          if (!identical(lifetime, ref) || !identical(ownerAtEvent, _owner)) {
            return;
          }
          _publish();
        });
      },
      weak: false,
      fireImmediately: false,
    );
    _accountActions = ref.read(accountsViewModelProvider.notifier);
    _accountActionsLifetime = lifetime;
    final observation = _models.state.watch((_) => _catalogChanged());
    ref.onDispose(() {
      releaseAccountDemand(_modelDemand);
      observation.cancel();
      if (identical(_accountActionsLifetime, lifetime)) {
        _accountActions = null;
        _accountActionsLifetime = null;
      }
      for (final entry in _pendingAttempts.entries.toList()) {
        if (identical(entry.value.lifetime, lifetime)) {
          _retireCommand(entry.key, entry.value);
        }
      }
    });
    return _derive();
  }

  /// Diagnostic consumers may read existing results; this getter never queries.
  Map<String, DelegationModelDetail> readObservedPerformance() =>
      Map.unmodifiable(_performance);

  /// The actual account route scope owns this finite permit. Covering a page,
  /// opening a model or changing its tab must not release it; scope removal
  /// does. Closing it only releases display retention, never admitted SDK work.
  void Function() retainAccountScope() {
    final retention = ref.keepAlive();
    var released = false;
    return () {
      if (released) return;
      released = true;
      retention.close();
    };
  }

  void setStrings(AccountStrings strings) {
    _strings = strings;
    _publish();
  }

  bool get _ready =>
      _models.state.value.accounts[_identity]?.loaded == true &&
      _models.state.value.configurations[_identity]?.loaded == true &&
      _models.state.value.accounts[_identity]?.stale != true &&
      _models.state.value.configurations[_identity]?.stale != true;

  bool get _deletionBlocked {
    final source = _accountActions;
    final bound = _accountActionsLifetime;
    if (source == null ||
        bound == null ||
        !bound.mounted ||
        !identical(bound, ref)) {
      return true;
    }
    return source.isRemovalBlocked(_key) ||
        _pendingAttempts.entries.any(
          (entry) =>
              entry.value.removing &&
              _ownsCommand(entry.key, entry.value) &&
              _pending.contains(entry.key),
        );
  }

  bool canRemove({required Object expectedToken}) =>
      ref.mounted &&
      matchesCompactLeaveToken(expectedToken) &&
      _ready &&
      !hasCompactDrafts() &&
      !compactLeaveBlocked() &&
      !hasUnconfirmedCompactSave() &&
      _pending.isEmpty &&
      !_syncAdmitting &&
      _models.state.value.accounts[_identity]?.value?.status.probing != true &&
      !_deletionBlocked;
  AccountModelIdentity _model(String id) =>
      AccountModelIdentity(account: _identity, modelId: id);

  Future<void> sync() async {
    if (_deletionBlocked) return;
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

  Future<void> setEnabled(String id, bool enabled) async {
    await _command(id, () => _models.setEnabled(_model(id), enabled));
  }

  Future<void> setConnection(String id, AccountConnection connection) async {
    await _command(
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
  }

  Future<OperationState?> removeManual(
    String id, {
    required Object expectedToken,
  }) => _command(
    id,
    () => _models.removeManual(_model(id)),
    removing: true,
    expectedToken: expectedToken,
  );

  Future<OperationState?> _command(
    String id,
    Future<OperationState> Function() action, {
    bool removing = false,
    Object? expectedToken,
  }) async {
    if (!ref.mounted ||
        !_ready ||
        _deletionBlocked ||
        (removing &&
            (expectedToken == null ||
                !canRemove(expectedToken: expectedToken) ||
                _models.state.value.model(_model(id))?.origin !=
                    ModelOrigin.manual)) ||
        !_pending.add(id)) {
      return null;
    }
    final previous = _pendingAttempts[id];
    if (previous != null) {
      previous.retired = true;
      previous.closeLocal();
    }
    final attempt = _ModelAttempt(_owner, ref, removing: removing);
    if (removing) attempt.closeRetention = ref.keepAlive().close;
    _pendingAttempts[id] = attempt;
    _errors.remove(id);
    _publish();
    OperationState? admittedResult;
    try {
      if (!_ownsCommand(id, attempt)) return null;
      final result = await action();
      admittedResult = result;
      attempt.operationId = result.id;
      if (!_ownsCommand(id, attempt)) return result;
      void apply(OperationState operation) {
        if (!_ownsCommand(id, attempt) || operation.id != attempt.operationId) {
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
          attempt.terminal = true;
        }
        _publish();
        _releaseSettledCommand(id, attempt);
      }

      trackAccountOperation(
        attempt.lifetime,
        result,
        attempt.observations,
        apply,
      );
      if (!removing || result.failurePhase != null) return result;
      // Exactly one settled result for this admission. The Editor consumes it
      // without another operation lookup/settler that could upgrade a failure.
      return await observeAccountOperation(attempt.lifetime, result) ?? result;
    } catch (error) {
      if (_ownsCommand(id, attempt)) {
        _errors[id] = safeAccountError(error, _strings);
        if (!removing || attempt.operationId == null) {
          _pending.remove(id);
          attempt.terminal = true;
        }
      }
      return admittedResult;
    } finally {
      final current = _ownsCommand(id, attempt);
      attempt.waiting = false;
      _releaseSettledCommand(id, attempt);
      if (current &&
          ref.mounted &&
          identical(ref, attempt.lifetime) &&
          identical(_owner, attempt.owner)) {
        _publish();
      }
    }
  }

  bool _ownsCommand(String id, _ModelAttempt attempt) =>
      ref.mounted &&
      attempt.lifetime.mounted &&
      identical(ref, attempt.lifetime) &&
      !attempt.retired &&
      identical(attempt.owner, _owner) &&
      identical(_pendingAttempts[id], attempt);

  void _releaseSettledCommand(String id, _ModelAttempt attempt) {
    if (attempt.retired || (attempt.terminal && !attempt.waiting)) {
      attempt.closeLocal();
      if (!attempt.retired &&
          attempt.removing &&
          _ownsCommand(id, attempt) &&
          _models.state.value.accounts[_identity]?.loaded == true &&
          _models.state.value.model(_model(id)) == null) {
        _pendingAttempts.remove(id);
        _errors.remove(id);
      }
    }
  }

  void _retireCommand(String id, _ModelAttempt attempt) {
    attempt.retired = true;
    attempt.closeLocal();
    if (identical(_pendingAttempts[id], attempt)) {
      _pendingAttempts.remove(id);
      _pending.remove(id);
    }
  }

  void changeCompact(String id, String raw) {
    if (_deletionBlocked || !resourceModelLoaded(id)) return;
    final current = _compact[id];
    // A new keystroke cannot rebase a retired owner's intent implicitly.
    if (current != null && !identical(current.owner, _owner)) return;
    _revision++;
    final baseline =
        _models
            .state
            .value
            .configurations[_identity]
            ?.value
            ?.autoCompactLimits[id]
            ?.toString() ??
        '';
    if (raw == baseline &&
        !_compactAttempts.containsKey(id) &&
        !_compactUncertain.contains(id)) {
      _compact.remove(id);
      _publish();
      return;
    }
    final draft = _CompactDraft(raw, _revision, _owner);
    _compact[id] = draft;
    final parsed = positiveAccountInteger(raw);
    if (parsed == null) {
      draft.error = _strings['positiveInteger'];
    }
    _publish();
  }

  void presetCompact(String id, int percent) {
    if (!const [25, 50, 75, 90].contains(percent)) return;
    final window = _models.state.value.model(_model(id))?.context.contextWindow;
    if (window == null || window <= 0) return;
    final tokens = window * percent ~/ 100;
    if (tokens > 0) changeCompact(id, '$tokens');
  }

  Future<void> saveCompact(String id) async {
    final draft = _compact[id];
    if (draft == null) return;
    final parsed = positiveAccountInteger(draft.raw);
    if (!draft.clearing && parsed == null) return;
    await _saveCompact(
      id,
      draft,
      draft.clearing
          ? const AutoCompactIntent.clear()
          : AutoCompactIntent.set(parsed!),
    );
  }

  bool hasCompactDrafts() => _compact.isNotEmpty;
  bool compactLeaveBlocked() => _compactAttempts.isNotEmpty;
  bool hasUnconfirmedCompactSave() => _compactUncertain.isNotEmpty;
  Object compactLeaveToken() => (_owner, _revision);
  bool matchesCompactLeaveToken(Object token) =>
      ref.mounted && token == compactLeaveToken();
  String? compactLeaveError() => _compact.values
      .map(
        (draft) =>
            !identical(draft.owner, _owner) ? _strings['stale'] : draft.error,
      )
      .whereType<String>()
      .firstOrNull;
  bool canSaveCompactDrafts() =>
      hasCompactDrafts() &&
      _compact.entries.every(
        (entry) => _canSaveCompact(entry.key, entry.value),
      );

  bool _canSaveCompact(String id, _CompactDraft draft) =>
      _ready &&
      !_deletionBlocked &&
      resourceModelLoaded(id) &&
      identical(draft.owner, _owner) &&
      !_compactAttempts.containsKey(id) &&
      !_compactUncertain.contains(id) &&
      (draft.clearing || positiveAccountInteger(draft.raw) != null);

  /// Freeze every revision before leaving; a new edit can never be discarded by
  /// an older completion. Accepted/unknown operations remain domain-owned.
  Future<bool> requestLeaveCompact(AccountLeaveChoice choice) async {
    if (choice == AccountLeaveChoice.cancel) return false;
    if (compactLeaveBlocked()) return false;
    final token = compactLeaveToken();
    final frozen = Map<String, _CompactDraft>.of(_compact);
    if (choice == AccountLeaveChoice.discard) {
      // A replaced/denied navigation must not discard still-visible input.
      // Commit via discardCompactDrafts only when the account scope retires.
      return true;
    }
    if (!canSaveCompactDrafts() && frozen.isNotEmpty) return false;
    for (final entry in frozen.entries) {
      if (token != compactLeaveToken() ||
          !identical(_compact[entry.key], entry.value)) {
        return false;
      }
      await saveCompact(entry.key);
      if (!ref.mounted ||
          token != compactLeaveToken() ||
          _compact.containsKey(entry.key)) {
        return false;
      }
    }
    return !hasCompactDrafts();
  }

  /// Commit an explicit discard only at actual scope removal, using the token
  /// captured by its UI decision. New input/owner/waits invalidate that decision.
  bool discardCompactDrafts(Object token) {
    if (!matchesCompactLeaveToken(token) || compactLeaveBlocked()) return false;
    if (_compact.isEmpty && _compactUncertain.isEmpty) return true;
    _compact.clear();
    _compactUncertain.clear();
    // Actual removal may run inside Widget.dispose. Retire local input now,
    // but notify outside that prohibited lifecycle phase (Riverpod's Future
    // event boundary). This callback never clears input or recreates an owner.
    unawaited(
      Future<void>(() {
        if (!matchesCompactLeaveToken(token) || compactLeaveBlocked()) return;
        _publish();
      }),
    );
    return true;
  }

  Future<void> resetCompact(String id) async {
    if (_deletionBlocked ||
        !_ready ||
        !resourceModelLoaded(id) ||
        (_compact[id] != null && !identical(_compact[id]!.owner, _owner)) ||
        _compactAttempts.containsKey(id) ||
        _compactUncertain.contains(id)) {
      return;
    }
    final draft = _CompactDraft('', ++_revision, _owner, clearing: true);
    _compact[id] = draft;
    await _saveCompact(id, draft, const AutoCompactIntent.clear());
  }

  // A rejected clear retries exactly the same clear intent as leave-and-save.
  Future<void> retryCompact(String id) => saveCompact(id);

  Future<void> _saveCompact(
    String id,
    _CompactDraft draft,
    AutoCompactIntent intent,
  ) async {
    if (!_canSaveCompact(id, draft) || !identical(_compact[id], draft)) {
      return;
    }
    final attempt = Object();
    _compactAttempts[id] = attempt;
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
      if (!ref.mounted || !identical(draft.owner, _owner)) {
        return;
      }
      final result = await observeAccountOperation(ref, operation);
      if (!ref.mounted ||
          result == null ||
          !identical(_compactAttempts[id], attempt) ||
          !identical(draft.owner, _owner)) {
        return;
      }
      draft.error = operationMessage(result, _strings);
      final uncertain =
          result.failurePhase == OperationPhase.unknownOutcome ||
          result.failurePhase == OperationPhase.syncFailed ||
          (result.failurePhase == null && !operationSaved(result));
      if (uncertain) _compactUncertain.add(id);
      if (operationSaved(result) && identical(_compact[id], draft)) {
        _compact.remove(id);
      }
    } catch (error) {
      if (ref.mounted &&
          identical(_compactAttempts[id], attempt) &&
          identical(draft.owner, _owner)) {
        if (identical(_compact[id], draft)) {
          draft.error = safeAccountError(error, _strings);
        }
      }
    } finally {
      // This token tracks the actual local await, not the board's isPending.
      // Catalog refresh/owner retirement must not pretend it already returned.
      if (identical(_compactAttempts[id], attempt)) {
        _compactAttempts.remove(id);
      }
      _publish();
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
      performance: _readouts[id]?.performance,
      guidance: _readouts[id]?.guidance ?? const [],
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
        performance: AccountPerformancePresentation(
          sampleCount: detail.performance.sampleCount,
          ttftSampleCount: detail.performance.ttftSampleCount,
          tokensPerSecond: detail.performance.tokensPerSecond,
          averageTtftMillis: detail.performance.averageTtftMillis,
          updatedLabel: detail.performance.updatedAt == null
              ? null
              : _strings.date(detail.performance.updatedAt),
        ),
        guidance: [
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
              category: AccountEvaluationCategory.values.byName(
                evaluation.taskCategory.name,
              ),
              categoryLabel: _strings['task.${evaluation.taskCategory.name}'],
              outcome: AccountEvaluationOutcome.values.byName(
                evaluation.outcome.name,
              ),
              outcomeLabel: _strings['outcome.${evaluation.outcome.name}'],
              updatedLabel: _strings.date(evaluation.updatedAt),
              updatedAt: evaluation.updatedAt,
              comment: evaluation.comment,
              quality: evaluation.quality,
              instructionFollowing: evaluation.instructionFollowing,
            ),
        ],
      );
    } catch (error) {
      if (ref.mounted && _readoutTokens[id] == token) {
        _readouts[id] = AccountReadoutState(
          phase: AccountReadoutPhase.failed,
          error: safeAccountError(error, _strings),
          performance: _readouts[id]?.performance,
          guidance: _readouts[id]?.guidance ?? const [],
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
        canSync:
            !_deletionBlocked &&
            resource?.loaded == true &&
            status?.supported == true,
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
      canToggle: _ready && !_deletionBlocked,
      saving: _pending.contains(model.modelId),
      error: _errors[model.modelId],
      summary: model.description,
      specificationFacts: AccountModelSpecificationFacts(
        modalityCapabilities: [
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
            AccountDisplayFact(
              label: _strings['capability'],
              value: capability,
            ),
        ],
        context: [
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
        ],
        connection: [
          AccountDisplayFact(label: _strings['modelId'], value: model.modelId),
          AccountDisplayFact(label: _strings['protocol'], value: model.wireApi),
        ],
      ),
      currency: model.currency.isEmpty ? null : model.currency,
      priceSource: model.priceSource.isEmpty ? null : model.priceSource,
      priceVerifiedLabel: model.priceVerifiedAt == null
          ? null
          : _strings.date(model.priceVerifiedAt),
      priceTiers: [
        for (final tier in model.priceTiers)
          AccountModelPriceTier(
            label: tier.label,
            input: tier.input,
            output: tier.output,
            cacheRead: tier.cacheRead,
            cacheWrite: tier.cacheWrite,
          ),
      ],
      performance: readout?.performance,
      guidance: readout?.guidance ?? const [],
      evaluations: readout?.evaluations ?? const [],
      evaluationSummary: _summarizeEvaluations(
        readout?.evaluations ?? const [],
        _evaluationFilters[model.modelId] ?? const AccountEvaluationFilter(),
      ),
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
        error: draft != null && !identical(draft.owner, _owner)
            ? _strings['stale']
            : draft?.error ??
                  (_compactUncertain.contains(model.modelId)
                      ? _strings['unknownOutcome']
                      : null),
        saving: _compactAttempts.containsKey(model.modelId),
        dirty: draft != null,
        contextWindow: model.context.contextWindow,
        adjusted: model.context.adjustment != null,
        canSave: draft != null && _canSaveCompact(model.modelId, draft),
        canEdit:
            _ready &&
            !_deletionBlocked &&
            (draft == null || identical(draft.owner, _owner)),
        canReset:
            _ready &&
            !_deletionBlocked &&
            (override != null || draft != null) &&
            (draft == null || identical(draft.owner, _owner)) &&
            !_compactAttempts.containsKey(model.modelId) &&
            !_compactUncertain.contains(model.modelId),
        canRetry:
            draft?.error != null && _canSaveCompact(model.modelId, draft!),
      ),
      canEdit:
          _ready && !_deletionBlocked && model.origin == ModelOrigin.manual,
      canDelete:
          model.origin == ModelOrigin.manual &&
          canRemove(expectedToken: compactLeaveToken()),
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
    final ownerChanged =
        epoch != null && _ownerEpoch != null && epoch != _ownerEpoch;
    _ownerEpoch = epoch ?? _ownerEpoch;
    if (ownerChanged) {
      for (final entry in _pendingAttempts.entries.toList()) {
        _retireCommand(entry.key, entry.value);
      }
      _owner = Object();
      _pending.clear();
      _pendingAttempts.clear();
      _errors.clear();
      for (final draft in _compact.values) {
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
        performance: old?.performance,
        guidance: old?.guidance ?? const [],
        evaluations: old?.evaluations ?? const [],
      );
    }
    _publish();
  }

  void _publish() {
    if (ref.mounted) state = AsyncData(_derive());
  }

  void filterEvaluations(String id, AccountEvaluationFilter filter) {
    _evaluationFilters[id] = filter;
    _publish();
  }

  AccountEvaluationSummary _summarizeEvaluations(
    List<AccountModelEvaluation> evaluations,
    AccountEvaluationFilter filter,
  ) {
    final window = evaluations.take(10).toList();
    final rated = window.where(
      (item) => item.outcome != AccountEvaluationOutcome.notRated,
    );
    double? average(Iterable<int?> values) {
      final scores = values.whereType<int>().toList();
      return scores.isEmpty
          ? null
          : scores.reduce((a, b) => a + b) / scores.length;
    }

    final visible = window
        .where(
          (item) =>
              (filter.outcome == null || item.outcome == filter.outcome) &&
              (filter.category == null || item.category == filter.category) &&
              (filter.minimumQuality == null ||
                  (item.outcome != AccountEvaluationOutcome.notRated &&
                      item.quality != null &&
                      item.quality! >= filter.minimumQuality!)),
        )
        .toList();
    visible.sort((a, b) {
      final comparison = switch (filter.sort) {
        AccountEvaluationSort.newest => b.updatedAt.compareTo(a.updatedAt),
        AccountEvaluationSort.highestQuality => (b.quality ?? -1).compareTo(
          a.quality ?? -1,
        ),
        AccountEvaluationSort.lowestQuality => (a.quality ?? 6).compareTo(
          b.quality ?? 6,
        ),
      };
      return comparison == 0 ? b.updatedAt.compareTo(a.updatedAt) : comparison;
    });
    return AccountEvaluationSummary(
      count: window.length,
      quality: average(rated.map((item) => item.quality)),
      instructionFollowing: average(
        rated.map((item) => item.instructionFollowing),
      ),
      qualityDistribution: {
        for (var score = 1; score <= 5; score++)
          score: rated.where((item) => item.quality == score).length,
      },
      visible: visible,
      filter: filter,
    );
  }
}
