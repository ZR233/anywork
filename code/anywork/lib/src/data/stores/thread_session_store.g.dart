// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'thread_session_store.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// 会话状态族。首个观察者经 Bridge 建流，最后一个观察者释放订阅。
///
/// keepAlive 保留 last-known canonical runtime 状态；订阅寿命用 onCancel/onResume/onDispose。
/// 聊天正文按显示需求消费（design/25 §25.4）：无观察者时关闭权威 ChatView 并清正文镜像，
/// 恢复观察后重开窗口、重获最新有界 Reset——Rust 执行、可靠事实保存不依赖 Dart 是否观察。

@ProviderFor(ThreadSessionStore)
final threadSessionStoreProvider = ThreadSessionStoreFamily._();

/// 会话状态族。首个观察者经 Bridge 建流，最后一个观察者释放订阅。
///
/// keepAlive 保留 last-known canonical runtime 状态；订阅寿命用 onCancel/onResume/onDispose。
/// 聊天正文按显示需求消费（design/25 §25.4）：无观察者时关闭权威 ChatView 并清正文镜像，
/// 恢复观察后重开窗口、重获最新有界 Reset——Rust 执行、可靠事实保存不依赖 Dart 是否观察。
final class ThreadSessionStoreProvider
    extends $NotifierProvider<ThreadSessionStore, ThreadSessionState> {
  /// 会话状态族。首个观察者经 Bridge 建流，最后一个观察者释放订阅。
  ///
  /// keepAlive 保留 last-known canonical runtime 状态；订阅寿命用 onCancel/onResume/onDispose。
  /// 聊天正文按显示需求消费（design/25 §25.4）：无观察者时关闭权威 ChatView 并清正文镜像，
  /// 恢复观察后重开窗口、重获最新有界 Reset——Rust 执行、可靠事实保存不依赖 Dart 是否观察。
  ThreadSessionStoreProvider._({
    required ThreadSessionStoreFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'threadSessionStoreProvider',
         isAutoDispose: false,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$threadSessionStoreHash();

  @override
  String toString() {
    return r'threadSessionStoreProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  ThreadSessionStore create() => ThreadSessionStore();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(ThreadSessionState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<ThreadSessionState>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is ThreadSessionStoreProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$threadSessionStoreHash() =>
    r'0558a4752480857197bee1620ae8436a93c4e419';

/// 会话状态族。首个观察者经 Bridge 建流，最后一个观察者释放订阅。
///
/// keepAlive 保留 last-known canonical runtime 状态；订阅寿命用 onCancel/onResume/onDispose。
/// 聊天正文按显示需求消费（design/25 §25.4）：无观察者时关闭权威 ChatView 并清正文镜像，
/// 恢复观察后重开窗口、重获最新有界 Reset——Rust 执行、可靠事实保存不依赖 Dart 是否观察。

final class ThreadSessionStoreFamily extends $Family
    with
        $ClassFamilyOverride<
          ThreadSessionStore,
          ThreadSessionState,
          ThreadSessionState,
          ThreadSessionState,
          String
        > {
  ThreadSessionStoreFamily._()
    : super(
        retry: null,
        name: r'threadSessionStoreProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: false,
      );

  /// 会话状态族。首个观察者经 Bridge 建流，最后一个观察者释放订阅。
  ///
  /// keepAlive 保留 last-known canonical runtime 状态；订阅寿命用 onCancel/onResume/onDispose。
  /// 聊天正文按显示需求消费（design/25 §25.4）：无观察者时关闭权威 ChatView 并清正文镜像，
  /// 恢复观察后重开窗口、重获最新有界 Reset——Rust 执行、可靠事实保存不依赖 Dart 是否观察。

  ThreadSessionStoreProvider call(String threadId) =>
      ThreadSessionStoreProvider._(argument: threadId, from: this);

  @override
  String toString() => r'threadSessionStoreProvider';
}

/// 会话状态族。首个观察者经 Bridge 建流，最后一个观察者释放订阅。
///
/// keepAlive 保留 last-known canonical runtime 状态；订阅寿命用 onCancel/onResume/onDispose。
/// 聊天正文按显示需求消费（design/25 §25.4）：无观察者时关闭权威 ChatView 并清正文镜像，
/// 恢复观察后重开窗口、重获最新有界 Reset——Rust 执行、可靠事实保存不依赖 Dart 是否观察。

abstract class _$ThreadSessionStore extends $Notifier<ThreadSessionState> {
  late final _$args = ref.$arg as String;
  String get threadId => _$args;

  ThreadSessionState build(String threadId);
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<ThreadSessionState, ThreadSessionState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<ThreadSessionState, ThreadSessionState>,
              ThreadSessionState,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, () => build(_$args));
  }
}
