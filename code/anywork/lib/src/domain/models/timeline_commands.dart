// Timeline 的呈现模式与应用侧命令词表。
//
// 这里没有像素锚点、窗口焦点、双向翻页或几何回执：Live/History 仅表达阅读意图，
// 不改变完成发布、消费者、查询 scope 或业务订阅（design/26 §26.8）。

/// 阅读意图。两种意图均持续接纳完成项，滚动由原生组件负责。
enum TimelineDisplayMode { live, history }

/// 内容连接对外的 typed 阶段（与 Thread 状态同步完全独立）。
enum TimelineConnectionPhase {
  idle,
  opening,
  ready,
  reconnecting,
  failed,
  closed,
}

/// 界面可发出的唯一 Timeline 意图词汇。
///
/// 查询本身（older 页、详情块）有返回值和在途身份，因此它们是展示 lease 上的方法调用，
/// 不压进这些无返回值意图里。
sealed class TimelineCommand {
  const TimelineCommand();
}

/// 真实用户滚动离开底端。
final class TimelineEnterHistory extends TimelineCommand {
  const TimelineEnterHistory();
}

/// 显式回到最新：保留现有业务订阅与已加载窗口。
final class TimelineReturnLive extends TimelineCommand {
  const TimelineReturnLive();
}
