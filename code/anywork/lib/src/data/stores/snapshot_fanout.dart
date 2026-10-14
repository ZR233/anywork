import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/models/studio_models.dart';
import 'mcp_store.dart';
import 'lsp_store.dart';
import 'mode_catalog_store.dart';
import 'model_performance_store.dart';
import 'persistence_store.dart';
import 'project_store.dart';
import 'provider_usage_store.dart';
import 'recovery_store.dart';
import 'selection_store.dart';
import 'session_costs_store.dart';
import 'settings_store.dart';
import 'skills_store.dart';
import 'thread_directory_store.dart';
import 'thread_session_store.dart';
import 'updater_store.dart';

/// 把 `readStudioState` 的聚合快照拆进各领域 merge path。
///
/// 不按到达顺序整体替换：每个 store 仍按自己的水位拒收旧事实。
void applyProductSnapshot(Ref ref, StudioState snapshot) {
  final projects = ref.read(projectStoreProvider.notifier);
  final projectApplied = projects.applyProjectDirectory(
    snapshot.projectDirectory,
  );
  projects.applyAgentDirectory(snapshot.agentDirectory);
  if (projectApplied) reconcileSelectedProject(ref);

  ref
      .read(threadDirectoryStoreProvider.notifier)
      .applyWindow(snapshot.threadDirectory);
  ref.read(settingsStoreProvider.notifier).merge(snapshot.settingsState);
  final profiles = snapshot.agentProfilesState;
  if (profiles != null) {
    ref.read(settingsStoreProvider.notifier).applyAgentProfiles(profiles);
  }
  ref.read(recoveryStoreProvider.notifier).apply(snapshot.recoveryState);
  ref.read(mcpStoreProvider.notifier).apply(snapshot.mcpState);
  ref.read(lspStoreProvider.notifier).apply(snapshot.lspState);
  ref.read(modeCatalogStoreProvider.notifier).apply(snapshot.threadModeCatalog);
  ref
      .read(providerUsageStoreProvider.notifier)
      .apply(snapshot.providerUsageState);
  ref
      .read(modelPerformanceStoreProvider.notifier)
      .apply(snapshot.modelPerformance);
  ref.read(updaterStoreProvider.notifier).apply(snapshot.updaterState);
  ref
      .read(persistenceStoreProvider.notifier)
      .applyState(snapshot.persistenceState);
  final queue = snapshot.persistenceQueueState;
  if (queue != null) {
    ref.read(persistenceStoreProvider.notifier).applyQueue(queue);
  }
  for (final entry in snapshot.skillsByProject.entries) {
    ref.read(skillsStoreProvider(entry.key).notifier).apply(entry.value);
  }
  for (final entry in snapshot.sessionCostsByRoot.entries) {
    ref.read(sessionCostsStoreProvider(entry.key).notifier).apply(entry.value);
  }
}

/// 选中项目已不在新目录中时，按稳定 id 序回退。选择本身没有 revision。
void reconcileSelectedProject(Ref ref) {
  final projects = ref.read(projectStoreProvider).projects?.values ?? const [];
  final ids = projects.map((project) => project.id).toSet();
  final sorted = [...projects]
    ..sort((left, right) => left.id.compareTo(right.id));
  ref
      .read(selectionStoreProvider.notifier)
      .retainProjects(ids, fallbackProjectId: sorted.firstOrNull?.id);
}

void reconcileRemovedThreads(Ref ref, Set<String> removed) {
  // 目录增量有意不回绑 threadSession.workspace.thread，也不清理其 workspace。
  // keepAlive 族不会因目录项消失自动释放，因此对每个 removed id 显式释放。
  for (final threadId in removed) {
    releaseThreadSession(ref, threadId);
  }
  final selected = ref.read(selectionStoreProvider).selectedThreadId;
  if (selected == null || !removed.contains(selected)) return;
  final projectId = ref.read(selectionStoreProvider).selectedProjectId;
  final threads = ref.read(threadDirectoryStoreProvider).window.threads;
  final next = threads
      .where((thread) => thread.isRoot && thread.projectId == projectId)
      .firstOrNull
      ?.id;
  ref.read(selectionStoreProvider.notifier).replaceRemovedThread(next);
}

/// 释放一个 keepAlive 会话族实例。未创建过的 provider invalidate 是 no-op。
///
/// 目录元数据只走 [ThreadDirectoryStore]；这里不读取、不回写会话 workspace。
void releaseThreadSession(Ref ref, String threadId) {
  ref.invalidate(threadSessionStoreProvider(threadId));
}
