import 'dart:async';

import 'package:anywork_client/configuration.dart';
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
import '../state/skills_view_state.dart';
import 'skill_names.dart';

part 'skills_preferences_view_model.g.dart';

/// Global disabled-name intent, independent of the visible Project catalog.
@riverpod
class SkillsPreferencesViewModel extends _$SkillsPreferencesViewModel {
  late ConfigurationRepository _repository;
  late VisibleReadDemand<(ProductReadOrigin, ConfigurationReadRef)> _configuration;
  late VisibleReadDemand<(ProductReadOrigin, ProductSourceStatusRef)> _source;
  Observation? _operation;
  bool _alive = true;
  bool _visible = false;
  bool _refreshing = false;
  int _lifetime = 0;
  int _intent = 0;
  @override
  Future<SkillsPreferencesState> build() async {
    _alive = true;
    final lifetime = ++_lifetime;
    _repository = ref.watch(configurationRepositoryProvider);
    final repository = _repository;
    _configuration = VisibleReadDemand(read: (target) async {
      final repository = _repository;
      final source = repository.state.value.projection;
      if (source.stamp?.origin == target.$1 && source.header?.reference == target.$2) await repository.loadSkillsSettings();
    }, changed: (target, error, current) => _changed(SkillsPreferencesReadField.configuration, error, current, _configuration.reading));
    _source = VisibleReadDemand(read: (target) async {
      final repository = _repository;
      final source = repository.state.value.projection;
      if (source.stamp?.origin == target.$1 && source.header?.source.status == target.$2) await repository.loadSourceStatus();
    }, changed: (target, error, current) => _changed(SkillsPreferencesReadField.sourceStatus, error, current, _source.reading));
    final tab = ref.read(settingsNavigationViewModelProvider.notifier).register(SettingsTab.skills,
      SettingsTabLifecycle(visibility: setVisible));
    _visible = tab.visible;
    Observation? observation;
    ref.onDispose(() {
      _alive = false; _lifetime++; tab.unregister(); observation?.cancel(); _operation?.cancel();
      _configuration.dispose(); _source.dispose();
    });
    observation = repository.state.watchLatest((source) {
      if (!_owns(lifetime)) return;
      state = AsyncData(state.requireValue.copyWith(source: source)); _refreshDemands();
    }).observation;
    final issues = <SkillsPreferencesReadField, StudioFailure>{};
    Future<void> initial(SkillsPreferencesReadField field, Future<void> Function() read) async {
      try { await read(); } on StudioFailure catch (error) { issues[field] = error; }
    }
    await Future.wait<void>([
      initial(SkillsPreferencesReadField.configuration, () async { await repository.loadSkillsSettings(); }),
      initial(SkillsPreferencesReadField.sourceStatus, repository.loadSourceStatus),
    ]);
    _rememberFailures();
    Future<void>(() {
      if (!_owns(lifetime)) return;
      state = AsyncData(state.requireValue.copyWith(source: repository.state.value));
      _rememberFailures(); _refreshDemands();
    });
    return SkillsPreferencesState(source: repository.state.value, readIssues: issues);
  }
  bool _owns(int lifetime) => _alive && lifetime == _lifetime && state.asData != null;
  SkillsSettings? get currentSettings {
    final source = state.requireValue.source;
    return isCurrentRead(source.skillsSettings, source.projection.header?.reference, source.projection.stamp?.origin)
      ? displayReadValue(source.skillsSettings) : null;
  }
  void setVisible(bool visible) {
    _visible = visible;
    if (_alive && state.asData != null) _refreshDemands();
  }
  void setQuery(String raw) {
    if (_alive && state.asData != null && state.requireValue.queryRaw != raw)
      state = AsyncData(state.requireValue.copyWith(queryRaw: raw));
  }
  void _rememberFailures() {
    final source = _repository.state.value;
    if (failedReadIdentity(source.skillsSettings) case final target?) _configuration.remember(target);
    if (failedReadIdentity(source.sourceStatus) case final target?) _source.remember(target);
  }
  void _changed(SkillsPreferencesReadField field, StudioFailure? error, bool current, bool reading) {
    if (!_alive || state.asData == null) return;
    final issues = {...state.requireValue.readIssues};
    if (current) { if (error == null) { issues.remove(field); } else { issues[field] = error; } }
    state = AsyncData(state.requireValue.copyWith(readIssues: issues,
      reading: {...state.requireValue.reading}..remove(field)..addAll(reading ? [field] : [])));
  }
  void _refreshDemands() {
    if (!_alive || state.asData == null) return;
    final source = state.requireValue.source;
    final origin = source.projection.stamp?.origin;
    final reference = source.projection.header?.reference;
    final status = source.projection.header?.source.status;
    _configuration.target(origin == null || reference == null ? null : (origin, reference),
      needed: !_refreshing && !isCurrentRead(source.skillsSettings, reference, origin));
    _source.target(origin == null || status == null ? null : (origin, status),
      needed: !_refreshing && !isCurrentRead(source.sourceStatus, status, origin));
    _configuration.visible(_visible); _source.visible(_visible);
  }
  Future<void> refresh() async {
    if (!_alive || !_visible || state.asData == null || _refreshing || _configuration.reading || _source.reading) return;
    _refreshing = true;
    final lifetime = _lifetime;
    final repository = _repository;
    try {
      await Future.wait<void>([
        _refreshField(SkillsPreferencesReadField.configuration, () async { await repository.loadSkillsSettings(); }, lifetime),
        _refreshField(SkillsPreferencesReadField.sourceStatus, repository.loadSourceStatus, lifetime),
      ]);
    } finally {
      _refreshing = false;
      if (_owns(lifetime)) { _rememberFailures(); _refreshDemands(); }
    }
  }
  Future<void> _refreshField(SkillsPreferencesReadField field, Future<void> Function() read, int lifetime) async {
    _changed(field, null, true, true);
    try {
      if (!_owns(lifetime) || !_visible) return;
      await read();
      if (_owns(lifetime)) _changed(field, null, true, false);
    } on StudioFailure catch (error) {
      if (_owns(lifetime)) _changed(field, error, true, false);
    } finally {
      if (_owns(lifetime)) state = AsyncData(state.requireValue.copyWith(reading: {...state.requireValue.reading}..remove(field)));
    }
  }
  Future<void> setEnabled(String name, bool enabled) async {
    if (!_alive || !_visible || state.asData == null || (state.requireValue.disabledAction?.preventsResubmission ?? false)) return;
    final settings = currentSettings;
    if (settings == null) return;
    final key = skillNameKey(name);
    final disabled = settings.disabled.where((value) => !enabled || skillNameKey(value) != key).toList();
    if (!enabled && !skillNameDisabled(disabled, name)) disabled.add(name);
    disabled.sort();
    final repository = _repository;
    final lifetime = _lifetime;
    final intent = ++_intent;
    state = AsyncData(state.requireValue.copyWith(disabledAction: SettingsAction(intent: intent, pending: true)));
    bool owns() => _owns(lifetime) && state.requireValue.disabledAction?.intent == intent;
    if (!owns()) return;
    OperationTicket<Unit> ticket;
    try { ticket = repository.applyField(SettingsFieldUpdate.skillsDisabled(value: disabled)); }
    on StudioFailure catch (error) {
      if (owns()) state = AsyncData(state.requireValue.copyWith(disabledAction: SettingsAction(intent: intent,
        outcome: SettingsActionOutcome.rejected, error: error)));
      return;
    }
    StudioFailure? observationError;
    if (owns()) {
      _operation?.cancel(); _operation = null;
      try {
        final watch = ticket.state.watchLatest((operation) {
          if (owns()) state = AsyncData(state.requireValue.copyWith(disabledAction: state.requireValue.disabledAction?.copyWith(operation: operation)));
        });
        if (owns()) { _operation = watch.observation; } else { watch.observation.cancel(); }
      } on StudioFailure catch (error) { observationError = error; }
      if (owns()) state = AsyncData(state.requireValue.copyWith(disabledAction: SettingsAction(intent: intent,
        pending: true, operation: ticket.state.value, observationError: observationError)));
    }
    final result = await ticket.result;
    if (owns()) state = AsyncData(state.requireValue.copyWith(disabledAction: settledSettingsAction(intent, result,
      operation: ticket.state.value).copyWith(observationError: observationError)));
  }
}
