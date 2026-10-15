import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../presentation/providers/lsp_store.dart';
import '../../presentation/providers/mode_catalog_store.dart';
import '../../presentation/providers/selection_store.dart';
import '../../presentation/providers/settings_store.dart';
import '../../presentation/providers/thread_directory_store.dart';

import 'package:anywork_client/studio_client.dart';

import '../../presentation/providers/thread_session_store.dart';

import '../../domain/models/studio_models.dart';

part 'status_view.g.dart';

const statusEmptyRuntime = ThreadRuntimeView(
  model: '',
  contextTokens: 0,
  contextWindow: 0,
  totalTokens: 0,
  costLabel: '',
  activeSkills: [],
  activeMcpServers: [],
  activeLspServers: [],
);

/// Mode 选择器只订阅目录本身。Shell 租约由 shell 持有；这里不另开 topic。
@riverpod
List<ThreadModeDescriptorView> statusModeCatalog(Ref ref) {
  return ref.watch(modeCatalogStoreProvider).value?.modes ??
      const <ThreadModeDescriptorView>[];
}

/// LSP 活动只读 store。Shell bundle 不含 LspTopic，无人租用时列表为空。
@riverpod
List<LspServerStateView> statusLspServers(Ref ref) {
  return ref.watch(lspStoreProvider).value?.servers ?? const [];
}

@riverpod
StudioRuntimeProjection? statusRuntimeProjection(Ref ref) {
  final session = _selectedSession(ref);
  if (session == null) return null;
  final runtime = session.runtime ?? statusEmptyRuntime;
  return StudioRuntimeProjection(
    threadId: session.threadId,
    runtime: runtime,
    turn: session.activeTurn,
    isBusy: session.activeTurn?.state.isBusy ?? false,
    syncState: _syncState(session),
    loadError: session.sync.phase == DomainSyncPhase.failed
        ? session.sync.errorMessage
        : null,
  );
}

@riverpod
StudioContextProjection? statusContextProjection(Ref ref) {
  final session = _selectedSession(ref);
  if (session == null) return null;
  return StudioContextProjection.fromRuntime(
    session.threadId,
    session.runtime ?? statusEmptyRuntime,
  );
}

@riverpod
StudioThroughputProjection? statusThroughputProjection(Ref ref) {
  final session = _selectedSession(ref);
  if (session == null) return null;
  final runtime = session.runtime ?? statusEmptyRuntime;
  final live = runtime.liveUsage;
  // Live 输出与解码计数独立出现：一个 provider 可能先报其一。两者必须保持
  // 同一样本，否则新一次尝试的短解码窗口会与上一次尝试的输出总数交叉配对，
  // 显示出虚假的数千 tokens/s（design/18 §18.8.1，对齐
  // `StudioThroughputProjection.fromState` 的配对语义）。
  final liveOutputTokens = live?.completionTokens;
  final liveDecodeMillis = live?.decodeMillis;
  final hasCompleteLiveSample =
      liveOutputTokens != null &&
      liveOutputTokens > 0 &&
      liveDecodeMillis != null &&
      liveDecodeMillis > 0;
  return StudioThroughputProjection(
    threadId: session.threadId,
    completionTokens: hasCompleteLiveSample
        ? liveOutputTokens
        : live != null
        ? 0
        : runtime.turnCompletionTokens,
    decodeMillis: hasCompleteLiveSample
        ? liveDecodeMillis
        : live != null
        ? 0
        : runtime.turnDecodeMillis,
  );
}

@riverpod
StatusBarView? statusBarView(Ref ref) {
  final session = _selectedSession(ref);
  if (session == null) return null;
  final thread = _directoryThread(ref, session.threadId);
  if (thread == null) return null;
  final settings = ref.watch(settingsStoreProvider);
  final canonical = settings.canonical;
  final runtime = session.runtime ?? statusEmptyRuntime;
  return StatusBarView(
    thread: thread,
    runtime: runtime,
    providers: providersWithCatalogMetadata(
      canonical?.providers ?? const <ProviderSettingsView>[],
      settings.providerCatalog,
    ),
    roles: canonical?.roles ?? const [],
    isBusy: session.activeTurn?.state.isBusy ?? false,
  );
}

ThreadSessionState? _selectedSession(Ref ref) {
  final selection = ref.watch(selectionStoreProvider);
  final threadId = selection.selectedThreadId;
  if (threadId == null || selection.needsOpen) return null;
  return ref.watch(threadSessionStoreProvider(threadId));
}

StudioThread? _directoryThread(Ref ref, String threadId) {
  final directory = ref.watch(threadDirectoryStoreProvider);
  for (final thread in [
    ...directory.window.threads,
    ...directory.overlayThreads,
  ]) {
    if (thread.id == threadId) return thread;
  }
  return null;
}

AgentWorkspaceSyncState _syncState(ThreadSessionState session) {
  return switch (session.sync.phase) {
    DomainSyncPhase.idle =>
      session.hasSnapshot
          ? AgentWorkspaceSyncState.ready
          : AgentWorkspaceSyncState.loading,
    DomainSyncPhase.connecting => AgentWorkspaceSyncState.loading,
    DomainSyncPhase.ready => AgentWorkspaceSyncState.ready,
    DomainSyncPhase.reconnecting =>
      session.hasSnapshot
          ? AgentWorkspaceSyncState.reconnecting
          : AgentWorkspaceSyncState.loading,
    DomainSyncPhase.failed =>
      session.hasSnapshot
          ? AgentWorkspaceSyncState.stale
          : AgentWorkspaceSyncState.failed,
  };
}
