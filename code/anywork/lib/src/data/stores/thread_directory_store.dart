import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../domain/models/studio_models.dart';
import 'domain_sync.dart';

part 'thread_directory_store.g.dart';

/// 会话目录分页窗口。revision 与 cursor 都参与相等。
///
/// 合并语义来自 [ThreadDirectoryWindow]：基线保留已加载更旧页，增量按身份合并，
/// 同 revision 幂等，更低 revision 拒绝。
@Riverpod(keepAlive: true)
class ThreadDirectoryStore extends _$ThreadDirectoryStore {
  @override
  ThreadDirectoryStoreState build() => const ThreadDirectoryStoreState();

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
    if (identical(next, state.window)) return false;
    state = state.copyWith(window: next, sync: state.sync.connected());
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
    this.loaded = false,
    this.sync = const DomainSyncStatus(),
  });

  final ThreadDirectoryWindow window;
  final bool loaded;
  final DomainSyncStatus sync;

  int get revision => window.revision;
  String? get nextCursor => window.nextCursor;
  bool get hasMore => window.hasMore;

  ThreadDirectoryStoreState copyWith({
    ThreadDirectoryWindow? window,
    bool? loaded,
    DomainSyncStatus? sync,
  }) {
    return ThreadDirectoryStoreState(
      window: window ?? this.window,
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
          identical(window, other.window);

  @override
  int get hashCode => Object.hash(
    loaded,
    revision,
    nextCursor,
    window.hasMore,
    window.isLoading,
    sync,
    identityHashCode(window),
  );
}
