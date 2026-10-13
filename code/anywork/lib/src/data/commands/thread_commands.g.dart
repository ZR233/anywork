// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'thread_commands.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// 会话命令 lane。
///
/// route 更新与设置写入共用 settings lane，并按双 revision rebase。响应里的
/// runtime 不是第二事实源：只合并 settings，route 本身等 Thread 有序流。
/// 其他命令直通数据源；无目录 revision 的结果不拼进目录。

@ProviderFor(ThreadCommands)
final threadCommandsProvider = ThreadCommandsProvider._();

/// 会话命令 lane。
///
/// route 更新与设置写入共用 settings lane，并按双 revision rebase。响应里的
/// runtime 不是第二事实源：只合并 settings，route 本身等 Thread 有序流。
/// 其他命令直通数据源；无目录 revision 的结果不拼进目录。
final class ThreadCommandsProvider
    extends $NotifierProvider<ThreadCommands, ThreadCommandBoard> {
  /// 会话命令 lane。
  ///
  /// route 更新与设置写入共用 settings lane，并按双 revision rebase。响应里的
  /// runtime 不是第二事实源：只合并 settings，route 本身等 Thread 有序流。
  /// 其他命令直通数据源；无目录 revision 的结果不拼进目录。
  ThreadCommandsProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'threadCommandsProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$threadCommandsHash();

  @$internal
  @override
  ThreadCommands create() => ThreadCommands();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(ThreadCommandBoard value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<ThreadCommandBoard>(value),
    );
  }
}

String _$threadCommandsHash() => r'7dae0e408d89eb3eb703b4aaf3b5a9adee6f852a';

/// 会话命令 lane。
///
/// route 更新与设置写入共用 settings lane，并按双 revision rebase。响应里的
/// runtime 不是第二事实源：只合并 settings，route 本身等 Thread 有序流。
/// 其他命令直通数据源；无目录 revision 的结果不拼进目录。

abstract class _$ThreadCommands extends $Notifier<ThreadCommandBoard> {
  ThreadCommandBoard build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<ThreadCommandBoard, ThreadCommandBoard>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<ThreadCommandBoard, ThreadCommandBoard>,
              ThreadCommandBoard,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}
