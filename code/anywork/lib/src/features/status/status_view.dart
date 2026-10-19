import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../presentation/providers/client_provider.dart';
import '../../presentation/providers/lsp_store.dart';
import '../../presentation/providers/mode_catalog_store.dart';
import '../../presentation/providers/observe_client.dart';
import '../../presentation/providers/thread_directory_store.dart';
import '../settings/settings_views.dart';

import 'package:anywork_client/studio_client.dart';

import '../../domain/models/studio_models.dart';

part 'status_view.g.dart';

const statusEmptyRuntime = ThreadRuntimeView(
  modelId: '',
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

/// Stable status-bar fields for one Thread. Throughput and context are not
/// part of this value, so decode updates cannot rebuild the chrome.
@riverpod
StatusBarView? statusBarView(Ref ref, String threadId) {
  final thread = _directoryThread(ref, threadId);
  if (thread == null) return null;
  final catalog = ref.watch(settingsAccountsViewProvider);
  final chrome =
      _observeSession(
        ref,
        threadId,
        _chromeFromSession,
        equals: _chromeEquals,
      ) ??
      (
        isBusy: false,
        modelRoute: null,
        workflowRun: null,
        activeSkills: const <String>[],
        activeMcpServers: const <String>[],
        activeLspServers: const <String>[],
      );
  return StatusBarView(
    thread: thread,
    accounts: catalog.accounts,
    roles: catalog.canonical?.roles ?? const [],
    isBusy: chrome.isBusy,
    modelRoute: chrome.modelRoute,
    workflowRun: chrome.workflowRun,
    activeSkills: chrome.activeSkills,
    activeMcpServers: chrome.activeMcpServers,
    activeLspServers: chrome.activeLspServers,
  );
}

@riverpod
StudioContextProjection? statusContextProjection(Ref ref, String threadId) {
  return _observeSession(
    ref,
    threadId,
    (session) => StudioContextProjection.fromRuntime(
      threadId,
      session.runtime ?? statusEmptyRuntime,
    ),
  );
}

@riverpod
StudioThroughputProjection? statusThroughputProjection(
  Ref ref,
  String threadId,
) {
  return _observeSession(ref, threadId, (session) {
    final runtime = session.runtime ?? statusEmptyRuntime;
    final source = ModelRouteQueries.throughputSource(runtime);
    return StudioThroughputProjection(
      threadId: threadId,
      completionTokens: source?.outputTokens ?? 0,
      decodeMillis: source?.decodeMillis ?? 0,
    );
  });
}

typedef _StatusChrome = ({
  bool isBusy,
  ThreadModelRouteView? modelRoute,
  WorkflowRunView? workflowRun,
  List<String> activeSkills,
  List<String> activeMcpServers,
  List<String> activeLspServers,
});

_StatusChrome _chromeFromSession(ThreadSessionState session) {
  final runtime = session.runtime ?? statusEmptyRuntime;
  return (
    isBusy: session.activeTurn?.state.isBusy ?? false,
    modelRoute: runtime.modelRoute,
    workflowRun: runtime.workflow?.currentRun,
    activeSkills: runtime.activeSkills,
    activeMcpServers: runtime.activeMcpServers,
    activeLspServers: runtime.activeLspServers,
  );
}

bool _chromeEquals(_StatusChrome left, _StatusChrome right) {
  return left.isBusy == right.isBusy &&
      left.modelRoute == right.modelRoute &&
      left.workflowRun == right.workflowRun &&
      _sameStrings(left.activeSkills, right.activeSkills) &&
      _sameStrings(left.activeMcpServers, right.activeMcpServers) &&
      _sameStrings(left.activeLspServers, right.activeLspServers);
}

bool _sameStrings(List<String> left, List<String> right) {
  if (identical(left, right)) return true;
  if (left.length != right.length) return false;
  for (var index = 0; index < left.length; index++) {
    if (left[index] != right[index]) return false;
  }
  return true;
}

T? _observeSession<T>(
  Ref ref,
  String threadId,
  T Function(ThreadSessionState session) project, {
  bool Function(T left, T right)? equals,
}) {
  final owner = ref.read(anyworkClientProvider).existingSession(threadId);
  if (owner == null) {
    observeClientDemand(
      ref,
      ownsFailure: (owner) => owner == 'session:$threadId',
    );
    return null;
  }
  late final T current;
  current = project(
    observeClient(ref, owner.source, (next) {
      final projected = project(next);
      final unchanged = equals == null
          ? projected == current
          : equals(projected, current);
      if (!unchanged) ref.invalidateSelf();
    }),
  );
  return current;
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
