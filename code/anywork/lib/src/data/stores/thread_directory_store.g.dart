// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'thread_directory_store.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// 会话目录分页窗口。revision 与 cursor 都参与相等。
///
/// 合并语义来自 [ThreadDirectoryWindow]：基线保留已加载更旧页，增量按身份合并，
/// 同 revision 幂等，更低 revision 拒绝。

@ProviderFor(ThreadDirectoryStore)
final threadDirectoryStoreProvider = ThreadDirectoryStoreProvider._();

/// 会话目录分页窗口。revision 与 cursor 都参与相等。
///
/// 合并语义来自 [ThreadDirectoryWindow]：基线保留已加载更旧页，增量按身份合并，
/// 同 revision 幂等，更低 revision 拒绝。
final class ThreadDirectoryStoreProvider
    extends $NotifierProvider<ThreadDirectoryStore, ThreadDirectoryStoreState> {
  /// 会话目录分页窗口。revision 与 cursor 都参与相等。
  ///
  /// 合并语义来自 [ThreadDirectoryWindow]：基线保留已加载更旧页，增量按身份合并，
  /// 同 revision 幂等，更低 revision 拒绝。
  ThreadDirectoryStoreProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'threadDirectoryStoreProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$threadDirectoryStoreHash();

  @$internal
  @override
  ThreadDirectoryStore create() => ThreadDirectoryStore();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(ThreadDirectoryStoreState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<ThreadDirectoryStoreState>(value),
    );
  }
}

String _$threadDirectoryStoreHash() =>
    r'ba0d9d12fcc1c0b9c0727476ef05a616abc15cf6';

/// 会话目录分页窗口。revision 与 cursor 都参与相等。
///
/// 合并语义来自 [ThreadDirectoryWindow]：基线保留已加载更旧页，增量按身份合并，
/// 同 revision 幂等，更低 revision 拒绝。

abstract class _$ThreadDirectoryStore
    extends $Notifier<ThreadDirectoryStoreState> {
  ThreadDirectoryStoreState build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref =
        this.ref as $Ref<ThreadDirectoryStoreState, ThreadDirectoryStoreState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<ThreadDirectoryStoreState, ThreadDirectoryStoreState>,
              ThreadDirectoryStoreState,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}
