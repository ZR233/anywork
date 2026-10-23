import 'dart:async';

import 'package:anywork_client/account_usage.dart';
import 'package:anywork_client/configuration.dart';
import 'package:anywork_client/models.dart';
import 'package:anywork_client/operations.dart';
import 'package:anywork_client/resources.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../../app/app_bindings.dart';
import '../../state/editor_keys.dart';
import '../../state/settings_action.dart';
import '../../state/settings_navigation_state.dart';
import '../../view_models/collection_values.dart';
import '../../view_models/read_values.dart';
import '../../view_models/settings_navigation_view_model.dart';
import '../../view_models/settings_tab_lifecycle.dart';
import '../state/accounts_state.dart';
import 'account_detail_participant.dart';
import 'account_usage_checks.dart';
import 'accounts_visible_reads.dart';

part 'accounts_view_model.g.dart';

@Riverpod(keepAlive: true)
class AccountsViewModel extends _$AccountsViewModel {
  late ConfigurationRepository _configuration;
  late ModelsRepository _models;
  late AccountUsageRepository _usage;
  late AccountsVisibleReads _reads;
  final _observations = <Observation>[];
  final _rowObservations = <(String, AccountRowAction), Observation>{};
  final _modelObservations = <(String, String), Observation>{};
  AccountUsageChecks? _usageChecks;
  int _lifetime = 0;
  int _editorId = 0;
  bool _alive = true;
  bool _visible = true;
  Set<String> _visibleUsage = const {};
  AccountDetailParticipant? _detail;
  String? _detailAccountId;

  bool detailRequested(String accountId) => _alive && _visible && state.asData?.value.showDetails == true &&
    state.requireValue.selectedAccountId == accountId && state.requireValue.editor == null;

  void Function() attachDetail(String accountId, AccountDetailParticipant detail) {
    if (_detail != null && !identical(_detail, detail)) _detail!.endEditing();
    _detailAccountId = accountId;
    _detail = detail;
    return () {
      if (identical(_detail, detail)) { _detail = null; _detailAccountId = null; }
    };
  }

  void _endDetail() {
    final detail = _detail;
    _detail = null;
    _detailAccountId = null;
    detail?.endEditing();
  }

  @override
  Future<AccountsViewState> build() async {
    _alive = true;
    final lifetime = ++_lifetime;
    _configuration = ref.watch(configurationRepositoryProvider);
    _models = ref.watch(modelsRepositoryProvider);
    _usage = ref.watch(accountUsageRepositoryProvider);
    _reads = AccountsVisibleReads(_configuration, _models, _usage, (field, error, current, reading) {
      if (!_owns(lifetime)) return;
      final issues = {...state.requireValue.readIssues};
      if (current) {
        if (error == null) { issues.remove(field); } else { issues[field] = error; }
      }
      final fields = {...state.requireValue.reading};
      if (reading) { fields.add(field); } else { fields.remove(field); }
      state = AsyncData(state.requireValue.copyWith(readIssues: issues, reading: fields));
    }, (templates) {
      if (_owns(lifetime)) state = AsyncData(state.requireValue.copyWith(templates: templates));
    });
    final tab = ref.read(settingsNavigationViewModelProvider.notifier).register(SettingsTab.accounts,
      SettingsTabLifecycle(visibility: setVisible));
    _visible = tab.visible;
    ref.onDispose(() {
      _alive = false;
      _lifetime++;
      _reads.dispose();
      _usageChecks?.dispose();
      tab.unregister();
      for (final observation in _observations) { observation.cancel(); }
      _observations.clear();
      for (final observation in [..._rowObservations.values, ..._modelObservations.values]) {
        observation.cancel();
      }
      _rowObservations.clear(); _modelObservations.clear();
      // Repository, accepted checks and writes outlive their display observer.
    });
    _observations.add(_configuration.state.watchLatest((source) {
      if (!_owns(lifetime)) return;
      _publish(state.requireValue.copyWith(source: source));
    }).observation);
    _observations.add(_models.state.watchLatest((source) {
      if (_owns(lifetime)) _publish(state.requireValue.copyWith(modelSource: source));
    }).observation);
    _observations.add(_models.templates.watchLatest((source) {
      if (_owns(lifetime)) _publish(state.requireValue.copyWith(templateSource: source));
    }).observation);
    _observations.add(_usage.state.watchLatest((source) {
      if (_owns(lifetime)) _publish(state.requireValue.copyWith(usageSource: source));
    }).observation);
    _usageChecks = AccountUsageChecks(_configuration, _usage, (checks) {
      if (_owns(lifetime)) state = AsyncData(state.requireValue.copyWith(usageChecks: checks));
    });
    final errors = <AccountsReadField, StudioFailure>{};
    AccountTemplatesValue? templates;
    Future<void> read(AccountsReadField field, Future<void> Function() action) async {
      try { await action(); } on StudioFailure catch (error) { errors[field] = error; }
    }
    await Future.wait<void>([
      read(AccountsReadField.accounts, () => _configuration.loadAccountsPage()),
      read(AccountsReadField.models, () => _models.loadAccountsPage()),
      read(AccountsReadField.templates, () async { templates = await _models.loadTemplates(); }),
      read(AccountsReadField.defaultAccount, () async { await _configuration.loadDefaultAccountId(); }),
      read(AccountsReadField.usage, () => _usage.loadRecordsPage()),
      read(AccountsReadField.configurationSource, _configuration.loadSourceStatus),
      read(AccountsReadField.modelSource, _models.loadSourceStatus),
      read(AccountsReadField.usageSource, _usage.loadSourceStatus),
    ]);
    _reads.rememberInitialFailures();
    _usageChecks!.refresh();
    final initial = _filter(AccountsViewState(source: _configuration.state.value,
      modelSource: _models.state.value, templateSource: _models.templates.value,
      usageSource: _usage.state.value, templates: templates, readIssues: errors, usageChecks: _usageChecks!.snapshot));
    Future<void>(() { if (_owns(lifetime)) _publish(state.requireValue); });
    return initial;
  }

  bool _owns(int lifetime) => _alive && lifetime == _lifetime && state.asData != null;

  void _publish(AccountsViewState value) {
    final lifetime = _lifetime;
    state = AsyncData(_filter(value));
    if (!_owns(lifetime)) return;
    _reads.visible(_visible);
    if (!_owns(lifetime)) return;
    final current = state.requireValue;
    final ids = !_visible || current.editor != null ? <String>{} : current.showDetails
      ? {if (current.selectedAccountId case final id?) id} : current.matchingAccountIds.toSet();
    _usageChecks?.visibleAccounts(ids);
    if (!_owns(lifetime)) return;
    final latest = state.requireValue;
    final latestIds = !_visible || latest.editor != null ? <String>{} : latest.showDetails
      ? {if (latest.selectedAccountId case final id?) id} : latest.matchingAccountIds.toSet();
    if (ids.length != latestIds.length || !ids.containsAll(latestIds)) return;
    if (ids.length == _visibleUsage.length && ids.containsAll(_visibleUsage)) return;
    _visibleUsage = Set.unmodifiable(ids);
    try { _usage.setVisibleAccounts(ids); }
    on StudioFailure catch (error) {
      state = AsyncData(state.requireValue.copyWith(readIssues: {
        ...state.requireValue.readIssues, AccountsReadField.usage: error}));
    }
  }

  AccountsViewState _filter(AccountsViewState value) {
    final query = value.query.trim().toLowerCase();
    final accounts = displayCollectionRows(value.source.accounts);
    final catalogs = displayCollectionRows(value.modelSource.accounts);
    final matching = [for (final account in accounts)
      if (query.isEmpty || [account.accountId, account.name,
        for (final catalog in catalogs.where((item) => item.accountId == account.accountId)) ...[
          catalog.defaultModelId,
          for (final model in catalog.effectiveModels) ...[model.modelId, model.displayName,
            model.transport.protocol, model.transport.defaultConnectionMode],
        ],
      ].join(' ').toLowerCase().contains(query)) account.accountId];
    final complete = collectionComplete(value.source.accounts, value.source.projection.stamp?.origin);
    final selected = value.selectedAccountId;
    if (selected != null && complete && !accounts.any((item) => item.accountId == selected) && value.editor == null) {
      return value.copyWith(matchingAccountIds: matching, selectedAccountId: accounts.firstOrNull?.accountId, showDetails: false);
    }
    return value.copyWith(matchingAccountIds: matching);
  }

  void setVisible(bool value) {
    if (!_alive) return;
    if (!value) _detail?.leave();
    _visible = value;
    if (value && state.asData?.value.showDetails == true && _detailAccountId == state.requireValue.selectedAccountId)
      _detail?.setVisible(true);
    if (state.asData != null) _publish(state.requireValue);
  }
  void setQuery(String value) { if (_alive) _publish(state.requireValue.copyWith(query: value)); }
  void select(String id) {
    if (!_alive || !displayCollectionRows(state.requireValue.source.accounts).any((item) => item.accountId == id)) return;
    if (_detailAccountId != id) _endDetail();
    _publish(state.requireValue.copyWith(selectedAccountId: id, showDetails: true,
      navigationIntent: state.requireValue.navigationIntent + 1));
  }
  void showList() {
    if (!_alive) return;
    _endDetail();
    _publish(state.requireValue.copyWith(showDetails: false, navigationIntent: state.requireValue.navigationIntent + 1));
  }
  void retryRead() {
    if (!_alive || !_visible) return;
    _usageChecks?.refresh(retryObservations: true);
    _reads.retry();
    // A failed initial open has no origin/ref for a demand key. Explicit retry
    // can bootstrap that source without invalidating an editor's raw state.
    if (_configuration.state.value.projection.header?.reference == null) {
      unawaited(_page(AccountsReadField.accounts, () => _configuration.loadAccountsPage()));
      unawaited(_page(AccountsReadField.defaultAccount, () async { await _configuration.loadDefaultAccountId(); }));
      unawaited(_page(AccountsReadField.configurationSource, _configuration.loadSourceStatus));
    }
    if (_models.state.value.projection.header?.reference == null) {
      unawaited(_page(AccountsReadField.models, () => _models.loadAccountsPage()));
      unawaited(_page(AccountsReadField.modelSource, _models.loadSourceStatus));
    }
    if (_models.templates.value.projection.header == null) unawaited(_page(AccountsReadField.templates, () async {
      final lifetime = _lifetime;
      final templates = await _models.loadTemplates();
      if (_owns(lifetime)) state = AsyncData(state.requireValue.copyWith(templates: templates));
    }));
    if (_usage.state.value.projection.header?.reference == null) {
      unawaited(_page(AccountsReadField.usage, () => _usage.loadRecordsPage()));
      unawaited(_page(AccountsReadField.usageSource, _usage.loadSourceStatus));
    }
  }

  Future<void> loadMore() async {
    if (!_alive || !_visible) return;
    await Future.wait<void>([
      _page(AccountsReadField.accounts, () => _configuration.loadAccountsPage()),
      _page(AccountsReadField.models, () => _models.loadAccountsPage()),
      _page(AccountsReadField.usage, () => _usage.loadRecordsPage()),
    ]);
  }
  Future<void> _page(AccountsReadField field, Future<void> Function() read) async {
    final lifetime = _lifetime;
    if (state.requireValue.reading.contains(field)) return;
    state = AsyncData(state.requireValue.copyWith(reading: {...state.requireValue.reading, field}));
    StudioFailure? issue;
    try { await read(); } on StudioFailure catch (error) { issue = error; }
    if (!_owns(lifetime)) return;
    final errors = {...state.requireValue.readIssues};
    if (issue == null) { errors.remove(field); } else { errors[field] = issue; }
    _publish(state.requireValue.copyWith(reading: {...state.requireValue.reading}..remove(field), readIssues: errors));
  }

  Future<void> startCreate() async {
    if (!_alive || state.requireValue.editor != null) return;
    _endDetail();
    final lifetime = _lifetime;
    final navigation = state.requireValue.navigationIntent + 1;
    state = AsyncData(state.requireValue.copyWith(navigationIntent: navigation, editorError: null));
    // A stable human-readable ID is based on the complete current account set,
    // not the visible page. Each await explicitly asks for one bounded page.
    try {
      while (!collectionComplete(_configuration.state.value.accounts, _configuration.state.value.projection.stamp?.origin)) {
        await _configuration.loadAccountsPage();
        if (!_owns(lifetime) || state.requireValue.navigationIntent != navigation) return;
      }
      final templates = state.requireValue.templates ?? await _models.loadTemplates();
      if (!_owns(lifetime) || state.requireValue.navigationIntent != navigation) return;
      final template = templates.templates.firstOrNull;
      if (template == null) throw _failure(StudioFailureCode.unavailable, 'Account template catalog is unavailable.');
      final ids = displayCollectionRows(_configuration.state.value.accounts).map((item) => item.accountId).toSet();
      var id = template.id;
      for (var index = 2; ids.contains(id); index++) { id = '${template.id}-$index'; }
      _publish(state.requireValue.copyWith(templates: templates, editorAccountId: id,
        editor: AccountEditorKey(editorId: ++_editorId, initialTemplateId: template.id), showDetails: false));
    } on StudioFailure catch (error) {
      if (_owns(lifetime) && state.requireValue.navigationIntent == navigation)
        state = AsyncData(state.requireValue.copyWith(editorError: error));
    }
  }

  void startEdit(String id) {
    if (!_alive || state.requireValue.editor != null) return;
    _endDetail();
    _publish(state.requireValue.copyWith(selectedAccountId: id, editorAccountId: id, showDetails: false,
      navigationIntent: state.requireValue.navigationIntent + 1, editorError: null,
      editor: AccountEditorKey(editorId: ++_editorId, accountId: id)));
  }
  String accountIdForEditor(AccountEditorKey key) {
    final value = state.requireValue;
    if (value.editor != key || value.editorAccountId == null)
      throw _failure(StudioFailureCode.superseded, 'Account editor no longer owns this target.');
    return value.editorAccountId!;
  }
  void closeEditor(AccountEditorKey key, {bool saved = false}) {
    if (!_alive || state.requireValue.editor != key) return;
    _publish(state.requireValue.copyWith(editor: null, editorAccountId: null, showDetails: false,
      selectedAccountId: saved ? state.requireValue.editorAccountId : state.requireValue.selectedAccountId,
      navigationIntent: state.requireValue.navigationIntent + 1));
  }

  Future<void> setDefault(String id) => _row(id, AccountRowAction.setDefault,
    () => _configuration.setDefaultAccount(id));

  Future<void> remove(String id) async {
    if (!_alive || state.requireValue.preparingRemovalIds.contains(id) ||
        (state.requireValue.rowActions[(id, AccountRowAction.remove)]?.preventsResubmission ?? false)) return;
    final lifetime = _lifetime;
    state = AsyncData(state.requireValue.copyWith(preparingRemovalIds: {...state.requireValue.preparingRemovalIds, id}));
    try {
      var source = _configuration.state.value;
      if (!isCurrentRead(source.defaultAccountId, source.projection.header?.reference, source.projection.stamp?.origin)) {
        await _configuration.loadDefaultAccountId();
        if (!_owns(lifetime)) return;
        source = _configuration.state.value;
    }
      var defaultId = displayReadValue(source.defaultAccountId);
      var replacement = defaultId == id ? displayCollectionRows(source.accounts)
        .where((item) => item.accountId != id).firstOrNull?.accountId : defaultId;
      if (defaultId == id && replacement == null) {
        await _configuration.loadAccountsPage();
        if (!_owns(lifetime)) return;
        source = _configuration.state.value;
        if (!isCurrentRead(source.defaultAccountId, source.projection.header?.reference, source.projection.stamp?.origin))
          throw _failure(StudioFailureCode.superseded, 'Default account changed while choosing a replacement.');
        defaultId = displayReadValue(source.defaultAccountId);
        replacement = defaultId == id ? displayCollectionRows(source.accounts)
          .where((item) => item.accountId != id).firstOrNull?.accountId : defaultId;
      }
      final current = source.accounts;
      if (current is! CurrentCollectionMirror<AccountConfiguration> || current.window.reference.total <= 1) return;
      if (defaultId == id && replacement == null)
        throw _failure(StudioFailureCode.unavailable, 'A replacement account has not been materialized.');
    await _row(id, AccountRowAction.remove, () => _configuration.removeAccount(id, replacementAccountId: replacement));
    } on StudioFailure catch (error) {
      if (_owns(lifetime)) state = AsyncData(state.requireValue.copyWith(readIssues: {
        ...state.requireValue.readIssues, AccountsReadField.accounts: error}));
    } finally {
      if (_owns(lifetime)) state = AsyncData(state.requireValue.copyWith(
        preparingRemovalIds: {...state.requireValue.preparingRemovalIds}..remove(id)));
    }
  }

  Future<void> _row(String id, AccountRowAction field, OperationTicket<Unit> Function() admit) async {
    if (!_alive || (state.requireValue.rowActions[(id, field)]?.preventsResubmission ?? false)) return;
    final lifetime = _lifetime;
    final intent = state.requireValue.latestIntent + 1;
    state = AsyncData(state.requireValue.copyWith(latestIntent: intent, rowActions: {
      ...state.requireValue.rowActions, (id, field): SettingsAction(intent: intent, pending: true)}));
    bool owns() => _owns(lifetime) && state.requireValue.rowActions[(id, field)]?.intent == intent;
    void update(SettingsAction action) {
      if (owns()) state = AsyncData(state.requireValue.copyWith(rowActions: {...state.requireValue.rowActions, (id, field): action}));
    }
    _rowObservations.remove((id, field))?.cancel();
    await _run<Unit>(admit, intent, owns, update, (observation) => _rowObservations[(id, field)] = observation);
  }

  Future<void> removeModel(String accountId, String modelId) async {
    if (!_alive) return;
    final catalog = currentCollectionRow(_models.state.value.accounts, _models.state.value.projection.stamp?.origin,
      (item) => item.accountId == accountId)?.value;
    if (catalog == null || !catalog.effectiveModels.any((model) => model.modelId == modelId && model.origin == ModelOrigin.manual)) return;
    final key = (accountId, modelId);
    if (state.requireValue.modelActions[key]?.preventsResubmission ?? false) return;
    final lifetime = _lifetime;
    final intent = state.requireValue.latestIntent + 1;
    state = AsyncData(state.requireValue.copyWith(latestIntent: intent, modelActions: {
      ...state.requireValue.modelActions, key: SettingsAction(intent: intent, pending: true)}));
    bool owns() => _owns(lifetime) && state.requireValue.modelActions[key]?.intent == intent;
    _modelObservations.remove(key)?.cancel();
    await _run<Unit>(() => _configuration.removeAccountModel(accountId, modelId), intent, owns, (action) {
      if (owns()) state = AsyncData(state.requireValue.copyWith(modelActions: {...state.requireValue.modelActions, key: action}));
    }, (observation) => _modelObservations[key] = observation);
  }

  Future<void> refreshUsage([String? accountId]) async {
    if (!_alive) return;
    if (accountId != null) { await _check(accountId); return; }
    if (state.requireValue.refreshingAll) return;
    final lifetime = _lifetime;
    state = AsyncData(state.requireValue.copyWith(refreshingAll: true));
    try {
      while (!collectionComplete(_configuration.state.value.accounts, _configuration.state.value.projection.stamp?.origin)) {
        await _configuration.loadAccountsPage();
        if (!_owns(lifetime)) return;
      }
      final ids = displayCollectionRows(_configuration.state.value.accounts).map((item) => item.accountId).toList();
    await Future.wait<void>([for (final id in ids) _check(id)]);
    } on StudioFailure catch (error) {
      if (_owns(lifetime)) state = AsyncData(state.requireValue.copyWith(readIssues: {
        ...state.requireValue.readIssues, AccountsReadField.accounts: error}));
    } finally {
      if (_owns(lifetime)) state = AsyncData(state.requireValue.copyWith(refreshingAll: false));
    }
  }
  Future<void> _check(String id) async {
    if (!_alive || (state.requireValue.usageActions[id]?.pending ?? false)) return;
    final lifetime = _lifetime;
    final usage = _usage;
    final intent = state.requireValue.latestIntent + 1;
    state = AsyncData(state.requireValue.copyWith(latestIntent: intent, usageActions: {
      ...state.requireValue.usageActions, id: SettingsAction(intent: intent, pending: true)}));
    bool owns() => _owns(lifetime) && state.requireValue.usageActions[id]?.intent == intent;
    if (!owns()) return;
    OperationTicket<AccountUsageRecord> ticket;
    try { ticket = usage.check(id); }
    on StudioFailure catch (error) {
      if (owns()) state = AsyncData(state.requireValue.copyWith(usageActions: {...state.requireValue.usageActions,
        id: SettingsAction(intent: intent, outcome: SettingsActionOutcome.rejected, error: error)},
        usageActionIds: {...state.requireValue.usageActionIds}..remove(id)));
      return;
  }
    if (owns()) {
      state = AsyncData(state.requireValue.copyWith(usageActionIds: {...state.requireValue.usageActionIds, id: ticket.state.value.id},
        usageActions: {...state.requireValue.usageActions, id: SettingsAction(intent: intent, pending: true, operation: ticket.state.value)}));
      // The checks projection owns the one observer for this ticket, including
      // an automatic check that manual refresh joined. No second subscription.
      _usageChecks?.refresh();
    }
    final result = await ticket.result;
    if (!owns()) return;
    state = AsyncData(state.requireValue.copyWith(usageActions: {...state.requireValue.usageActions,
      id: settledSettingsAction(intent, result, operation: ticket.state.value)}));
    _usageChecks?.refresh();
  }

  Future<void> _run<T>(OperationTicket<T> Function() admit, int intent,
      bool Function() owns, void Function(SettingsAction) update, void Function(Observation) retain) async {
    OperationTicket<T> ticket;
    try { ticket = admit(); }
    on StudioFailure catch (error) {
      update(SettingsAction(intent: intent, outcome: SettingsActionOutcome.rejected, error: error));
      return;
    }
    StudioFailure? observationError;
    var action = SettingsAction(intent: intent, pending: true, operation: ticket.state.value);
    if (owns()) {
      try {
        final watch = ticket.state.watchLatest((operation) {
          if (owns()) { action = action.copyWith(operation: operation); update(action); }
        });
        if (owns()) { retain(watch.observation); } else { watch.observation.cancel(); }
      } on StudioFailure catch (error) { observationError = error; }
      action = action.copyWith(operation: ticket.state.value, observationError: observationError);
      update(action);
    }
    final result = await ticket.result;
    if (!owns()) return;
    action = settledSettingsAction(intent, result, operation: ticket.state.value).copyWith(observationError: observationError);
    update(action);
    _publish(state.requireValue);
  }

  static StudioFailure _failure(StudioFailureCode code, String message) => StudioFailure(
    code: code, message: message, retryable: true, correlationId: 'settings-accounts');
}
