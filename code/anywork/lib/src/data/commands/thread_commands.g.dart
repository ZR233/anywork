// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'thread_commands.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// 会话命令 lane。
///
/// 命令在提交时**冻结资源身份**（threadId/projectId/turnId）：排队期间切换会话不会改变命令
/// 目标；执行时只重新读取该资源自身的版本与合法性（design/25 §25.7）。
///
/// route 更新与设置写入共用 settings lane，并按双 revision rebase。响应里的
/// runtime 不是第二事实源：只合并 settings，route 本身等 Thread 有序流。
/// 其他命令直通数据源；命令成功后不重读聚合状态——目录增量、Thread 快照与聊天内容由
/// 各自 owner 的流交付（design/25 §25.5）。

@ProviderFor(ThreadCommands)
final threadCommandsProvider = ThreadCommandsProvider._();

/// 会话命令 lane。
///
/// 命令在提交时**冻结资源身份**（threadId/projectId/turnId）：排队期间切换会话不会改变命令
/// 目标；执行时只重新读取该资源自身的版本与合法性（design/25 §25.7）。
///
/// route 更新与设置写入共用 settings lane，并按双 revision rebase。响应里的
/// runtime 不是第二事实源：只合并 settings，route 本身等 Thread 有序流。
/// 其他命令直通数据源；命令成功后不重读聚合状态——目录增量、Thread 快照与聊天内容由
/// 各自 owner 的流交付（design/25 §25.5）。
final class ThreadCommandsProvider
    extends $NotifierProvider<ThreadCommands, ThreadCommandBoard> {
  /// 会话命令 lane。
  ///
  /// 命令在提交时**冻结资源身份**（threadId/projectId/turnId）：排队期间切换会话不会改变命令
  /// 目标；执行时只重新读取该资源自身的版本与合法性（design/25 §25.7）。
  ///
  /// route 更新与设置写入共用 settings lane，并按双 revision rebase。响应里的
  /// runtime 不是第二事实源：只合并 settings，route 本身等 Thread 有序流。
  /// 其他命令直通数据源；命令成功后不重读聚合状态——目录增量、Thread 快照与聊天内容由
  /// 各自 owner 的流交付（design/25 §25.5）。
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

String _$threadCommandsHash() => r'd831bc8f111275b768ab2df22a8b88c7037b0573';

/// 会话命令 lane。
///
/// 命令在提交时**冻结资源身份**（threadId/projectId/turnId）：排队期间切换会话不会改变命令
/// 目标；执行时只重新读取该资源自身的版本与合法性（design/25 §25.7）。
///
/// route 更新与设置写入共用 settings lane，并按双 revision rebase。响应里的
/// runtime 不是第二事实源：只合并 settings，route 本身等 Thread 有序流。
/// 其他命令直通数据源；命令成功后不重读聚合状态——目录增量、Thread 快照与聊天内容由
/// 各自 owner 的流交付（design/25 §25.5）。

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
