import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/studio_tokens.dart';

import 'package:anywork_client/studio_client.dart';

import '../../presentation/providers/client_provider.dart';
import '../../presentation/providers/lsp_store.dart';
import '../../presentation/providers/mcp_store.dart';
import '../../presentation/providers/model_performance_store.dart';
import '../../presentation/providers/provider_usage_store.dart';
import '../../presentation/providers/recovery_store.dart';
import '../../presentation/providers/settings_store.dart';
import '../../presentation/providers/skills_store.dart';
import '../../presentation/providers/bots_store.dart';
import '../../l10n/studio_l10n.dart';

export 'package:anywork_client/studio_client.dart' show BridgeSettingsScopeKind;

/// 当前可见的设置 tab 索引（由设置壳的 TabController 驱动）。
///
/// Visibility only changes display observation; Client retains topic owners and drafts.
final settingsVisibleTabProvider =
    NotifierProvider<SettingsVisibleTabNotifier, int>(
      SettingsVisibleTabNotifier.new,
      name: 'settingsVisibleTabProvider',
    );

class SettingsVisibleTabNotifier extends Notifier<int> {
  @override
  int build() => 0;

  void select(int index) {
    if (state != index) state = index;
  }
}

/// Visibility controls display observations only. AppGraph owns the corresponding
/// topics throughout the application lifetime.
void watchSettingsScope(
  WidgetRef ref, {
  required bool visible,
  required BridgeSettingsScopeKind kind,
  String? projectId,
}) {
  if (!visible) return;
  for (final topic in bridgeSettingsScopeTopics(kind, projectId)) {
    ref.watch(settingsTopicSyncProvider(topic));
  }
}

/// 静态供应商目录与启动选择由 `app/startup_facts.dart` 在 shell 挂载前写入。
/// 设置页只消费已经就绪的 canonical，不再做过渡写入。

final settingsTopicSyncProvider = Provider.autoDispose
    .family<DomainSyncStatus, ProductTopic>((ref, topic) {
      return switch (topic) {
        SettingsConfigTopic() => ref.watch(
          settingsStoreProvider.select((state) => state.configSync),
        ),
        ModelCatalogTopic() => ref.watch(
          settingsStoreProvider.select((state) => state.catalogSync),
        ),
        RecoveryTopic() => ref.watch(
          recoveryStoreProvider.select((state) => state.sync),
        ),
        AgentProfilesTopic() => ref.watch(
          settingsStoreProvider.select((state) => state.agentProfilesSync),
        ),
        McpTopic() => ref.watch(mcpStoreProvider.select((state) => state.sync)),
        LspTopic() => ref.watch(lspStoreProvider.select((state) => state.sync)),
        SkillsTopic(:final projectId) => ref.watch(
          skillsStoreProvider(projectId).select((state) => state.sync),
        ),
        AccountUsageTopic() => ref.watch(
          accountUsageStoreProvider.select((state) => state.sync),
        ),
        ModelPerformanceTopic() => ref.watch(
          modelPerformanceStoreProvider.select((state) => state.sync),
        ),
        BotsTopic() => ref.watch(
          botsStoreProvider.select((state) => state.sync),
        ),
        ProjectDirectoryTopic() ||
        ThreadDirectoryTopic() ||
        AgentDirectoryTopic() ||
        ThreadModeCatalogTopic() ||
        SessionCostsTopic() ||
        UpdaterTopic() ||
        PersistenceTopic() ||
        PersistenceQueueTopic() => const DomainSyncStatus(),
      };
    }, name: 'settingsTopicSyncProvider');

/// 单个设置页局部 topic 的传输连接提示。
///
/// 业务内容始终来自 store 的 last-known 值。connecting / ready / idle 不占布局；
/// failed 给出 retry，重连中保留原来的警告行。
class SettingsTopicStatus extends ConsumerWidget {
  const SettingsTopicStatus({required this.topic, super.key});

  final ProductTopic topic;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sync = ref.watch(settingsTopicSyncProvider(topic));
    if (sync.phase == DomainSyncPhase.idle ||
        sync.phase == DomainSyncPhase.connecting ||
        sync.phase == DomainSyncPhase.ready) {
      return const SizedBox.shrink();
    }
    final failed = sync.phase == DomainSyncPhase.failed;
    final message = sync.errorMessage?.trim();
    final label = (message == null || message.isEmpty)
        ? (failed
              ? context.l10n.settingsSshStateFailed
              : context.l10n.settingsSshStateReconnecting)
        : message;
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Icon(
            failed ? Icons.error_outline : Icons.sync_problem_outlined,
            size: 16,
            color: failed ? context.colors.error : context.statusColors.warning,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: context.text.bodySmall?.copyWith(
                color: context.colors.onSurfaceVariant,
              ),
            ),
          ),
          if (failed)
            TextButton.icon(
              key: ValueKey('settings-topic-retry-${topic.runtimeType}'),
              onPressed: () =>
                  ref.read(anyworkClientProvider).retryResource(topic),
              icon: const Icon(Icons.refresh, size: 16),
              label: Text(context.l10n.sidebarRetry),
            ),
        ],
      ),
    );
  }
}
