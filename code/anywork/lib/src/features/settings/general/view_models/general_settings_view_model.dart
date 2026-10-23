import 'dart:async';

import 'package:anywork_client/configuration.dart';
import 'package:anywork_client/models.dart';
import 'package:anywork_client/operations.dart';
import 'package:anywork_client/resources.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../../app/app_bindings.dart';
import '../../state/settings_action.dart';
import '../../state/settings_navigation_state.dart';
import '../../view_models/read_values.dart';
import '../../view_models/settings_navigation_view_model.dart';
import '../../view_models/settings_tab_lifecycle.dart';
import '../state/general_settings_state.dart';
import 'general_visible_reads.dart';

part 'general_settings_view_model.g.dart';

@Riverpod(keepAlive: true)
class GeneralSettingsViewModel extends _$GeneralSettingsViewModel {
  late ConfigurationRepository _configuration;
  late ModelsRepository _models;
  final _operationWatches = <GeneralSettingAction, Observation>{};
  final _webWatches = <Observation>[];
  bool _alive = true;
  int _lifetime = 0;
  bool _visible = true;
  late GeneralVisibleReads _reads;

  @override
  Future<GeneralSettingsViewState> build() async {
    _alive = true;
    final lifetime = ++_lifetime;
    _configuration = ref.watch(configurationRepositoryProvider);
    _models = ref.watch(modelsRepositoryProvider);
    _reads = GeneralVisibleReads(_configuration, _models, (field, error, current, reading, anyReading) {
      if (!_alive || lifetime != _lifetime || state.asData == null) return;
      final value = state.requireValue;
      final issues = {...value.readIssues};
      if (current && !reading) { if (error == null) issues.remove(field); else issues[field] = error; }
      state = AsyncData(value.copyWith(readIssues: issues, readErrors: issues.values.toList(), readPending: anyReading));
    });
    final tab = ref.read(settingsNavigationViewModelProvider.notifier).register(SettingsTab.general,
      SettingsTabLifecycle(visibility: setVisible));
    _visible = tab.visible;
    Observation? configurationObservation;
    Observation? modelObservation;
    ref.onDispose(() {
      _alive = false;
      _lifetime++;
      configurationObservation?.cancel(); modelObservation?.cancel(); tab.unregister();
      for (final observation in _operationWatches.values) { observation.cancel(); }
      _operationWatches.clear();
      for (final observation in _webWatches) { observation.cancel(); }
      _webWatches.clear(); _reads.dispose();
    });
    final configurationWatch = _configuration.state.watchLatest((source) {
      if (!_alive || lifetime != _lifetime) return;
      final previous = state.asData?.value;
      if (previous == null) return;
      final web = displayReadValue(source.webSearch);
      state = AsyncData(previous.copyWith(
        source: source,
        canonical: displayReadValue(source.general) ?? previous.canonical,
        configuredWebSearch: web ?? previous.configuredWebSearch,
        configuredDeepSeek: displayReadValue(source.deepSeekSearch) ?? previous.configuredDeepSeek,
        webSearch: web == null ? previous.webSearch : previous.webSearch == null
          ? _fromCanonical(web) : _adoptObservedWeb(previous.webSearch!, source, previous.webFieldActions),
      ));
      _reads.refresh();
    });
    configurationObservation = configurationWatch.observation;
    final modelWatch = _models.state.watchLatest((source) {
      if (!_alive || lifetime != _lifetime) return;
      final previous = state.asData?.value;
      if (previous == null) return;
      state = AsyncData(previous.copyWith(
        modelSource: source,
        effectiveWebSearch: displayReadValue(source.webSearch),
        effectiveDeepSeek: displayReadValue(source.deepSeekSearch),
      ));
      _reads.refresh();
    });
    modelObservation = modelWatch.observation;
    final errors = await _readInitial();
    _reads.rememberInitialFailures();
    final source = _configuration.state.value;
    final general = displayReadValue(source.general);
    final web = displayReadValue(source.webSearch);
    final deepSeek = displayReadValue(source.deepSeekSearch);
    final modelSource = _models.state.value;
    Future<void>(() { if (_alive && lifetime == _lifetime) _reads.visible(_visible); });
    return GeneralSettingsViewState(
      source: source,
      modelSource: modelSource,
      canonical: general,
      configuredWebSearch: web,
      configuredDeepSeek: deepSeek,
      webSearch: web == null ? null : _fromCanonical(web),
      effectiveWebSearch: displayReadValue(modelSource.webSearch),
      effectiveDeepSeek: displayReadValue(modelSource.deepSeekSearch),
      readErrors: errors.values.toList(), readIssues: errors,
    );
  }

  Future<Map<GeneralReadField, StudioFailure>> _readInitial() async {
    final errors = <GeneralReadField, StudioFailure>{};
    Future<void> capture<T>(GeneralReadField field, Future<T> query) async {
      try { await query; } on StudioFailure catch (error) { errors[field] = error; }
    }
    await Future.wait([
      capture(GeneralReadField.general, _configuration.loadGeneralSettings()),
      capture(GeneralReadField.webSearch, _configuration.loadWebSearchSettings()),
      capture(GeneralReadField.deepSeek, _configuration.loadDeepSeekSettings()),
      capture(GeneralReadField.webPolicy, _models.loadWebSearch()),
      capture(GeneralReadField.deepSeekPolicy, _models.loadDeepSeekSearch()),
    ]);
    return errors;
  }

  void setVisible(bool visible) { _visible = visible; if (_alive) _reads.visible(visible); }
  void retryRead() { if (_alive) _reads.retry(); }

  Future<void> setFollowActiveTurn(bool value) => _toggle(
    GeneralSettingAction.followActiveTurn, SettingsFieldUpdate.generalFollowActiveTurn(value: value));
  Future<void> setCompactTimeline(bool value) => _toggle(
    GeneralSettingAction.compactTimeline, SettingsFieldUpdate.generalCompactTimeline(value: value));
  Future<void> setDeepSeekSearch(bool value) => _toggle(
    GeneralSettingAction.deepSeekSearch, SettingsFieldUpdate.deepSeekWebSearchEnabled(value: value));
  Future<void> setDeepSeekFetch(bool value) => _toggle(
    GeneralSettingAction.deepSeekFetch, SettingsFieldUpdate.deepSeekWebFetchEnabled(value: value));

  Future<void> _toggle(GeneralSettingAction field, SettingsFieldUpdate update) async {
    if (!_alive) return;
    final previous = state.requireValue;
    if (previous.actions[field]?.preventsResubmission ?? false) return;
    final intent = previous.latestIntent + 1;
    final lifetime = _lifetime;
    state = AsyncData(previous.copyWith(latestIntent: intent, actions: {
      ...previous.actions, field: SettingsAction(intent: intent, pending: true),
    }));
    OperationTicket<Unit> ticket;
    try {
      ticket = _configuration.applyField(update);
    } on StudioFailure catch (error) {
      if (!_ownsAction(field, intent, lifetime)) return;
      final current = state.requireValue;
      state = AsyncData(current.copyWith(actions: {
        ...current.actions,
        field: SettingsAction(intent: intent, outcome: SettingsActionOutcome.rejected, error: error),
      }));
      return;
    }
    if (!_ownsAction(field, intent, lifetime)) return;
    _operationWatches.remove(field)?.cancel();
    StudioFailure? observationError;
    try {
      final watch = ticket.state.watchLatest((operation) {
        if (!_ownsAction(field, intent, lifetime)) return;
        final current = state.requireValue;
        state = AsyncData(current.copyWith(actions: {
          ...current.actions, field: current.actions[field]!.copyWith(operation: operation),
        }));
      });
      _operationWatches[field] = watch.observation;
    } on StudioFailure catch (error) {
      observationError = error; // The command has already been admitted.
    }
    state = AsyncData(state.requireValue.copyWith(actions: {
      ...state.requireValue.actions,
      field: SettingsAction(intent: intent, pending: true, operation: ticket.state.value,
        observationError: observationError),
    }));
    final result = await ticket.result;
    if (!_ownsAction(field, intent, lifetime)) return;
    final current = state.requireValue;
    state = AsyncData(current.copyWith(actions: {
      ...current.actions,
      field: settledSettingsAction(intent, result, operation: ticket.state.value)
        .copyWith(observationError: observationError),
    }));
  }

  bool _ownsAction(GeneralSettingAction field, int intent, int lifetime) =>
      _alive && lifetime == _lifetime && state.asData?.value.actions[field]?.intent == intent;

  void setWebMode(String value) => _editWeb(WebSearchField.mode, value);
  void setWebContextSize(String? value) {
    if (!_alive) return;
    final current = state.requireValue;
    final draft = current.webSearch;
    if (draft == null || draft.contextSize == value) return;
    state = AsyncData(current.copyWith(webSearch: draft.copyWith(
      contextSize: value,
      dirtyFields: {...draft.dirtyFields, WebSearchField.contextSize},
      fieldRevisions: {...draft.fieldRevisions, WebSearchField.contextSize: draft.revision + 1},
      revision: draft.revision + 1,
    )));
  }
  void setDomains(String value) => _editWeb(WebSearchField.domains, value);
  void setCountry(String value) => _editWeb(WebSearchField.country, value);
  void setRegion(String value) => _editWeb(WebSearchField.region, value);
  void setCity(String value) => _editWeb(WebSearchField.city, value);
  void setTimezone(String value) => _editWeb(WebSearchField.timezone, value);

  void _editWeb(WebSearchField field, String value) {
    if (!_alive) return;
    final current = state.requireValue;
    final draft = current.webSearch;
    if (draft == null) return;
    final updated = switch (field) {
      WebSearchField.mode => draft.copyWith(mode: value),
      WebSearchField.domains => draft.copyWith(domains: value),
      WebSearchField.country => draft.copyWith(country: value),
      WebSearchField.region => draft.copyWith(region: value),
      WebSearchField.city => draft.copyWith(city: value),
      WebSearchField.timezone => draft.copyWith(timezone: value),
      WebSearchField.contextSize => throw ArgumentError('Use setWebContextSize'),
    };
    if (updated == draft) return;
    state = AsyncData(current.copyWith(webSearch: updated.copyWith(
      dirtyFields: {...draft.dirtyFields, field}, revision: draft.revision + 1,
      fieldRevisions: {...draft.fieldRevisions, field: draft.revision + 1},
    )));
  }

  Future<bool> saveWebSearch() async {
    if (!_alive) return false;
    final frozen = state.requireValue;
    final raw = frozen.webSearch;
    final canonical = frozen.configuredWebSearch;
    if (raw == null || canonical == null) return false;
    if (frozen.webSaving) return false;
    final changes = <SettingsFieldUpdate>[];
    final fields = <WebSearchField>[];
    final blocked = <WebSearchField>{};
    final unchanged = <WebSearchField>{};
    void add(WebSearchField field, bool changed, SettingsFieldUpdate update) {
      if (!raw.dirtyFields.contains(field)) return;
      final prior = frozen.webFieldActions[field];
      if (prior != null && prior.intent == (raw.fieldRevisions[field] ?? 0) && prior.preventsResubmission) {
        blocked.add(field);
      } else if (changed) { fields.add(field); changes.add(update); }
      else { unchanged.add(field); }
    }
    final domains = raw.domains.split(RegExp(r'[,\n]')).map((value) => value.trim())
        .where((value) => value.isNotEmpty).toSet().toList();
    add(WebSearchField.mode, raw.mode != canonical.configuredMode,
      SettingsFieldUpdate.webSearchMode(value: raw.mode));
    add(WebSearchField.contextSize, raw.contextSize != canonical.contextSize,
      SettingsFieldUpdate.webSearchContextSize(value: raw.contextSize));
    add(WebSearchField.domains, !_same(domains, canonical.allowedDomains),
      SettingsFieldUpdate.webSearchAllowedDomains(value: domains));
    add(WebSearchField.country, _nullable(raw.country) != canonical.country,
      SettingsFieldUpdate.webSearchCountry(value: _nullable(raw.country)));
    add(WebSearchField.region, _nullable(raw.region) != canonical.region,
      SettingsFieldUpdate.webSearchRegion(value: _nullable(raw.region)));
    add(WebSearchField.city, _nullable(raw.city) != canonical.city,
      SettingsFieldUpdate.webSearchCity(value: _nullable(raw.city)));
    add(WebSearchField.timezone, _nullable(raw.timezone) != canonical.timezone,
      SettingsFieldUpdate.webSearchTimezone(value: _nullable(raw.timezone)));
    if (changes.isEmpty) {
      final dirty = {...raw.dirtyFields};
      if (isCurrentRead(frozen.source.webSearch, frozen.source.projection.header?.reference,
          frozen.source.projection.stamp?.origin)) dirty.removeAll(unchanged);
      state = AsyncData(frozen.copyWith(webSearch: _adopt(raw.copyWith(dirtyFields: dirty), canonical)));
      return blocked.isEmpty; // No operation/receipt was created.
    }
    final intent = frozen.latestIntent + 1;
    final lifetime = _lifetime;
    state = AsyncData(frozen.copyWith(latestIntent: intent, webSaveIntent: intent,
      webSaving: true, webSaveActions: [], webSaveResult: null,
      webFieldActions: {...frozen.webFieldActions, for (final field in fields)
        field: SettingsAction(intent: raw.fieldRevisions[field] ?? 0, pending: true)}));
    SettingsWriteBatch batch;
    try {
      batch = _configuration.applyFields(changes);
    } on StudioFailure catch (error) {
      if (!_ownsBatch(intent, lifetime)) return false;
      state = AsyncData(state.requireValue.copyWith(webSaving: false, webSaveActions: [
        SettingsAction(intent: intent, outcome: SettingsActionOutcome.rejected, error: error),
      ], webFieldActions: {...state.requireValue.webFieldActions, for (final field in fields)
        field: SettingsAction(intent: raw.fieldRevisions[field] ?? 0,
          outcome: SettingsActionOutcome.rejected, error: error)}));
      return false;
    }
    if (!_ownsBatch(intent, lifetime)) { await batch.result; return false; }
    for (final observation in _webWatches) { observation.cancel(); }
    _webWatches.clear();
      final actions = <SettingsAction>[];
      final fieldActions = {...state.requireValue.webFieldActions};
      for (var index = 0; index < batch.operations.length; index++) {
        final step = index;
        StudioFailure? observationError;
        try {
        final watch = batch.operations[index].state.watchLatest((operation) {
          if (!_ownsBatch(intent, lifetime)) return;
          final current = state.requireValue;
          if (step >= current.webSaveActions.length) return;
          final next = [...current.webSaveActions];
          next[step] = next[step].copyWith(operation: operation);
          final field = fields[step];
          state = AsyncData(current.copyWith(webSaveActions: next, webFieldActions: {
            ...current.webFieldActions, field: current.webFieldActions[field]!.copyWith(operation: operation),
          }));
        });
        _webWatches.add(watch.observation);
        } on StudioFailure catch (error) { observationError = error; }
        actions.add(SettingsAction(intent: intent, pending: true,
          operation: batch.operations[index].state.value, observationError: observationError));
        fieldActions[fields[index]] = actions.last.copyWith(intent: raw.fieldRevisions[fields[index]] ?? 0);
      }
      state = AsyncData(state.requireValue.copyWith(webSaveActions: actions, webFieldActions: fieldActions));
      final result = await batch.result;
      if (!_ownsBatch(intent, lifetime)) return false;
      final settled = <SettingsAction>[];
      final succeeded = <WebSearchField>{};
      final settledFields = {...state.requireValue.webFieldActions};
      for (final step in result.steps) {
        switch (step) {
          case FinishedSettingsField(:final index, result: final outcome):
            final action = settledSettingsAction(intent, outcome, operation: batch.operations[index].state.value);
            final presentation = action.copyWith(observationError: actions[index].observationError);
            settled.add(presentation);
            settledFields[fields[index]] = presentation.copyWith(intent: raw.fieldRevisions[fields[index]] ?? 0);
            if (action.succeeded) succeeded.add(fields[index]);
          case NotStartedSettingsField(:final index, :final error):
            final action = SettingsAction(intent: intent, outcome: SettingsActionOutcome.rejected, error: error);
            settled.add(action);
            settledFields[fields[index]] = action.copyWith(intent: raw.fieldRevisions[fields[index]] ?? 0);
        }
      }
      final current = state.requireValue;
      final currentDraft = current.webSearch!;
      final dirty = {...currentDraft.dirtyFields};
      if (isCurrentRead(current.source.webSearch, current.source.projection.header?.reference,
          current.source.projection.stamp?.origin)) {
        dirty.removeWhere((field) => unchanged.contains(field) &&
          currentDraft.fieldRevisions[field] == raw.fieldRevisions[field] &&
          _matches(field, currentDraft, current.configuredWebSearch!));
      }
      state = AsyncData(current.copyWith(
        webSaving: false, webSaveActions: settled, webSaveResult: result, webFieldActions: settledFields,
        webSearch: _adoptObservedWeb(currentDraft.copyWith(dirtyFields: dirty), current.source, settledFields),
      ));
      return succeeded.length == fields.length && blocked.isEmpty;
  }

  bool _ownsBatch(int intent, int lifetime) => _alive && lifetime == _lifetime &&
      state.asData?.value.webSaveIntent == intent;

  static String? _nullable(String raw) => raw.trim().isEmpty ? null : raw.trim();
  static bool _same(List<String> a, List<String> b) =>
      a.length == b.length && Iterable<int>.generate(a.length).every((i) => a[i] == b[i]);

  static WebSearchDraft _fromCanonical(WebSearchConfiguration value) => WebSearchDraft(
    mode: value.configuredMode, contextSize: value.contextSize,
    domains: value.allowedDomains.join(', '), country: value.country ?? '',
    region: value.region ?? '', city: value.city ?? '', timezone: value.timezone ?? '',
  );

  static WebSearchDraft _adoptObservedWeb(WebSearchDraft draft, ConfigurationState source,
      Map<WebSearchField, SettingsAction> actions) {
    final value = displayReadValue(source.webSearch);
    if (value == null) return draft;
    final dirty = {...draft.dirtyFields};
    if (isCurrentRead(source.webSearch, source.projection.header?.reference, source.projection.stamp?.origin)) {
      dirty.removeWhere((field) => (actions[field]?.succeeded ?? false) &&
        actions[field]!.intent == (draft.fieldRevisions[field] ?? 0) && _matches(field, draft, value));
    }
    return _adopt(draft.copyWith(dirtyFields: dirty), value);
  }

  static bool _matches(WebSearchField field, WebSearchDraft raw, WebSearchConfiguration value) => switch (field) {
    WebSearchField.mode => raw.mode == value.configuredMode,
    WebSearchField.contextSize => raw.contextSize == value.contextSize,
    WebSearchField.domains => _same(raw.domains.split(RegExp(r'[,\n]')).map((item) => item.trim())
      .where((item) => item.isNotEmpty).toSet().toList(), value.allowedDomains),
    WebSearchField.country => _nullable(raw.country) == value.country,
    WebSearchField.region => _nullable(raw.region) == value.region,
    WebSearchField.city => _nullable(raw.city) == value.city,
    WebSearchField.timezone => _nullable(raw.timezone) == value.timezone,
  };

  static WebSearchDraft _adopt(WebSearchDraft draft, WebSearchConfiguration value) {
    final dirty = draft.dirtyFields;
    return draft.copyWith(
      mode: dirty.contains(WebSearchField.mode) ? draft.mode : value.configuredMode,
      contextSize: dirty.contains(WebSearchField.contextSize) ? draft.contextSize : value.contextSize,
      domains: dirty.contains(WebSearchField.domains) ? draft.domains : value.allowedDomains.join(', '),
      country: dirty.contains(WebSearchField.country) ? draft.country : value.country ?? '',
      region: dirty.contains(WebSearchField.region) ? draft.region : value.region ?? '',
      city: dirty.contains(WebSearchField.city) ? draft.city : value.city ?? '',
      timezone: dirty.contains(WebSearchField.timezone) ? draft.timezone : value.timezone ?? '',
    );
  }
}
