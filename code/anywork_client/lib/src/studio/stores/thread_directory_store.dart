import '../../../models.dart';
import '../../../anywork_client.dart' show ReadModel;
import 'domain_sync.dart';

class ThreadDirectoryStore extends ReadModel<ThreadDirectoryStoreState> {
  ThreadDirectoryStore() : super(const ThreadDirectoryStoreState());

  bool applyBaseline(ThreadDirectoryPage page, {required int revision}) {
    final ThreadDirectoryWindow next;
    if (!state.loaded) {
      next = ThreadDirectoryWindow(
        threads: page.threads,
        nextCursor: page.nextCursor,
        hasMore: page.hasMore,
        revision: revision,
      );
    } else {
      next = state.window.applyBaselinePage(page, revision: revision);
      if (identical(next, state.window)) return false;
    }
    state = state.copyWith(
      window: next,
      loaded: true,
      sync: state.sync.connected(),
    );
    return true;
  }

  /// 产品快照里的窗口按基线页合并，避免用旧首页裁掉已触底加载的更旧页。
  bool applyWindow(ThreadDirectoryWindow incoming) {
    return applyBaseline(
      ThreadDirectoryPage(
        threads: incoming.threads,
        nextCursor: incoming.nextCursor,
        revision: incoming.revision,
      ),
      revision: incoming.revision,
    );
  }

  bool applyDelta({
    required int revision,
    required List<StudioThread> upserted,
    required List<String> removed,
  }) {
    if (!state.loaded) return false;
    final next = state.window.applyDelta(
      revision: revision,
      upserted: upserted,
      removed: removed,
    );
    var overlay = state.overlayThreads;
    if (overlay.isNotEmpty && removed.isNotEmpty) {
      final removedIds = removed.toSet();
      final pruned = overlay
          .where((thread) => !removedIds.contains(thread.id))
          .toList(growable: false);
      if (pruned.length != overlay.length) overlay = pruned;
    }
    if (identical(next, state.window) &&
        identical(overlay, state.overlayThreads)) {
      return false;
    }
    state = state.copyWith(
      window: next,
      overlayThreads: overlay,
      sync: state.sync.connected(),
    );
    return true;
  }

  /// 搜索命中且当前窗口未包含的线程并入 overlay，不推进 window revision。
  ///
  /// overlay 仅由命令响应补充、由 [applyDelta] 的 removed 清理；线程会话的
  /// 定位查找会同时检索窗口与 overlay，避免搜索命中的线程无法进入会话。
  bool mergeOverlayThreads(List<StudioThread> threads) {
    if (threads.isEmpty) return false;
    final windowIds = state.window.threads.map((t) => t.id).toSet();
    final overlayIds = state.overlayThreads.map((t) => t.id).toSet();
    final additions = threads
        .where((t) => !windowIds.contains(t.id) && !overlayIds.contains(t.id))
        .toList(growable: false);
    if (additions.isEmpty) return false;
    state = state.copyWith(
      overlayThreads: [...state.overlayThreads, ...additions],
    );
    return true;
  }

  void appendPage(ThreadDirectoryPage page) {
    final next = state.window.appendPage(page);
    if (identical(next, state.window)) return;
    state = state.copyWith(window: next, loaded: true);
  }

  void setLoading(bool isLoading) {
    if (state.window.isLoading == isLoading) return;
    state = state.copyWith(window: state.window.copyWith(isLoading: isLoading));
  }

  void applyTransport(DomainSyncStatus sync) {
    if (sync == state.sync) return;
    state = state.copyWith(sync: sync);
  }
}

class ThreadDirectoryStoreState {
  const ThreadDirectoryStoreState({
    this.window = const ThreadDirectoryWindow(),
    this.overlayThreads = const [],
    this.loaded = false,
    this.sync = const DomainSyncStatus(),
  });

  final ThreadDirectoryWindow window;
  final List<StudioThread> overlayThreads;
  final bool loaded;
  final DomainSyncStatus sync;

  int get revision => window.revision;
  String? get nextCursor => window.nextCursor;
  bool get hasMore => window.hasMore;

  ThreadDirectoryStoreState copyWith({
    ThreadDirectoryWindow? window,
    List<StudioThread>? overlayThreads,
    bool? loaded,
    DomainSyncStatus? sync,
  }) {
    return ThreadDirectoryStoreState(
      window: window ?? this.window,
      overlayThreads: overlayThreads ?? this.overlayThreads,
      loaded: loaded ?? this.loaded,
      sync: sync ?? this.sync,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ThreadDirectoryStoreState &&
          loaded == other.loaded &&
          revision == other.revision &&
          nextCursor == other.nextCursor &&
          window.hasMore == other.window.hasMore &&
          window.isLoading == other.window.isLoading &&
          sync == other.sync &&
          identical(overlayThreads, other.overlayThreads) &&
          identical(window, other.window);

  @override
  int get hashCode => Object.hash(
    loaded,
    revision,
    nextCursor,
    window.hasMore,
    window.isLoading,
    sync,
    identityHashCode(overlayThreads),
    identityHashCode(window),
  );
}
