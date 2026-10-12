import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../domain/models/studio_models.dart';
import '../frb/studio_api.dart';
import '../repositories/studio_api_provider.dart';
import '../stores/domain_sync.dart';
import '../stores/settings_store.dart';
import 'command_lane.dart';

part 'settings_commands.g.dart';

/// 设置写入的单一串行 lane。
///
/// 每次执行读取 settingsStore 的配置 revision 作 CAS。`staleRevision` / `conflict`
/// 先刷新 canonical，再重试最多两次。成功只走 [SettingsStore.merge]；失败只写
/// 命令状态区。不乐观改 canonical，也不提供 generation map、flush 或超时。
@Riverpod(keepAlive: true)
class SettingsCommands extends _$SettingsCommands {
  final CommandLane _lane = CommandLane();

  @override
  SettingsCommandLaneState build() => const SettingsCommandLaneState();

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
      (revision) => _api.applySettingsField(revision, command),
    );
  }

  Future<SettingsStateSnapshot> saveProvider(ProviderCommand command) {
    return _run(
      'provider:${command.id}',
      target: CommandTarget(providerId: command.id, label: command.name),
      (revision) => _api.saveProvider(revision, command),
    );
  }

  Future<SettingsStateSnapshot> removeProvider(
    String providerId, {
    String? replacementProviderId,
  }) {
    return _run(
      'provider:$providerId',
      target: CommandTarget(
        providerId: providerId,
        label: replacementProviderId,
      ),
      (revision) => _api.removeProvider(
        revision,
        providerId,
        replacementProviderId: replacementProviderId,
      ),
    );
  }

  Future<void> setModeModelField({
    ThreadModeId? mode,
    required String providerId,
    required String model,
  }) async {
    if (mode == null) return;
    await applySettingsField(
      ModeModelCommand(modeId: mode.id, providerId: providerId, model: model),
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
    required String providerId,
    required String model,
  }) {
    return applySettingsField(
      RoleModelCommand(role: roleKey, providerId: providerId, model: model),
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
      (revision) => _api.setSystemAgentEnabled(
        expectedSettingsRevision: revision,
        profileId: profileId,
        enabled: enabled,
      ),
    );
  }

  Future<void> setDefaultProvider(String providerId) async {
    await _run(
      'default-provider',
      target: CommandTarget(providerId: providerId),
      (revision) {
        final providers =
            ref.read(settingsStoreProvider).canonical?.providers ?? const [];
        if (!providers.any((provider) => provider.id == providerId)) {
          throw StateError('Provider is unavailable: $providerId');
        }
        return _api.setDefaultProvider(revision, providerId);
      },
    );
  }

  Future<void> saveUserAgentProfile(AgentProfileDraft draft) async {
    await _run(
      'user-agent-profile:${draft.id}',
      target: CommandTarget(label: draft.id),
      (revision) => _api.saveUserAgentProfile(revision, draft),
    );
  }

  Future<void> setPermissionMode(PermissionMode mode) async {
    await _run(
      'permission-mode',
      target: CommandTarget(label: mode.name),
      (revision) => _api.saveRuntimePermissionMode(revision, mode),
    );
  }

  /// 只刷新事实源，不重放保存。失败时保留调用方原来的冲突错误。
  Future<SettingsStateSnapshot?> refreshCanonical() async {
    try {
      final snapshot = await _api.readSettingsState();
      if (ref.mounted) {
        ref.read(settingsStoreProvider.notifier).merge(snapshot);
      }
      return snapshot;
    } catch (_) {
      return null;
    }
  }

  StudioBridgeDataSource get _api => ref.read(studioBridgeDataSourceProvider);

  Future<SettingsStateSnapshot> _run(
    String key,
    Future<SettingsStateSnapshot> Function(int revision) request, {
    CommandTarget target = const CommandTarget(),
  }) {
    return _lane.enqueue(() async {
      final store = ref.read(settingsStoreProvider.notifier);
      store.beginCommand(key, target);
      try {
        final snapshot = await retryRevisionConflict(() async {
          final revision = await _expectedSettingsRevision();
          return request(revision);
        }, refresh: () async => await refreshCanonical() != null);
        if (!ref.mounted) return snapshot;
        store.merge(snapshot);
        store.clearCommand(key);
        return snapshot;
      } catch (error) {
        if (ref.mounted) {
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

  Future<int> _expectedSettingsRevision() async {
    final current = ref.read(settingsStoreProvider);
    if (current.configLoaded) return current.settingsRevision;
    final refreshed = await refreshCanonical();
    final loaded = ref.read(settingsStoreProvider);
    if (refreshed == null || !loaded.configLoaded) {
      throw _settingsNotReady;
    }
    return loaded.settingsRevision;
  }
}

class SettingsCommandLaneState {
  const SettingsCommandLaneState();

  @override
  bool operator ==(Object other) => other is SettingsCommandLaneState;

  @override
  int get hashCode => 0;
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
      ModeModelCommand(:final modeId) => 'mode-route:model:$modeId',
      ModeReasoningEffortCommand(:final modeId) => 'mode-route:effort:$modeId',
      RoleModelCommand(:final role) => 'agent-role:model:$role',
      RoleReasoningEffortCommand(:final role) => 'agent-role:effort:$role',
    };

CommandTarget settingsFieldTarget(
  SettingsFieldCommand command,
) => switch (command) {
  ModeModelCommand(:final providerId, :final model) => CommandTarget(
    providerId: providerId,
    model: model,
  ),
  RoleModelCommand(:final providerId, :final model) => CommandTarget(
    providerId: providerId,
    model: model,
  ),
  ModeReasoningEffortCommand(:final effort) => CommandTarget(effort: effort),
  RoleReasoningEffortCommand(:final effort) => CommandTarget(effort: effort),
  _ => const CommandTarget(),
};
