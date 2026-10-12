import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../data/stores/lsp_store.dart';
import '../../data/stores/mode_catalog_store.dart';
import '../../data/stores/selection_store.dart';
import '../../data/stores/settings_store.dart';
import '../../data/stores/thread_directory_store.dart';
import '../../data/stores/thread_session_state.dart';
import '../../data/stores/thread_session_store.dart';
import '../../data/stores/domain_sync.dart';
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
  return StudioThroughputProjection(
    threadId: session.threadId,
    completionTokens: live?.completionTokens ?? runtime.turnCompletionTokens,
    decodeMillis: live?.decodeMillis ?? runtime.turnDecodeMillis,
  );
}

@riverpod
StatusBarView? statusBarView(Ref ref) {
  final session = _selectedSession(ref);
  if (session == null) return null;
  final thread =
      session.workspace?.thread ?? _directoryThread(ref, session.threadId);
  if (thread == null) return null;
  final settings = ref.watch(settingsStoreProvider);
  final canonical = settings.canonical;
  final runtime = session.runtime ?? statusEmptyRuntime;
  return StatusBarView(
    thread: thread,
    runtime: runtime,
    permissionMode: canonical?.permissionMode ?? PermissionMode.requestApproval,
    providers: [
      for (final provider
          in canonical?.providers ?? const <ProviderSettingsView>[])
        providerWithCatalogMetadata(provider, settings.providerCatalog),
    ],
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
  for (final thread in ref.watch(threadDirectoryStoreProvider).window.threads) {
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
