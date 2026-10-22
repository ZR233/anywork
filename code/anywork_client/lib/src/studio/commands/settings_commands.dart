import 'dart:async';

import '../../../models.dart';
import '../../../studio_ports.dart';
import '../../../anywork_client.dart'
    show OperationHandle, OperationState, Observation;
import '../anywork_client.dart';
import '../stores/domain_sync.dart';
import 'command_lane.dart';

class SettingsCommands {
  SettingsCommands(this._client);
  final AnyworkClient _client;
  final CommandLane _lane = CommandLane();

  /// 供同 revision 的会话 route 写入复用这条 lane，避免与配置 CAS 交叉覆盖。
  Future<T> enqueueSettingsWrite<T>(Future<T> Function() action) =>
      _lane.enqueue(action);

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

  Future<SettingsStateSnapshot> saveAccount(AccountCommand command) {
    return _run(
      'account:${command.id}',
      target: CommandTarget(accountId: command.id, label: command.name),
      (revision, operationId) =>
          _api.saveAccount(revision, command, operationId: operationId),
    );
  }

  /// 只持有目标模型意图；在串行 lane 内、每次 CAS 重试时都基于最新 canonical 重建。
  /// 其它模型覆盖、目录、endpoint 和凭据不会被发起输入时的旧快照覆盖。
  Future<SettingsStateSnapshot> setModelAutoCompactLimit(
    String accountId,
    String modelId,
    int? limit,
  ) {
    if (limit != null && limit <= 0) {
      return Future.error(
        ArgumentError.value(limit, 'limit', 'Must be positive'),
      );
    }
    return _run(
      'model-auto-compact:${accountId.length}:$accountId:$modelId',
      target: CommandTarget(accountId: accountId, modelId: modelId),
      (revision, operationId) {
        final account = _client.settings.state.canonical?.accounts
            .where((account) => account.id == accountId)
            .firstOrNull;
        final model = account?.models
            .where((model) => model.modelId == modelId)
            .firstOrNull;
        if (account == null || model == null) {
          throw StudioFailure(
            code: StudioFailureCode.notFound,
            message: 'Account model is unavailable: $accountId/$modelId',
            retryable: false,
            correlationId: 'client-model-auto-compact',
          );
        }
        final updated = account.withAutoCompactLimit(
          AccountModelAutoCompactView(modelId: modelId, overrideLimit: limit),
        );
        final command = AccountCommandBuilder.buildAccount(
          updated,
          secret: const AccountSecretCommand.preserve(),
        );
        return _api.saveAccount(revision, command, operationId: operationId);
      },
    );
  }

  Future<SettingsStateSnapshot> removeAccountModel(
    String accountId,
    String modelId,
  ) {
    return _run(
      'account-model:${accountId.length}:$accountId:$modelId',
      target: CommandTarget(accountId: accountId, modelId: modelId),
      (revision, _) => _api.removeAccountModel(revision, accountId, modelId),
    );
  }

  Future<SettingsStateSnapshot> removeAccount(
    String accountId, {
    String? replacementAccountId,
  }) {
    return _run(
      'account:$accountId',
      target: CommandTarget(accountId: accountId, label: replacementAccountId),
      (revision, operationId) => _api.removeAccount(
        revision,
        accountId,
        replacementAccountId: replacementAccountId,
        operationId: operationId,
      ),
    );
  }

  /// 保存（或更新）一个 ACP 接入配置。
  ///
  /// 与 Native 账号写入共用同一 settings CAS lane：两种账号类型不会交叉覆盖配置
  /// revision，冲突按同一规则刷新 canonical 后重试。
  Future<SettingsStateSnapshot> saveAcpAccount(AcpAccountUpdateView account) {
    return _run(
      'acp-account:${account.accountId}',
      target: CommandTarget(accountId: account.accountId, label: account.name),
      (revision, operationId) =>
          _api.saveAcpAccount(revision, account, operationId: operationId),
    );
  }

  /// 删除一个 ACP 接入配置；删除不注销官方程序持有的凭据。
  Future<SettingsStateSnapshot> removeAcpAccount(String accountId) {
    return _run(
      'acp-account:$accountId',
      target: CommandTarget(accountId: accountId),
      (revision, operationId) =>
          _api.removeAcpAccount(revision, accountId, operationId: operationId),
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

  Future<void> setDefaultAccount(String accountId) async {
    await _run('default-account', target: CommandTarget(accountId: accountId), (
      revision,
      operationId,
    ) {
      final accounts = _client.settings.state.canonical?.accounts ?? const [];
      if (!accounts.any((account) => account.id == accountId)) {
        throw StateError('Account is unavailable: $accountId');
      }
      return _api.setDefaultAccount(
        revision,
        accountId,
        operationId: operationId,
      );
    });
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
  Future<SettingsStateSnapshot?> refreshCanonical() async {
    try {
      final snapshot = await _api.readSettingsState();
      if (!_client.isClosed) {
        _client.settings.merge(snapshot);
      }
      return snapshot;
    } catch (_) {
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
    // Latest intent is visible before queueing. An older ACK may still update
    // canonical and its own operation record, but cannot erase this intent.
    final operation = _client.mutations.begin(target: 'settings:$key');
    final store = _client.settings;
    store.beginCommand(key, target);
    return _lane.enqueue(() async {
      try {
        final reply = await retryRevisionConflict(() async {
          final revision = await _expectedSettingsRevision();
          return request(revision, operation.id);
        }, refresh: () async => await refreshCanonical() != null);
        if (!_client.isClosed) store.merge(reply.snapshot);
        operation.accept(reply.receipt.toCommitReceipt());
        _confirm(key, operation);
        return reply.snapshot;
      } catch (error) {
        if (operation.state.value.receipt != null) {
          operation.syncFailed(error);
        } else if (_knownRejection(error)) {
          operation.reject(error);
        } else {
          operation.unknownOutcome(error);
        }
        if (!_client.isClosed && _isLatest(operation)) {
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

  void _confirm(String key, OperationHandle operation) {
    if (_client.isClosed) return;
    void settle(OperationState result) {
      if (!result.observed && result.failurePhase == null) return;
      _confirmations.remove(operation.id)?.cancel();
      if (_client.isClosed || !_isLatest(operation)) return;
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
    _lane.seal();
    return _lane.join();
  }

  Future<int> _expectedSettingsRevision() async {
    final current = _client.settings.state;
    if (current.configLoaded) return current.settingsRevision;
    final refreshed = await refreshCanonical();
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

bool _knownRejection(Object error) =>
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
