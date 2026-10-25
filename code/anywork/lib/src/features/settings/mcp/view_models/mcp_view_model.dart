import 'dart:async';

import 'package:anywork_client/configuration.dart';
import 'package:anywork_client/mcp.dart';
import 'package:anywork_client/operations.dart';
import 'package:anywork_client/resources.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../../app/app_bindings.dart';
import '../../../../app/lifecycle/exit_participant.dart';
import '../../state/settings_action.dart';
import '../../state/settings_navigation_state.dart';
import '../../view_models/collection_values.dart';
import '../../view_models/coalesced_publish.dart';
import '../../view_models/read_values.dart';
import '../../view_models/settings_navigation_view_model.dart';
import '../../view_models/settings_tab_lifecycle.dart';
import '../state/mcp_view_state.dart';
import 'mcp_visible_reads.dart';

part 'mcp_view_model.g.dart';

@riverpod
class McpViewModel extends _$McpViewModel implements ApplicationEditProducer {
  late ConfigurationRepository _configuration;
  late McpRepository _mcp;
  late McpVisibleReads _reads;
  final _observations = <Observation>[];
  final _writes = <(String, McpConfigField), Observation>{};
  final _resets = <String, Observation>{};
  final _timers = <String, Timer>{};
  Observation? _allReset;
  ApplicationEditRegistration? _registration;
  int _lifetime = 0;
  bool _alive = true;
  bool _visible = false;
  bool _sealed = false;

  @override
  Future<McpViewState> build() async {
    _alive = true;
    _sealed = false;
    final lifetime = ++_lifetime;
    _configuration = ref.watch(configurationRepositoryProvider);
    _mcp = ref.watch(mcpRepositoryProvider);
    _reads = McpVisibleReads(_configuration, _mcp, (
      field,
      error,
      current,
      reading,
    ) {
      if (!_owns(lifetime)) return;
      final errors = {...state.requireValue.readIssues};
      if (current && !reading) {
        if (error == null) {
          errors.remove(field);
        } else {
          errors[field] = error;
        }
      }
      final pending = {...state.requireValue.reading};
      if (reading) {
        pending.add(field);
      } else {
        pending.remove(field);
      }
      state = AsyncData(
        state.requireValue.copyWith(readIssues: errors, reading: pending),
      );
    });
    final tab = ref
        .read(settingsNavigationViewModelProvider.notifier)
        .register(
          SettingsTab.mcp,
          SettingsTabLifecycle(visibility: setVisible, handoff: leave),
        );
    _visible = tab.visible;
    ref.onDispose(() {
      _alive = false;
      _lifetime++;
      tab.unregister();
      _reads.dispose();
      for (final timer in _timers.values) {
        timer.cancel();
      }
      _timers.clear();
      for (final observation in [
        ..._observations,
        ..._writes.values,
        ..._resets.values,
      ]) {
        observation.cancel();
      }
      _observations.clear();
      _writes.clear();
      _resets.clear();
      _allReset?.cancel();
      _registration?.unregister();
      _registration = null;
      // No save, reset, Repository cancellation or close during disposal.
    });
    // Sources can publish while another provider is still building; one trailing
    // microtask adopts the latest configuration/runtime pair, then refreshes.
    final sourcePublish = CoalescedPublish(() {
      if (_owns(lifetime)) _publishSources();
    });
    ref.onDispose(sourcePublish.dispose);
    _observations.add(
      _configuration.state.watchLatest((_) {
        if (_owns(lifetime)) sourcePublish.mark();
      }).observation,
    );
    _observations.add(
      _mcp.state.watchLatest((_) {
        if (_owns(lifetime)) sourcePublish.mark();
      }).observation,
    );
    final errors = <McpReadField, StudioFailure>{};
    Future<void> read(McpReadField field, Future<void> Function() query) async {
      try {
        await query();
      } on StudioFailure catch (error) {
        errors[field] = error;
      }
    }

    await Future.wait<void>([
      read(McpReadField.configurationStatus, _configuration.loadSourceStatus),
      read(McpReadField.runtimeStatus, _mcp.loadSourceStatus),
    ]);
    _reads.rememberStatusFailures();
    Future<void>(() {
      if (_owns(lifetime)) _reads.visible(_visible);
    });
    return McpViewState(
      configurationSource: _configuration.state.value,
      source: _mcp.state.value,
      readIssues: errors,
    );
  }

  bool _owns(int lifetime) =>
      _alive && lifetime == _lifetime && state.asData != null;
  McpConfiguration? _server(String id) {
    final source = _configuration.state.value;
    if (!isCurrentRead(
      source.mcpConfigurations,
      source.projection.header?.reference,
      source.projection.stamp?.origin,
    )) {
      return null;
    }
    return displayReadValue(source.mcpConfigurations)
        ?.where((value) => value.id == id)
        .firstOrNull;
  }

  McpServerDraft? _draft(String id) {
    final previous = state.requireValue.drafts[id];
    if (previous != null) return previous;
    final value = _server(id);
    return value == null
        ? null
        : McpServerDraft(
            enabled: value.configuration != McpConfigurationState.disabled,
            endpoint: value.endpoint,
          );
  }

  void _replace(String id, McpServerDraft draft, [int? clock]) =>
      state = AsyncData(
        state.requireValue.copyWith(
          latestIntent: clock ?? state.requireValue.latestIntent,
          drafts: {...state.requireValue.drafts, id: draft},
        ),
      );

  void setVisible(bool value) {
    if (!_alive || _sealed) return;
    _visible = value;
    _reads.visible(value);
    if (value &&
        state.asData?.value.drafts.values.any(
              (draft) => draft.dirty.isNotEmpty,
            ) ==
            true) {
      _registration ??= ref
          .read(applicationEditProducerRegistryProvider)
          .register(this);
    }
  }

  void setEnabled(String id, bool enabled) {
    if (!_alive || !_visible || _sealed || _server(id) == null) return;
    final draft = _draft(id);
    if (draft == null || draft.enabled == enabled) return;
    _registration ??= ref
        .read(applicationEditProducerRegistryProvider)
        .register(this);
    final revision = state.requireValue.latestIntent + 1;
    _replace(
      id,
      draft.copyWith(
        enabled: enabled,
        dirty: {...draft.dirty, McpConfigField.enabled},
        revisions: {...draft.revisions, McpConfigField.enabled: revision},
      ),
      revision,
    );
    _dispatch(id, McpConfigField.enabled);
  }

  void setEndpoint(String id, String raw) {
    if (!_alive || !_visible || _sealed) return;
    final config = _server(id);
    if (config == null || config.mutationPolicy == 'lockedIdentity') return;
    final draft = _draft(id)!;
    if (draft.endpoint == raw) return;
    _registration ??= ref
        .read(applicationEditProducerRegistryProvider)
        .register(this);
    final revision = state.requireValue.latestIntent + 1;
    _replace(
      id,
      draft.copyWith(
        endpoint: raw,
        dirty: {...draft.dirty, McpConfigField.endpoint},
        revisions: {...draft.revisions, McpConfigField.endpoint: revision},
      ),
      revision,
    );
    _schedule(id);
  }

  void setComposing(String id, bool value) {
    if (!_alive ||
        !_visible ||
        _sealed ||
        _server(id)?.mutationPolicy == 'lockedIdentity') {
      return;
    }
    final draft = _draft(id);
    if (draft == null) return;
    _replace(id, draft.copyWith(composing: value));
    if (value) {
      _timers.remove(id)?.cancel();
    } else if (draft.dirty.contains(McpConfigField.endpoint)) {
      _schedule(id);
    }
  }

  void _schedule(String id) {
    _timers.remove(id)?.cancel();
    if (_draft(id)?.composing ?? true) return;
    _timers[id] = Timer(const Duration(milliseconds: 650), () {
      _timers.remove(id);
      if (!_sealed) _dispatch(id, McpConfigField.endpoint);
    });
  }

  void commit(String id, McpConfigField field) {
    if (!_alive || !_visible || _sealed) return;
    _timers.remove(id)?.cancel();
    final draft = _draft(id);
    if (draft == null) return;
    if (draft.actions[field]?.outcome == SettingsActionOutcome.rejected) {
      final revision = state.requireValue.latestIntent + 1;
      _replace(
        id,
        draft.copyWith(revisions: {...draft.revisions, field: revision}),
        revision,
      );
    }
    _dispatch(id, field);
  }

  void leave() {
    _visible = false;
    _reads.visible(false);
    _handoff();
    _registration?.unregister();
    _registration = null;
  }

  @override
  void sealAndHandoff() {
    if (_sealed) return;
    _sealed = true;
    _visible = false;
    _reads.visible(false);
    _handoff();
  }

  void _handoff() {
    for (final timer in _timers.values) {
      timer.cancel();
    }
    _timers.clear();
    if (!_alive || state.asData == null) return;
    for (final id in state.requireValue.drafts.keys.toList()) {
      for (final field in McpConfigField.values) {
        _dispatch(id, field);
      }
    }
  }

  void _dispatch(String id, McpConfigField field) {
    if (!_alive || state.asData == null) return;
    final frozen = _draft(id);
    if (frozen == null ||
        !frozen.dirty.contains(field) ||
        (field == McpConfigField.endpoint && frozen.composing)) {
      return;
    }
    final intent = frozen.revisions[field]!;
    if (frozen.actions[field]?.intent == intent) return;
    final lifetime = _lifetime;
    final configuration = _configuration;
    final updateField = switch (field) {
      McpConfigField.enabled => SettingsFieldUpdate.mcpServerEnabled(
        id: id,
        value: frozen.enabled,
      ),
      McpConfigField.endpoint => SettingsFieldUpdate.mcpServerEndpoint(
        id: id,
        endpoint: frozen.endpoint,
      ),
    };
    _replace(
      id,
      frozen.copyWith(
        actions: {
          ...frozen.actions,
          field: SettingsAction(intent: intent, pending: true),
        },
      ),
    );
    bool owns() =>
        _owns(lifetime) &&
        state.requireValue.drafts[id]?.actions[field]?.intent == intent;
    void update(SettingsAction action) {
      if (!owns()) return;
      final current = state.requireValue.drafts[id]!;
      _replace(
        id,
        current.copyWith(actions: {...current.actions, field: action}),
      );
      state = AsyncData(_adopt(state.requireValue));
    }

    _writes.remove((id, field))?.cancel();
    unawaited(
      _execute<Unit>(
        () => configuration.applyField(updateField),
        intent,
        owns,
        update,
        (observation) => _writes[(id, field)] = observation,
      ),
    );
  }

  /// Publishes the latest configuration/runtime sources at once.
  void _publishSources() {
    state = AsyncData(
      _adopt(
        state.requireValue.copyWith(
          configurationSource: _configuration.state.value,
          source: _mcp.state.value,
        ),
      ),
    );
    _reads.refresh();
  }

  McpViewState _adopt(McpViewState value) {
    final source = value.configurationSource;
    if (!isCurrentRead(
      source.mcpConfigurations,
      source.projection.header?.reference,
      source.projection.stamp?.origin,
    )) {
      return value;
    }
    final configurations = displayReadValue(source.mcpConfigurations)!;
    final drafts = {...value.drafts};
    for (final entry in drafts.entries.toList()) {
      final canonical = configurations
          .where((config) => config.id == entry.key)
          .firstOrNull;
      if (canonical == null) continue;
      final draft = entry.value;
      final dirty = {...draft.dirty};
      for (final field in draft.dirty) {
        final action = draft.actions[field];
        if (!(action?.succeeded ?? false) ||
            action!.intent != draft.revisions[field]) {
          continue;
        }
        if (field == McpConfigField.enabled
            ? draft.enabled ==
                  (canonical.configuration != McpConfigurationState.disabled)
            : draft.endpoint == canonical.endpoint) {
          dirty.remove(field);
        }
      }
      drafts[entry.key] = draft.copyWith(
        dirty: dirty,
        enabled: dirty.contains(McpConfigField.enabled)
            ? draft.enabled
            : canonical.configuration != McpConfigurationState.disabled,
        endpoint: dirty.contains(McpConfigField.endpoint)
            ? draft.endpoint
            : canonical.endpoint,
      );
    }
    return value.copyWith(drafts: drafts);
  }

  Future<void> refresh() async {
    if (!_alive || !_visible || state.asData == null) return;
    final lifetime = _lifetime;
    if (_configuration.state.value.projection.header == null ||
        _mcp.state.value.projection.header == null) {
      final errors = {...state.requireValue.readIssues};
      Future<void> read(
        McpReadField field,
        Future<void> Function() query,
      ) async {
        try {
          await query();
          errors.remove(field);
        } on StudioFailure catch (error) {
          errors[field] = error;
        }
      }

      await Future.wait<void>([
        read(McpReadField.configurationStatus, _configuration.loadSourceStatus),
        read(McpReadField.runtimeStatus, _mcp.loadSourceStatus),
      ]);
      if (!_owns(lifetime)) return;
      state = AsyncData(state.requireValue.copyWith(readIssues: errors));
    }
    _reads.retry();
  }

  Future<void> loadMore() async {
    if (!_alive ||
        !_visible ||
        state.requireValue.reading.contains(McpReadField.runtime)) {
      return;
    }
    final lifetime = _lifetime;
    state = AsyncData(
      state.requireValue.copyWith(
        reading: {...state.requireValue.reading, McpReadField.runtime},
      ),
    );
    StudioFailure? failure;
    try {
      await _mcp.loadServersPage();
    } on StudioFailure catch (error) {
      failure = error;
    }
    if (!_owns(lifetime)) return;
    final errors = {...state.requireValue.readIssues};
    if (failure == null) {
      errors.remove(McpReadField.runtime);
    } else {
      errors[McpReadField.runtime] = failure;
    }
    state = AsyncData(
      state.requireValue.copyWith(
        readIssues: errors,
        reading: {...state.requireValue.reading}..remove(McpReadField.runtime),
      ),
    );
  }

  Future<void> resetServer(String id) async {
    if (!_alive ||
        !_visible ||
        (state.requireValue.resets[id]?.preventsResubmission ?? false)) {
      return;
    }
    final runtime = currentCollectionRow(
      _mcp.state.value.servers,
      _mcp.state.value.projection.stamp?.origin,
      (value) => value.id == id,
    )?.value;
    if (runtime == null || runtime.state is DisabledMcpServerState) return;
    final intent = state.requireValue.latestIntent + 1;
    final lifetime = _lifetime;
    final mcp = _mcp;
    state = AsyncData(
      state.requireValue.copyWith(
        latestIntent: intent,
        resets: {
          ...state.requireValue.resets,
          id: SettingsAction(intent: intent, pending: true),
        },
      ),
    );
    bool owns() =>
        _owns(lifetime) && state.requireValue.resets[id]?.intent == intent;
    _resets.remove(id)?.cancel();
    await _execute<McpReadTarget>(() => mcp.resetServer(id), intent, owns, (
      action,
    ) {
      if (owns()) {
        state = AsyncData(
          state.requireValue.copyWith(
            resets: {...state.requireValue.resets, id: action},
          ),
        );
      }
    }, (observation) => _resets[id] = observation);
  }

  Future<void> resetAll() async {
    if (!_alive ||
        !_visible ||
        (state.requireValue.resetAllAction?.preventsResubmission ?? false)) {
      return;
    }
    final intent = state.requireValue.latestIntent + 1;
    final lifetime = _lifetime;
    final mcp = _mcp;
    state = AsyncData(
      state.requireValue.copyWith(
        latestIntent: intent,
        resetAllAction: SettingsAction(intent: intent, pending: true),
      ),
    );
    bool owns() =>
        _owns(lifetime) && state.requireValue.resetAllAction?.intent == intent;
    _allReset?.cancel();
    await _execute<McpReadTarget>(mcp.resetAll, intent, owns, (action) {
      if (owns()) {
        state = AsyncData(state.requireValue.copyWith(resetAllAction: action));
      }
    }, (observation) => _allReset = observation);
  }

  Future<void> _execute<T>(
    OperationTicket<T> Function() admit,
    int intent,
    bool Function() owns,
    void Function(SettingsAction) update,
    void Function(Observation) retain,
  ) async {
    if (!owns()) return;
    OperationTicket<T> ticket;
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
    var action = SettingsAction(
      intent: intent,
      pending: true,
      operation: ticket.state.value,
    );
    StudioFailure? observationError;
    if (owns()) {
      try {
        final watch = ticket.state.watchLatest((operation) {
          if (owns()) {
            action = action.copyWith(operation: operation);
            update(action);
          }
        });
        if (owns()) {
          retain(watch.observation);
        } else {
          watch.observation.cancel();
        }
      } on StudioFailure catch (error) {
        observationError = error;
      }
      action = action.copyWith(observationError: observationError);
      update(action);
    }
    final result = await ticket.result;
    if (!owns()) return;
    action = settledSettingsAction(
      intent,
      result,
      operation: ticket.state.value,
    ).copyWith(observationError: observationError);
    update(action);
    _reads.refresh();
  }
}
