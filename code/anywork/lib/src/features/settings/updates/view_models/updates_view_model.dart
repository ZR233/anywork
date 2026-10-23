import 'package:anywork_client/operations.dart';
import 'package:anywork_client/resources.dart';
import 'package:anywork_client/updates.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../../app/app_bindings.dart';
import '../../state/settings_action.dart';
import '../../state/settings_navigation_state.dart';
import '../../view_models/read_values.dart';
import '../../view_models/settings_navigation_view_model.dart';
import '../../view_models/settings_tab_lifecycle.dart';
import '../../view_models/visible_read_demand.dart';
import '../state/updates_view_state.dart';

part 'updates_view_model.g.dart';

const _compiledVersion = String.fromEnvironment('ANYWORK_VERSION', defaultValue: '1.0.0');

@Riverpod(keepAlive: true)
class UpdatesViewModel extends _$UpdatesViewModel {
  late UpdatesRepository _repository;
  late VisibleReadDemand<(ProductReadOrigin, UpdatesReadRef)> _valueRead;
  late VisibleReadDemand<(ProductReadOrigin, UpdateSummaryReadRef)> _summaryRead;
  final _operations = <UpdateSettingsAction, Observation>{};
  int _lifetime = 0;
  bool _alive = true;
  bool _visible = true;
  bool _preparing = false;
  bool _bootstrappingValue = false;

  @override
  Future<UpdatesViewState> build() async {
    _alive = true;
    final lifetime = ++_lifetime;
    _repository = ref.watch(updatesRepositoryProvider);
    _valueRead = VisibleReadDemand(read: (key) async {
      final source = _repository.state.value.projection;
      if (source.stamp?.origin == key.$1 && source.header?.reference == key.$2) await _repository.loadValue();
    }, changed: (key, error, current) => _readChanged(UpdatesReadField.value, error, current, _valueRead.reading, lifetime));
    _summaryRead = VisibleReadDemand(read: (key) => _loadSummary(key, lifetime),
      changed: (key, error, current) => _readChanged(UpdatesReadField.summary, error, current, _summaryRead.reading, lifetime));
    final tab = ref.read(settingsNavigationViewModelProvider.notifier).register(SettingsTab.general,
      SettingsTabLifecycle(visibility: setVisible));
    _visible = tab.visible;
    Observation? observation;
    ref.onDispose(() {
      _alive = false; _lifetime++;
      observation?.cancel(); _valueRead.dispose(); _summaryRead.dispose(); tab.unregister();
      for (final value in _operations.values) { value.cancel(); }
      _operations.clear();
      // No check, cancellation, close or automatic startup from this observer.
    });
    final watch = _repository.state.watchLatest((source) {
      if (!_owns(lifetime)) return;
      state = AsyncData(state.requireValue.copyWith(source: source));
      _refreshReads();
    });
    observation = watch.observation;
    StudioFailure? initialError;
    try { await _repository.loadValue(); } on StudioFailure catch (error) { initialError = error; }
    if (failedReadIdentity(_repository.state.value.value) case final key?) _valueRead.remember(key);
    Future<void>(() { if (_owns(lifetime)) _refreshReads(); });
    return UpdatesViewState(source: _repository.state.value, controls: _repository.controls, currentVersion: _compiledVersion,
      readIssues: {if (initialError != null) UpdatesReadField.value: initialError});
  }

  bool _owns(int lifetime) => _alive && lifetime == _lifetime && state.asData != null;
  void setVisible(bool value) { if (!_alive) return; _visible = value; _refreshReads(); }
  void retryRead() {
    if (!_alive || !_visible) return;
    if (_repository.state.value.projection.stamp == null || _repository.state.value.projection.header == null) {
      if (!_bootstrappingValue) {
        final lifetime = _lifetime;
        final repository = _repository;
        _bootstrappingValue = true;
        state = AsyncData(state.requireValue.copyWith(readingValue: true));
        Future<void>(() async {
          if (!_owns(lifetime)) return;
          if (!_visible) {
            _bootstrappingValue = false;
            _readChanged(UpdatesReadField.value, null, false, false, lifetime);
            return;
          }
          StudioFailure? issue;
          try { await repository.loadValue(); } on StudioFailure catch (error) { issue = error; }
          if (!_owns(lifetime)) return;
          _bootstrappingValue = false;
          if (failedReadIdentity(_repository.state.value.value) case final key?) _valueRead.remember(key);
          _readChanged(UpdatesReadField.value, issue, true, false, lifetime);
        });
      }
    }
    _refreshReads(); _valueRead.retry(); _summaryRead.retry();
  }
  void _readChanged(UpdatesReadField field, StudioFailure? error, bool current, bool reading, int lifetime) {
    if (!_owns(lifetime)) return;
    final issues = {...state.requireValue.readIssues};
    if (current && !reading) { if (error == null) { issues.remove(field); } else { issues[field] = error; } }
    state = AsyncData(state.requireValue.copyWith(readIssues: issues,
      readingValue: _valueRead.reading || _bootstrappingValue, readingSummary: _summaryRead.reading));
    if (!reading) _refreshReads();
  }
  void _refreshReads() {
    if (!_alive || state.asData == null) return;
    final source = _repository.state.value;
    final origin = source.projection.stamp?.origin;
    final valueReference = source.projection.header?.reference;
    final reference = source.projection.header?.summary;
    _valueRead.visible(false);
    _valueRead.target(origin == null || valueReference == null ? null : (origin, valueReference),
      needed: state.requireValue.currentValue == null && !_bootstrappingValue);
    _valueRead.visible(_visible);
    _summaryRead.visible(false);
    _summaryRead.target(origin == null || reference == null ? null : (origin, reference),
      needed: state.requireValue.currentSummary == null && !_valueRead.reading && !_bootstrappingValue);
    _summaryRead.visible(_visible);
  }
  Future<void> _loadSummary((ProductReadOrigin, UpdateSummaryReadRef) key, int lifetime) async {
    final source = _repository.state.value;
    if (source.projection.stamp?.origin != key.$1 || source.projection.header?.summary != key.$2) return;
    final summary = await _repository.loadSummary();
    final latest = _repository.state.value;
    if (!_owns(lifetime) || latest.projection.stamp?.origin != key.$1 || latest.projection.header?.summary != key.$2) return;
    state = AsyncData(state.requireValue.copyWith(summary: summary, summaryOrigin: key.$1, summaryReference: key.$2));
  }

  bool get canCheck {
    if (!_alive || state.asData == null || !state.requireValue.controls.enabled) return false;
    final current = state.requireValue;
    final phase = current.source.projection.header?.brief;
    return phase is! DisabledUpdatesBrief && phase is! CheckingUpdatesBrief &&
      phase is! DownloadingUpdatesBrief && phase is! VerifyingUpdatesBrief && phase is! InstallerLaunchedUpdatesBrief &&
      !(current.actions[UpdateSettingsAction.check]?.preventsResubmission ?? false) &&
      !(current.actions[UpdateSettingsAction.prepare]?.preventsResubmission ?? false);
  }
  bool get canPrepare {
    if (!_alive || _preparing || state.asData == null || !state.requireValue.controls.enabled) return false;
    final current = state.requireValue;
    final phase = current.source.projection.header?.brief;
    return current.currentSummary != null && (phase is AvailableUpdatesBrief || phase is ReadyUpdatesBrief ||
      phase is InstallFailedUpdatesBrief || phase is DownloadingUpdatesBrief || phase is VerifyingUpdatesBrief) &&
      !(current.actions[UpdateSettingsAction.prepare]?.preventsResubmission ?? false) &&
      !(current.actions[UpdateSettingsAction.check]?.preventsResubmission ?? false) &&
      !(current.actions[UpdateSettingsAction.cancel]?.preventsResubmission ?? false);
  }
  bool get canCancel {
    if (!_alive || state.asData == null || !state.requireValue.controls.enabled) return false;
    final current = state.requireValue;
    final phase = current.source.projection.header?.brief;
    return ((current.actions[UpdateSettingsAction.prepare]?.pending ?? false) ||
      (current.actions[UpdateSettingsAction.prepare]?.uncertain ?? false) || phase is DownloadingUpdatesBrief ||
      phase is VerifyingUpdatesBrief) && !(current.actions[UpdateSettingsAction.cancel]?.preventsResubmission ?? false);
  }

  Future<void> check() async {
    if (!canCheck) return;
    final intent = _begin(UpdateSettingsAction.check);
    await _run<Unit>(UpdateSettingsAction.check, intent, _repository.check);
  }
  Future<void> cancelPreparation() async {
    if (!canCancel) return;
    final intent = _begin(UpdateSettingsAction.cancel);
    await _run<Unit>(UpdateSettingsAction.cancel, intent, _repository.cancelPreparation);
    // Canonical Ready may have won the race. Never publish Cancelled here.
  }
  Future<UpdateRestartRequest?> prepare() async {
    if (!canPrepare) return null;
    final version = state.requireValue.currentSummary!.version;
    final lifetime = _lifetime;
    final intent = _begin(UpdateSettingsAction.prepare);
    _preparing = true;
    try {
      final result = await _run<UpdatePreparationResult>(UpdateSettingsAction.prepare, intent, _repository.prepare);
      final ready = switch (result) {
        CommittedCommandResult<UpdatePreparationResult>(:final value) ||
        AcknowledgedCommandResult<UpdatePreparationResult>(:final value) => value.readyVersion,
        _ => null,
      };
      if (!_owns(lifetime) || ready == null || ready != version || state.requireValue.latestIntent != intent) return null;
      final source = _repository.state.value;
      if (source.projection.header?.brief is! ReadyUpdatesBrief) return null;
      if (state.requireValue.currentSummary == null) {
        final origin = source.projection.stamp?.origin;
        final reference = source.projection.header?.summary;
        if (origin == null || reference == null) return null;
        try { await _loadSummary((origin, reference), lifetime); }
        on StudioFailure catch (error) {
          if (_owns(lifetime)) state = AsyncData(state.requireValue.copyWith(readIssues: {
            ...state.requireValue.readIssues, UpdatesReadField.summary: error}));
          return null;
        }
      }
      final request = UpdateRestartRequest(intent: intent, version: ready);
      return ownsRestart(request) ? request : null;
    } finally { _preparing = false; }
  }
  bool ownsRestart(UpdateRestartRequest request) => _alive && state.asData != null &&
    state.requireValue.latestIntent == request.intent && state.requireValue.consumedRestartIntent != request.intent &&
    state.requireValue.actions[UpdateSettingsAction.prepare]?.intent == request.intent &&
    (state.requireValue.actions[UpdateSettingsAction.prepare]?.succeeded ?? false) &&
    state.requireValue.source.projection.header?.brief is ReadyUpdatesBrief &&
    state.requireValue.currentSummary?.version == request.version;
  bool takeRestart(UpdateRestartRequest request) {
    if (!ownsRestart(request)) return false;
    state = AsyncData(state.requireValue.copyWith(consumedRestartIntent: request.intent));
    return true;
  }

  int _begin(UpdateSettingsAction field) {
    final intent = state.requireValue.latestIntent + 1;
    state = AsyncData(state.requireValue.copyWith(latestIntent: intent,
      actions: {...state.requireValue.actions, field: SettingsAction(intent: intent, pending: true)}));
    return intent;
  }
  Future<CommandResult<T>?> _run<T>(UpdateSettingsAction field, int intent, OperationTicket<T> Function() admit) async {
    final lifetime = _lifetime;
    bool owns() => _owns(lifetime) && state.requireValue.actions[field]?.intent == intent;
    void update(SettingsAction action) {
      if (owns()) state = AsyncData(state.requireValue.copyWith(actions: {...state.requireValue.actions, field: action}));
    }
    if (!owns()) return null;
    if (field == UpdateSettingsAction.prepare && state.requireValue.latestIntent != intent) {
      update(SettingsAction(intent: intent, outcome: SettingsActionOutcome.rejected,
        error: const StudioFailure(code: StudioFailureCode.cancelled,
          message: 'Update preparation was cancelled before admission.', retryable: true,
          correlationId: 'settings-update-preparation')));
      return null;
    }
    OperationTicket<T> ticket;
    try { ticket = admit(); }
    on StudioFailure catch (error) {
      update(SettingsAction(intent: intent, outcome: SettingsActionOutcome.rejected, error: error)); return null;
    }
    var action = SettingsAction(intent: intent, pending: true, operation: ticket.state.value);
    StudioFailure? observationError;
    if (owns()) {
      _operations.remove(field)?.cancel();
      try {
        final watch = ticket.state.watchLatest((operation) {
          if (owns()) { action = action.copyWith(operation: operation); update(action); }
        });
        if (owns()) { _operations[field] = watch.observation; } else { watch.observation.cancel(); }
      } on StudioFailure catch (error) { observationError = error; }
      action = action.copyWith(observationError: observationError); update(action);
    }
    final result = await ticket.result;
    if (!owns()) return result;
    action = settledSettingsAction(intent, result, operation: ticket.state.value).copyWith(observationError: observationError);
    update(action); _refreshReads();
    return result;
  }
}
