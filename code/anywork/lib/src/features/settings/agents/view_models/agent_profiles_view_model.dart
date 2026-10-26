import 'dart:async';

import 'package:anywork_client/configuration.dart';
import 'package:anywork_client/models.dart';
import 'package:anywork_client/operations.dart';
import 'package:anywork_client/recovery.dart';
import 'package:anywork_client/resources.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../../app/app_bindings.dart';
import '../../state/editor_keys.dart';
import '../../state/settings_action.dart';
import '../../state/settings_navigation_state.dart';
import '../../view_models/collection_values.dart';
import '../../view_models/coalesced_publish.dart';
import '../../view_models/settings_navigation_view_model.dart';
import '../../view_models/settings_tab_lifecycle.dart';
import '../state/agent_profiles_state.dart';
import 'agent_profiles_visible_reads.dart';
import 'agent_role_visible_reads.dart';
import 'profile_routes.dart';

part 'agent_profiles_view_model.g.dart';

@Riverpod(keepAlive: true)
class AgentProfilesViewModel extends _$AgentProfilesViewModel {
  late ConfigurationRepository _configuration;
  late ModelsRepository _models;
  late RecoveryRepository _recovery;
  late AgentProfilesVisibleReads _reads;
  late AgentRoleVisibleReads _roleReads;
  final _observations = <Observation>[];
  final _profileObservations = <(String, AgentProfileAction), Observation>{};
  final _cleanupObservations = <(WorktreeOwner, String, int), Observation>{};
  Observation? _retryObservation;
  int _lifetime = 0;
  int _editorId = 0;
  bool _alive = true;
  bool _visible = true;

  @override
  Future<AgentProfilesViewState> build() async {
    _alive = true;
    final lifetime = ++_lifetime;
    _configuration = ref.watch(configurationRepositoryProvider);
    _models = ref.watch(modelsRepositoryProvider);
    _recovery = ref.watch(recoveryRepositoryProvider);
    _reads = AgentProfilesVisibleReads(_configuration, _models, _recovery, (
      field,
      error,
      current,
      reading,
    ) {
      if (!_owns(lifetime)) return;
      final errors = {...state.requireValue.readIssues};
      if (current) {
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
    final roleReads = _roleReads = AgentRoleVisibleReads(_configuration, (
      read,
    ) {
      if (!_owns(lifetime)) return;
      state = AsyncData(
        _project(
          state.requireValue.copyWith(
            roleReads: {...state.requireValue.roleReads, read.roleId: read},
          ),
        ),
      );
    });
    final tab = ref
        .read(settingsNavigationViewModelProvider.notifier)
        .register(
          SettingsTab.agents,
          SettingsTabLifecycle(visibility: setVisible),
        );
    _visible = tab.visible;
    ref.onDispose(() {
      _alive = false;
      _lifetime++;
      _reads.dispose();
      roleReads.dispose();
      tab.unregister();
      for (final observation in _observations) {
        observation.cancel();
      }
      _observations.clear();
      for (final observation in [
        ..._profileObservations.values,
        ..._cleanupObservations.values,
      ]) {
        observation.cancel();
      }
      _profileObservations.clear();
      _cleanupObservations.clear();
      _retryObservation?.cancel();
    });
    // Sources can publish while another provider is still building; one trailing
    // microtask applies every latest source in a single publish.
    final sourcePublish = CoalescedPublish(() {
      if (_owns(lifetime)) _publishSources();
    });
    ref.onDispose(sourcePublish.dispose);
    _observations.add(
      _configuration.profiles.watchLatest((_) {
        if (_owns(lifetime)) sourcePublish.mark();
      }).observation,
    );
    _observations.add(
      _configuration.state.watchLatest((_) {
        if (_owns(lifetime)) sourcePublish.mark();
      }).observation,
    );
    _observations.add(
      _models.state.watchLatest((_) {
        if (_owns(lifetime)) sourcePublish.mark();
      }).observation,
    );
    _observations.add(
      _recovery.state.watchLatest((_) {
        if (_owns(lifetime)) sourcePublish.mark();
      }).observation,
    );
    final errors = <AgentProfilesReadField, StudioFailure>{};
    Future<void> read(
      AgentProfilesReadField field,
      Future<void> Function() action,
    ) async {
      try {
        await action();
      } on StudioFailure catch (error) {
        errors[field] = error;
      }
    }

    await Future.wait<void>([
      read(AgentProfilesReadField.profiles, () async {
        await Future.wait<void>([
          _configuration.loadProfilesPage(),
          _configuration.loadProfileDiagnostics().then((_) {}),
        ]);
      }),
      read(
        AgentProfilesReadField.configuration,
        () => _configuration.loadAccountsPage(),
      ),
      read(AgentProfilesReadField.models, () => _models.loadAccountsPage()),
      read(AgentProfilesReadField.recovery, () => _recovery.loadIssuesPage()),
      read(
        AgentProfilesReadField.profilesSource,
        _configuration.loadProfilesSourceStatus,
      ),
      read(
        AgentProfilesReadField.configurationSource,
        _configuration.loadSourceStatus,
      ),
      read(AgentProfilesReadField.modelSource, _models.loadSourceStatus),
      read(AgentProfilesReadField.recoverySource, _recovery.loadSourceStatus),
    ]);
    _reads.rememberInitialFailures();
    Future<void>(() {
      if (_owns(lifetime)) {
        _publish(
          state.requireValue.copyWith(
            source: _configuration.profiles.value,
            configurationSource: _configuration.state.value,
            modelSource: _models.state.value,
            recoverySource: _recovery.state.value,
          ),
        );
      }
    });
    return _project(
      AgentProfilesViewState(
        source: _configuration.profiles.value,
        configurationSource: _configuration.state.value,
        modelSource: _models.state.value,
        recoverySource: _recovery.state.value,
        readIssues: errors,
      ),
    );
  }

  bool _owns(int lifetime) =>
      _alive &&
      lifetime == _lifetime &&
      state.asData != null &&
      !state.isLoading &&
      !state.hasError;

  /// Publishes the latest profile/configuration/model/recovery sources at once.
  void _publishSources() {
    _publish(
      state.requireValue.copyWith(
        source: _configuration.profiles.value,
        configurationSource: _configuration.state.value,
        modelSource: _models.state.value,
        recoverySource: _recovery.state.value,
      ),
    );
  }

  void _publish(AgentProfilesViewState value) {
    state = AsyncData(_project(value));
    _reads.visible(_visible);
    _roleReads.visible(_visible);
  }

  AgentProfilesViewState _project(AgentProfilesViewState value) {
    final profiles = displayCollectionRows(value.source.profiles);
    final target = currentRoleReadTarget(value.configurationSource);
    final catalog = profileCatalogTarget(value.modelSource);
    final query = value.query.trim().toLowerCase();
    final routes = <String, SettingsRoleRoute>{};
    for (final profile in profiles.where((value) => value.system)) {
      final read = value.roleReads[profile.profileId];
      if (target == null ||
          read == null ||
          read.target != target ||
          read.pending ||
          read.error != null ||
          read.value == null) {
        continue;
      }
      final (accountId, modelId, effort, configured) = switch (read.value!) {
        ConfiguredRoleRouteRead(:final route) => (
          route.accountId,
          route.modelId,
          route.effort,
          true,
        ),
        MissingRoleRouteRead(:final suggestion) => (
          suggestion?.model.accountId ?? '',
          suggestion?.model.modelId ?? '',
          suggestion?.effort,
          false,
        ),
      };
      // Display details are optional and never determine configured/missing or
      // replace the Rust result when the independently published catalog moves.
      final account = catalog == target.catalog
          ? currentCollectionRow(
              value.modelSource.accounts,
              catalog?.origin,
              (row) => row.accountId == accountId,
            )?.value
          : null;
      final descriptor = account?.effectiveModels
          .where((model) => model.modelId == modelId)
          .firstOrNull;
      routes[profile.profileId] = SettingsRoleRoute(
        target: target,
        accountId: accountId,
        modelId: modelId,
        effort: effort,
        descriptor: descriptor,
        configured: configured,
      );
    }
    return value.copyWith(
      routes: routes,
      matchingProfileIds: [
        for (final profile in profiles)
          if ('${value.systemSearchLabels[profile.profileId] ?? profile.displayName} ${profile.profileId} ${profile.description}'
              .toLowerCase()
              .contains(query))
            profile.profileId,
      ],
    );
  }

  void setVisible(bool value) {
    if (!_alive) return;
    _visible = value;
    _reads.visible(value);
    // A tab can become visible while its initial build is awaiting other
    // fields. Do not publish/lose paired results before ViewState exists.
    if (state.asData != null && !state.isLoading && !state.hasError) {
      _roleReads.visible(value);
    }
  }

  void setQuery(String raw, {required Map<String, String> systemNames}) {
    if (_alive) {
      _publish(
        state.requireValue.copyWith(
          query: raw,
          systemSearchLabels: Map.unmodifiable(systemNames),
        ),
      );
    }
  }

  void retryRead() {
    if (!_alive ||
        !_visible ||
        state.asData == null ||
        state.isLoading ||
        state.hasError) {
      return;
    }
    final lifetime = _lifetime;
    final configuration = _configuration;
    final models = _models;
    final recovery = _recovery;
    final reads = _reads;
    final roleReads = _roleReads;
    final profiles = configuration.profiles.value.projection;
    final config = configuration.state.value.projection;
    final catalog = models.state.value.projection;
    final recoverySource = recovery.state.value.projection;
    bool owns() =>
        _owns(lifetime) &&
        identical(_configuration, configuration) &&
        identical(_models, models) &&
        identical(_recovery, recovery) &&
        identical(_reads, reads) &&
        identical(_roleReads, roleReads);
    bool sameConfigurationTarget() {
      final current = configuration.state.value.projection;
      return current.stamp?.origin == config.stamp?.origin &&
          current.header?.reference == config.header?.reference &&
          current.header?.source.status == config.header?.source.status;
    }

    reads.retry();
    if (!owns() || !_visible) return;
    roleReads.retry();
    if (!owns() || !_visible) return;
    Future<void> bootstrap(
      AgentProfilesReadField field,
      Future<void> Function() read, {
      bool Function()? isCurrent,
    }) async {
      if (!owns() ||
          !_visible ||
          isCurrent?.call() == false ||
          state.requireValue.reading.contains(field)) {
        return;
      }
      state = AsyncData(
        state.requireValue.copyWith(
          reading: {...state.requireValue.reading, field},
        ),
      );
      if (!owns()) return;
      if (!_visible || isCurrent?.call() == false) {
        state = AsyncData(
          state.requireValue.copyWith(
            reading: {...state.requireValue.reading}..remove(field),
          ),
        );
        return;
      }
      StudioFailure? failure;
      try {
        await read();
      } on StudioFailure catch (error) {
        failure = error;
      }
      if (!owns()) return;
      final errors = {...state.requireValue.readIssues};
      if (failure == null) {
        errors.remove(field);
      } else {
        errors[field] = failure;
      }
      state = AsyncData(
        state.requireValue.copyWith(
          reading: {...state.requireValue.reading}..remove(field),
          readIssues: errors,
        ),
      );
    }

    if (profiles.header?.reference == null) {
      unawaited(
        bootstrap(AgentProfilesReadField.profiles, () async {
          await Future.wait<void>([
            configuration.loadProfilesPage(),
            configuration.loadProfileDiagnostics().then((_) {}),
          ]);
        }),
      );
      unawaited(
        bootstrap(
          AgentProfilesReadField.profilesSource,
          configuration.loadProfilesSourceStatus,
        ),
      );
    }
    if (config.header?.reference == null) {
      unawaited(
        bootstrap(
          AgentProfilesReadField.configuration,
          () => configuration.loadAccountsPage(),
          isCurrent: sameConfigurationTarget,
        ),
      );
    }
    if (owns() &&
        _visible &&
        sameConfigurationTarget() &&
        (config.sync.phase != ResourceSyncPhase.ready ||
            config.header?.reference == null)) {
      final origin = config.stamp?.origin;
      final status = config.header?.source.status;
      if (origin != null && status != null) {
        reads.retryConfigurationSource((origin, status));
      } else {
        unawaited(
          bootstrap(
            AgentProfilesReadField.configurationSource,
            configuration.loadSourceStatus,
            isCurrent: sameConfigurationTarget,
          ),
        );
      }
    }
    if (catalog.header?.reference == null) {
      unawaited(
        bootstrap(
          AgentProfilesReadField.models,
          () => models.loadAccountsPage(),
        ),
      );
      unawaited(
        bootstrap(AgentProfilesReadField.modelSource, models.loadSourceStatus),
      );
    }
    if (recoverySource.header?.reference == null) {
      unawaited(
        bootstrap(
          AgentProfilesReadField.recovery,
          () => recovery.loadIssuesPage(),
        ),
      );
      unawaited(
        bootstrap(
          AgentProfilesReadField.recoverySource,
          recovery.loadSourceStatus,
        ),
      );
    }
  }

  ProfileEditorKey? beginEditor([String? id]) {
    if (!_alive || state.requireValue.editor != null) return null;
    if (id != null &&
        !displayCollectionRows(state.requireValue.source.profiles)
            .any((value) => value.profileId == id && !value.system)) {
      return null;
    }
    final key = ProfileEditorKey(editorId: ++_editorId, profileId: id);
    state = AsyncData(state.requireValue.copyWith(editor: key));
    return key;
  }

  void closeEditor(ProfileEditorKey key) {
    if (_alive && state.requireValue.editor == key) {
      state = AsyncData(state.requireValue.copyWith(editor: null));
    }
  }

  Future<void> loadMore() async {
    if (!_alive || !_visible || state.requireValue.reading.isNotEmpty) return;
    final lifetime = _lifetime;
    state = AsyncData(
      state.requireValue.copyWith(
        reading: {
          AgentProfilesReadField.profiles,
          AgentProfilesReadField.configuration,
          AgentProfilesReadField.models,
          AgentProfilesReadField.recovery,
        },
      ),
    );
    final issues = <AgentProfilesReadField, StudioFailure>{};
    Future<void> read(
      AgentProfilesReadField field,
      Future<void> Function() action,
    ) async {
      try {
        await action();
      } on StudioFailure catch (error) {
        issues[field] = error;
      }
    }

    await Future.wait<void>([
      read(
        AgentProfilesReadField.profiles,
        () => _configuration.loadProfilesPage(),
      ),
      read(
        AgentProfilesReadField.configuration,
        () => _configuration.loadAccountsPage(),
      ),
      read(AgentProfilesReadField.models, () => _models.loadAccountsPage()),
      read(AgentProfilesReadField.recovery, () => _recovery.loadIssuesPage()),
    ]);
    if (_owns(lifetime)) {
      _publish(
        state.requireValue.copyWith(
          reading: {},
          readIssues: {...state.requireValue.readIssues, ...issues},
        ),
      );
    }
  }

  Future<void> setSystemEnabled(String id, bool enabled) async {
    if (!_alive) return;
    final profile = currentCollectionRow(
      _configuration.profiles.value.profiles,
      _configuration.profiles.value.projection.stamp?.origin,
      (profile) => profile.profileId == id,
    )?.value;
    if (profile == null || !profile.system) {
      return;
    }
    await _profileAction(
      id,
      AgentProfileAction.enabled,
      () => _configuration.setSystemProfileEnabled(id, enabled),
    );
  }

  Future<void> setRoleModel(
    String role,
    String accountId,
    String modelId,
  ) async {
    if (!_alive || !_roleEditable(role)) return;
    final configuration = _configuration;
    final source = _models.state.value;
    final account = currentCollectionRow(
      source.accounts,
      source.projection.stamp?.origin,
      (account) => account.accountId == accountId,
    )?.value;
    if (account == null ||
        !account.effectiveModels.any(
          (model) => model.modelId == modelId && supportsProfileText(model),
        )) {
      return;
    }
    await _profileAction(
      role,
      AgentProfileAction.model,
      () => configuration.applyField(
        SettingsFieldUpdate.roleModel(
          role: role,
          accountId: accountId,
          modelId: modelId,
        ),
      ),
    );
  }

  Future<void> setRoleEffort(String role, String? value) async {
    if (!_alive || value == null || !_roleEditable(role)) return;
    final configuration = _configuration;
    final route = state.requireValue.routes[role];
    if (!(route?.descriptor?.reasoning?.candidates.contains(value) ?? false)) {
      return;
    }
    await _profileAction(
      role,
      AgentProfileAction.effort,
      () => configuration.applyField(
        SettingsFieldUpdate.roleReasoningEffort(role: role, effort: value),
      ),
    );
  }

  Future<void> _profileAction(
    String id,
    AgentProfileAction field,
    OperationTicket<Unit> Function() admit,
  ) async {
    final related = field == AgentProfileAction.enabled
        ? [AgentProfileAction.enabled]
        : [AgentProfileAction.model, AgentProfileAction.effort];
    if (related.any(
      (action) =>
          state.requireValue.actions[(id, action)]?.preventsResubmission ??
          false,
    )) {
      return;
    }
    final lifetime = _lifetime;
    final intent = state.requireValue.latestIntent + 1;
    state = AsyncData(
      state.requireValue.copyWith(
        latestIntent: intent,
        actions: {
          ...state.requireValue.actions,
          (id, field): SettingsAction(intent: intent, pending: true),
        },
      ),
    );
    bool owns() =>
        _owns(lifetime) &&
        state.requireValue.actions[(id, field)]?.intent == intent;
    _profileObservations.remove((id, field))?.cancel();
    await _run<Unit>(admit, intent, owns, (action) {
      if (owns()) {
        state = AsyncData(
          state.requireValue.copyWith(
            actions: {...state.requireValue.actions, (id, field): action},
          ),
        );
      }
    }, (observation) => _profileObservations[(id, field)] = observation);
  }

  bool _roleEditable(String role) {
    final target = currentRoleReadTarget(_configuration.state.value);
    final read = state.requireValue.roleReads[role];
    return target != null &&
        read?.target == target &&
        read?.value != null &&
        read?.pending == false &&
        read?.error == null &&
        currentCollectionRow(
              _configuration.profiles.value.profiles,
              _configuration.profiles.value.projection.stamp?.origin,
              (profile) => profile.profileId == role && profile.system,
            ) !=
            null;
  }

  bool _currentRecoveryIssue(RecoveryIssue issue) {
    final source = _recovery.state.value;
    return source.projection.sync.phase == ResourceSyncPhase.ready &&
        source.projection.header?.source.brief is ReadyObservedBrief &&
        currentCollectionRow(
              source.issues,
              source.projection.stamp?.origin,
              (current) => current.id == issue.id && current == issue,
            ) !=
            null;
  }

  Future<void> cleanup(RecoveryIssue issue) async {
    if (!_alive ||
        !issue.availableActions.contains(RecoveryAction.cleanupWorktree) ||
        !_currentRecoveryIssue(issue)) {
      return;
    }
    final worktree = issue.worktree;
    if (worktree == null) return;
    final recovery = _recovery;
    final key = (
      worktree.ownerKind,
      worktree.ownerThreadId,
      worktree.leaseRevision,
    );
    if ((state.requireValue.cleanupActions[key]?.preventsResubmission ?? false) ||
        (state.requireValue.retryRecoveryAction?.preventsResubmission ?? false)) {
      return;
    }
    final lifetime = _lifetime;
    final intent = state.requireValue.latestIntent + 1;
    state = AsyncData(
      state.requireValue.copyWith(
        latestIntent: intent,
        cleanupActions: {
          ...state.requireValue.cleanupActions,
          key: SettingsAction(intent: intent, pending: true),
        },
      ),
    );
    bool owns() =>
        _owns(lifetime) &&
        state.requireValue.cleanupActions[key]?.intent == intent;
    _cleanupObservations.remove(key)?.cancel();
    await _run<Unit>(
      () => recovery.cleanupWorktree(key.$1, key.$2, key.$3),
      intent,
      owns,
      (action) {
        if (owns()) {
          state = AsyncData(
            state.requireValue.copyWith(
              cleanupActions: {
                ...state.requireValue.cleanupActions,
                key: action,
              },
            ),
          );
        }
      },
      (observation) => _cleanupObservations[key] = observation,
    );
  }

  Future<void> retryWorktree(RecoveryIssue issue) {
    if (!_alive || !issue.canRetry || !_currentRecoveryIssue(issue)) {
      return Future<void>.value();
    }
    final worktree = issue.worktree;
    if (worktree == null ||
        state.requireValue.cleanupActions[(
              worktree.ownerKind,
              worktree.ownerThreadId,
              worktree.leaseRevision,
            )]?.preventsResubmission ==
            true) {
      return Future<void>.value();
    }
    return retryRecovery();
  }

  Future<void> retryRecovery() async {
    if (!_alive ||
        (state.requireValue.retryRecoveryAction?.preventsResubmission ??
            false)) {
      return;
    }
    final recovery = _recovery;
    final lifetime = _lifetime;
    final intent = state.requireValue.latestIntent + 1;
    state = AsyncData(
      state.requireValue.copyWith(
        latestIntent: intent,
        retryRecoveryAction: SettingsAction(intent: intent, pending: true),
      ),
    );
    bool owns() =>
        _owns(lifetime) &&
        state.requireValue.retryRecoveryAction?.intent == intent;
    _retryObservation?.cancel();
    await _run<RecoveryReadTarget>(recovery.retry, intent, owns, (action) {
      if (owns()) {
        state = AsyncData(
          state.requireValue.copyWith(retryRecoveryAction: action),
        );
      }
    }, (observation) => _retryObservation = observation);
  }

  Future<void> _run<T>(
    OperationTicket<T> Function() admit,
    int intent,
    bool Function() owns,
    void Function(SettingsAction) update,
    void Function(Observation) retain,
  ) async {
    // Publishing local pending may synchronously replace/dispose this owner.
    // Only reject before admission; accepted tickets stay Repository-owned.
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
    StudioFailure? observationError;
    var action = SettingsAction(
      intent: intent,
      pending: true,
      operation: ticket.state.value,
    );
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
