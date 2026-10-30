import 'dart:async';

import '../../../models.dart';
import '../../../studio_ports.dart';
import '../../../anywork_client.dart'
    show OperationHandle, OperationState, Observation;
import '../anywork_client.dart';
import '../stores/domain_sync.dart';
import 'command_lane.dart';
import '../../../accounts_ports.dart'
    show
        SettingsWriteCoordinator,
        SettingsWriteOwner,
        SettingsWriteOwnerChanged;

class SettingsCommands {
  SettingsCommands(this._client);
  final AnyworkClient _client;
  SettingsWriteCoordinator get _lane => _client.settingsWrites;

  Future<SettingsStateSnapshot> applySettingsField(
    SettingsFieldCommand command, {
    String? mutationKey,
  }) {
    return _run(
      mutationKey ?? settingsFieldMutationKey(command),
      target: settingsFieldTarget(command),
      (revision, operationId) =>
          _api.applySettingsField(revision, command, operationId: operationId),
    );
  }

  Future<void> setModeModelField({
    ThreadModeId? mode,
    required String accountId,
    required String modelId,
  }) async {
    if (mode == null) return;
    await applySettingsField(
      ModeModelCommand(modeId: mode.id, accountId: accountId, modelId: modelId),
      mutationKey: 'new-thread-route:model:${mode.id}',
    );
  }

  Future<void> setModeReasoningEffortField({
    ThreadModeId? mode,
    required String? effort,
  }) async {
    if (mode == null) return;
    await applySettingsField(
      ModeReasoningEffortCommand(modeId: mode.id, effort: effort),
      mutationKey: 'new-thread-route:effort:${mode.id}',
    );
  }

  Future<void> setRoleModelField({
    required String roleKey,
    required String accountId,
    required String modelId,
  }) {
    return applySettingsField(
      RoleModelCommand(role: roleKey, accountId: accountId, modelId: modelId),
      mutationKey: 'agent-role:model:$roleKey',
    );
  }

  Future<void> setRoleReasoningEffortField({
    required String roleKey,
    required String? effort,
  }) {
    return applySettingsField(
      RoleReasoningEffortCommand(role: roleKey, effort: effort),
      mutationKey: 'agent-role:effort:$roleKey',
    );
  }

  Future<void> setSystemAgentEnabled({
    required String profileId,
    required bool enabled,
  }) async {
    await _run(
      'system-agent:$profileId',
      target: CommandTarget(label: profileId, enabled: enabled),
      (revision, operationId) => _api.setSystemAgentEnabled(
        operationId: operationId,
        expectedSettingsRevision: revision,
        profileId: profileId,
        enabled: enabled,
      ),
    );
  }

  Future<void> saveUserAgentProfile(AgentProfileDraft draft) async {
    await _run(
      'user-agent-profile:${draft.id}',
      target: CommandTarget(label: draft.id),
      (revision, operationId) =>
          _api.saveUserAgentProfile(revision, draft, operationId: operationId),
    );
  }

  Future<void> setPermissionMode(PermissionMode mode) async {
    await _run(
      'permission-mode',
      target: CommandTarget(label: mode.name),
      (revision, operationId) => _api.saveRuntimePermissionMode(
        revision,
        mode,
        operationId: operationId,
      ),
    );
  }

  /// 只刷新事实源，不重放保存。失败时保留调用方原来的冲突错误。
  Future<SettingsStateSnapshot?> refreshCanonical({
    SettingsWriteOwner? owner,
  }) async {
    final captured = owner ?? _lane.captureOwner();
    _lane.requireOwner(captured);
    try {
      final snapshot = await _api.readSettingsState();
      // The read carries no owner stamp itself. Never attach a retired read to
      // whatever runtime epoch happens to be current when its future completes.
      _lane.requireOwner(captured);
      _client.acceptSettingsSnapshot(snapshot, owner: captured);
      return snapshot;
    } catch (_) {
      _lane.requireOwner(captured);
      return null;
    }
  }

  StudioTransport get _api => _client.transport;

  final Map<OperationId, Observation> _confirmations = {};

  Future<SettingsStateSnapshot> _run(
    String key,
    Future<SettingsCommandReply> Function(int revision, OperationId operationId)
    request, {
    CommandTarget target = const CommandTarget(),
  }) {
    if (_client.isClosed) return Future.error(StateError('Client is closed'));
    final owner = _lane.captureOwner();
    var issued = false;
    Object? requestFailure;
    // Latest intent is visible before queueing. An older ACK may still update
    // canonical and its own operation record, but cannot erase this intent.
    final operation = _client.mutations.begin(
      target: 'settings:$key',
      observationOwner: owner,
    );
    final store = _client.settings;
    store.beginCommand(key, target);
    return _lane.enqueue(() async {
      try {
        _lane.requireOwner(owner);
        final reply = await retryRevisionConflict(() async {
          _lane.requireOwner(owner);
          final revision = await _expectedSettingsRevision(owner);
          _lane.requireOwner(owner);
          issued = true;
          requestFailure = null;
          try {
            return await request(revision, operation.id);
          } catch (error) {
            requestFailure = error;
            rethrow;
          }
        }, refresh: () async => await refreshCanonical(owner: owner) != null);
        if (reply.receipt.operationId != operation.id) {
          throw const StudioFailure(
            code: StudioFailureCode.protocol,
            message: 'Settings receipt does not belong to this operation',
            retryable: false,
            correlationId: 'client-settings-receipt',
          );
        }
        // Qualification was bound at admission. Retain the real receipt even
        // if reduction synchronously reconnects, without enabling old proofs.
        operation.accept(reply.receipt.toCommitReceipt());
        _lane.requireOwner(owner);
        _client.acceptSettingsReply(reply, owner: owner);
        _lane.requireOwner(owner);
        _confirm(key, operation, owner);
        return reply.snapshot;
      } catch (error) {
        if (operation.state.value.receipt != null) {
          operation.syncFailed(error);
        } else if (_knownRejection(error) ||
            error is SettingsWriteOwnerChanged &&
                (!issued || _knownRejection(requestFailure))) {
          operation.reject(requestFailure ?? error);
        } else {
          operation.unknownOutcome(error);
        }
        if (!_client.isClosed &&
            _lane.isCurrentOwner(owner) &&
            _isLatest(operation)) {
          store.failCommand(
            key,
            typedCommandFailure(error, correlationId: 'client-settings'),
            target: target,
          );
        }
        rethrow;
      }
    });
  }

  bool _isLatest(OperationHandle operation) =>
      _client.mutations.latest(operation.state.value.target)?.id ==
      operation.id;

  void _confirm(
    String key,
    OperationHandle operation,
    SettingsWriteOwner owner,
  ) {
    if (_client.isClosed) return;
    void settle(OperationState result) {
      if (!result.observed && result.failurePhase == null) return;
      _confirmations.remove(operation.id)?.cancel();
      if (_client.isClosed ||
          !_lane.isCurrentOwner(owner) ||
          !_isLatest(operation))
        return;
      if (result.observed) _client.settings.clearCommand(key);
    }

    if (operation.state.value.observed) {
      settle(operation.state.value);
      return;
    }
    final watched = operation.state.watchLatest(settle);
    _confirmations[operation.id] = watched.observation;
    settle(watched.value);
  }

  void closeObservations() {
    for (final observation in _confirmations.values) {
      observation.cancel();
    }
    _confirmations.clear();
  }

  Future<void> close() {
    return _lane.close();
  }

  Future<int> _expectedSettingsRevision(SettingsWriteOwner owner) async {
    _lane.requireOwner(owner);
    final current = _client.settings.state;
    if (_client.settingsWrites.stamp case final stamp?) return stamp.revision;
    if (current.configLoaded) return current.settingsRevision;
    final refreshed = await refreshCanonical(owner: owner);
    _lane.requireOwner(owner);
    final loaded = _client.settings.state;
    if (refreshed == null || !loaded.configLoaded) {
      throw _settingsNotReady;
    }
    return loaded.settingsRevision;
  }
}

const StudioFailure _settingsNotReady = StudioFailure(
  code: StudioFailureCode.notInitialized,
  message: 'Settings are not available yet',
  retryable: false,
  correlationId: 'client-settings-not-ready',
);

String settingsFieldMutationKey(SettingsFieldCommand command) =>
    switch (command) {
      DelegationModeCommand() => 'delegation:mode',
      DelegationPreferenceCommand() => 'delegation:preference',
      InstructionBaseOverrideCommand() => 'instructions:base-override',
      InstructionDeveloperCommand() => 'instructions:developer',
      InstructionUserCommand() => 'instructions:user',
      ProjectDocMaxBytesCommand() => 'instructions:project-doc-max-bytes',
      ProjectDocFallbackFilenamesCommand() =>
        'instructions:project-doc-fallback-filenames',
      SkillsEnabledCommand() => 'skills:enabled',
      SkillsAutoLearnCommand() => 'skills:auto-learn',
      SkillsSystemEnabledCommand() => 'skills:system-enabled',
      SkillsProjectDirCommand() => 'skills:project-dir',
      SkillsUserDirCommand() => 'skills:user-dir',
      SkillsExternalDirsCommand() => 'skills:external-dirs',
      SkillsDisabledCommand() => 'skills:disabled',
      SkillsAutoLearnMinToolCallsCommand() =>
        'skills:auto-learn-min-tool-calls',
      McpServerEnabledCommand(:final id) => 'mcp:$id:enabled',
      McpServerTransportCommand(:final id) => 'mcp:$id:transport',
      McpServerEndpointCommand(:final id) => 'mcp:$id:endpoint',
      GeneralFollowActiveTurnCommand() => 'general:follow-active-turn',
      GeneralCompactTimelineCommand() => 'general:compact-timeline',
      GeneralLanguageCommand() => 'general:language',
      GeneralSidebarWidthCommand() => 'general:sidebar-width',
      GeneralPinnedThreadIdsCommand() => 'general:pinned-thread-ids',
      GeneralPinnedProjectIdsCommand() => 'general:pinned-project-ids',
      WebSearchModeCommand() => 'web-search:mode',
      WebSearchContextSizeCommand() => 'web-search:context-size',
      WebSearchAllowedDomainsCommand() => 'web-search:allowed-domains',
      WebSearchCountryCommand() => 'web-search:country',
      WebSearchRegionCommand() => 'web-search:region',
      WebSearchCityCommand() => 'web-search:city',
      WebSearchTimezoneCommand() => 'web-search:timezone',
      DeepSeekWebSearchEnabledCommand() => 'deepseek:web-search-enabled',
      DeepSeekWebFetchEnabledCommand() => 'deepseek:web-fetch-enabled',
      ModeModelCommand(:final modeId) => 'mode-route:model:$modeId',
      ModeReasoningEffortCommand(:final modeId) => 'mode-route:effort:$modeId',
      RoleModelCommand(:final role) => 'agent-role:model:$role',
      RoleReasoningEffortCommand(:final role) => 'agent-role:effort:$role',
    };

CommandTarget settingsFieldTarget(
  SettingsFieldCommand command,
) => switch (command) {
  ModeModelCommand(:final accountId, :final modelId) => CommandTarget(
    accountId: accountId,
    modelId: modelId,
  ),
  RoleModelCommand(:final accountId, :final modelId) => CommandTarget(
    accountId: accountId,
    modelId: modelId,
  ),
  ModeReasoningEffortCommand(:final effort) => CommandTarget(effort: effort),
  RoleReasoningEffortCommand(:final effort) => CommandTarget(effort: effort),
  _ => const CommandTarget(),
};

bool _knownRejection(Object? error) =>
    error is StudioFailure &&
    switch (error.code) {
      StudioFailureCode.invalidArgument ||
      StudioFailureCode.notFound ||
      StudioFailureCode.busy ||
      StudioFailureCode.conflict ||
      StudioFailureCode.staleRevision ||
      StudioFailureCode.permissionDenied ||
      StudioFailureCode.overloaded ||
      StudioFailureCode.notInitialized => true,
      _ => false,
    };
