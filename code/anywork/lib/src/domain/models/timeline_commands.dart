// Timeline 的命令/事件门面归应用侧所有：它只是「界面 → Client threadCommands」
// 的类型化词汇表，不是第二份内容事实源。
//
// 混合归属说明：命令/事件类由应用侧自持，但其中**阅读锚点契约**直接复用 Client 类型——
// `TimelineAnchor` / `TimelineDirection` 是窗口/锚点契约的一部分，`TimelineViewAction`
// 更是 Client thread 命令 API（`updateTimelineAnchor(..., {viewAction})`）直接接收的参数
// 类型。若在应用侧另建同名副本，就会形成两份完全同值的枚举，并在每个消费点被迫做一次
// 恒等映射；因此这里只 `show` Client 的这三个符号，不再自建副本。
import 'package:anywork_client/models.dart'
    show TimelineAnchor, TimelineDirection, TimelineViewAction;

/// Timeline 的唯一 UI 命令入口。
///
/// 滚动、分页、正文补齐和阅读锚点都以同一组 typed 命令进入 data 层，避免
/// Widget 同时持有多个相互独立的业务回调。
sealed class TimelineCommand {
  const TimelineCommand();
}

/// 会话窗口向界面交付的事件。事件只属于当前打开的会话，界面不轮询数据源。
sealed class TimelineEvent {
  const TimelineEvent(this.threadId);
  final String threadId;
}

final class TimelineWindowReset extends TimelineEvent {
  const TimelineWindowReset(super.threadId, this.version);
  final int version;
}

final class TimelineWindowPatch extends TimelineEvent {
  const TimelineWindowPatch(super.threadId, this.fromVersion, this.version);
  final int fromVersion;
  final int version;
}

final class TimelinePagingStarted extends TimelineEvent {
  const TimelinePagingStarted(super.threadId, this.direction);
  final TimelineDirection direction;
}

final class TimelinePagingCompleted extends TimelineEvent {
  const TimelinePagingCompleted(super.threadId, this.direction, this.version);
  final TimelineDirection direction;
  final int version;
}

final class TimelinePagingFailed extends TimelineEvent {
  const TimelinePagingFailed(super.threadId, this.direction, this.error);
  final TimelineDirection direction;
  final Object error;
}

final class TimelineBodyLoadCompleted extends TimelineEvent {
  const TimelineBodyLoadCompleted(super.threadId, this.itemId, this.version);
  final String itemId;
  final int version;
}

final class TimelineRuntimeChanged extends TimelineEvent {
  const TimelineRuntimeChanged(super.threadId);
}

final class TimelineStreamLagged extends TimelineEvent {
  const TimelineStreamLagged(super.threadId, this.version);
  final int version;
}

final class TimelineSessionClosed extends TimelineEvent {
  const TimelineSessionClosed(super.threadId);
}

/// 当前打开会话的唯一命令/事件边界。具体状态由宿主 reducer 投影。
abstract interface class TimelineSession {
  Stream<TimelineEvent> get events;
  Future<void> dispatch(TimelineCommand command);
  Future<void> close();
}

final class TimelineLoadOlder extends TimelineCommand {
  const TimelineLoadOlder();
}

final class TimelineLoadNewer extends TimelineCommand {
  const TimelineLoadNewer();
}

final class TimelineJumpToLatest extends TimelineCommand {
  const TimelineJumpToLatest();
}

final class TimelineExpandBody extends TimelineCommand {
  const TimelineExpandBody(this.itemId);
  final String itemId;
}

final class TimelineVisibleBodies extends TimelineCommand {
  const TimelineVisibleBodies(this.itemIds);
  final List<String> itemIds;
}

final class TimelineAnchorChanged extends TimelineCommand {
  const TimelineAnchorChanged(this.anchor, {this.viewAction});
  final TimelineAnchor anchor;

  /// 本次锚点变化是否同时表达了「改后端焦点」的意图；null 表示只更新阅读位置。
  final TimelineViewAction? viewAction;
}
