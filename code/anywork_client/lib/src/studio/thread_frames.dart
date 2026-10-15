import '../../models.dart';

sealed class ThreadStreamFrame {
  const ThreadStreamFrame();
}

final class ThreadSnapshotFrame extends ThreadStreamFrame {
  const ThreadSnapshotFrame({required this.workspace});

  /// 当前内存状态与实时事实；不携带 Timeline 条目，历史由分页 API 提供。
  final ThreadWorkspace workspace;
}

final class ThreadNotificationFrame extends ThreadStreamFrame {
  const ThreadNotificationFrame({
    required this.threadId,
    required this.revision,
    required this.update,
    this.epoch,
    this.baseRevision,
  });

  final String threadId;
  final int revision;

  /// 生产端连续广播生命周期；与当前 epoch 不一致时丢弃或重同步。
  final int? epoch;

  /// 本通知之前的状态水位；非空且与当前 revision 不一致表示缺口。
  final int? baseRevision;
  final ThreadWorkspaceUpdate update;
}

final class ThreadResyncRequiredFrame extends ThreadStreamFrame {
  const ThreadResyncRequiredFrame({
    required this.threadId,
    required this.dropped,
    this.epoch,
  });

  final String threadId;
  final int dropped;
  final int? epoch;
}

sealed class ThreadWorkspaceUpdate {
  const ThreadWorkspaceUpdate();
}

final class ThreadTurnUpdate extends ThreadWorkspaceUpdate {
  const ThreadTurnUpdate(this.turn);

  final StudioTurnView turn;
}

/// 后端 typed 当前活动变化；[activity] 为 `null` 表示当前没有活动（清除）。
///
/// 活动独立于消息窗口：它只带小型 typed 摘要与身份，正文不在状态流里。
final class ThreadActivityUpdate extends ThreadWorkspaceUpdate {
  const ThreadActivityUpdate({required this.activity});

  final ThreadActivityView? activity;
}

/// 后端 typed 存储状态变化；[storage] 为 `null` 表示当前没有可报告的存储事实（未知，
/// 不是“健康”）。界面据此显示“等待保存/明确暂停原因”，不从错误文本推断故障。
final class ThreadStorageUpdate extends ThreadWorkspaceUpdate {
  const ThreadStorageUpdate({required this.storage});

  final ThreadStorageStateView? storage;
}

final class ThreadInteractionUpdate extends ThreadWorkspaceUpdate {
  const ThreadInteractionUpdate({
    required this.interaction,
    required this.pending,
  });

  final PendingInteraction interaction;
  final bool pending;
}

final class ThreadRuntimeUpdate extends ThreadWorkspaceUpdate {
  const ThreadRuntimeUpdate({required this.runtime, required this.todo});

  final ThreadRuntimeView runtime;
  final TimelineTodoListUpdate? todo;
}
