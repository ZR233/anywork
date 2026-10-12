import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/studio_tokens.dart';
import '../../data/bridge/studio_bridge.dart';
import '../../data/stores/domain_sync.dart';
import '../../data/stores/lsp_store.dart';
import '../../data/stores/mcp_store.dart';
import '../../data/stores/model_performance_store.dart';
import '../../data/stores/provider_usage_store.dart';
import '../../data/stores/recovery_store.dart';
import '../../data/stores/settings_store.dart';
import '../../data/stores/skills_store.dart';
import '../../domain/models/studio_models.dart';
import '../../l10n/studio_l10n.dart';

export '../../data/bridge/studio_bridge.dart' show BridgeSettingsScopeKind;

/// 当前可见的设置 tab 索引（由设置壳的 TabController 驱动）。
///
/// 设置页为保留编辑器草稿、搜索筛选与滚动位置，用 keep-alive 保活已访问过的 tab；
/// 但「保留 UI 状态」不等于「持有 topic 租约」。每个数据页据此只在自身可见时
/// `watch` 自己的 scope provider，隐藏时停止 `watch` 让 autoDispose 租约释放，
/// 重新可见时先取得最新基线。lease 本身由 StudioBridge 单一入口提供。
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

/// 设置页挂载期间持有的公共 topic。
///
/// Shell 尚未租用 bundle 时，设置页自己租用配置、模型目录与恢复 topic，离开即释放。
/// 所有者仍应是启动/shell；这里只是页面生命周期内的过渡租约。
final settingsPageTopicsLeaseProvider =
    Provider.autoDispose<BridgeTopicLeaseBundle>((ref) {
      final bridge = ref.watch(studioBridgeProvider);
      final bundle = bridge.acquireTopics(const [
        SettingsConfigTopic(),
        ModelCatalogTopic(),
        RecoveryTopic(),
      ]);
      ref.onDispose(() {
        unawaited(bundle.release());
      });
      return bundle;
    }, name: 'settingsPageTopicsLeaseProvider');

/// 可见 tab 的作用域租约参数。projectId 只对 Skills 有意义。
class SettingsScopeRequest {
  const SettingsScopeRequest(this.kind, [this.projectId]);

  final BridgeSettingsScopeKind kind;
  final String? projectId;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SettingsScopeRequest &&
          kind == other.kind &&
          projectId == other.projectId;

  @override
  int get hashCode => Object.hash(kind, projectId);
}

/// 一个参数化租约入口：各 tab 只声明 kind（以及 Skills 的 projectId）。
final settingsScopeLeaseProvider = Provider.autoDispose
    .family<BridgeTopicLeaseBundle, SettingsScopeRequest>((ref, request) {
      final bridge = ref.watch(studioBridgeProvider);
      final bundle = bridge.acquireSettingsScope(
        request.kind,
        request.projectId,
      );
      ref.onDispose(() {
        unawaited(bundle.release());
      });
      return bundle;
    }, name: 'settingsScopeLeaseProvider');

/// 可见 tab 才 watch 租约；隐藏时停止 watch，autoDispose 释放。
void watchSettingsScope(
  WidgetRef ref, {
  required bool visible,
  required BridgeSettingsScopeKind kind,
  String? projectId,
}) {
  if (!visible) return;
  ref.watch(settingsScopeLeaseProvider(SettingsScopeRequest(kind, projectId)));
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
        ProviderUsageTopic() => ref.watch(
          providerUsageStoreProvider.select((state) => state.sync),
        ),
        ModelPerformanceTopic() => ref.watch(
          modelPerformanceStoreProvider.select((state) => state.sync),
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
              onPressed: () => ref.read(studioBridgeProvider).retryTopic(topic),
              icon: const Icon(Icons.refresh, size: 16),
              label: Text(context.l10n.sidebarRetry),
            ),
        ],
      ),
    );
  }
}
