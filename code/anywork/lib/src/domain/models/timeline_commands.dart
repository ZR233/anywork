// Timeline 的呈现模式与应用侧命令词表。
//
// 这里没有像素锚点、窗口焦点、双向翻页或几何回执：Live/History 是**内容发布策略**，
// 不是滚动 owner；进入 History 只由真实用户滚动触发（design/26 §26.3、§26.4）。

/// 展示模式。Live 跟随最新端；History 冻结已展示内容，只允许向前插更早消息。
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

/// 真实用户滚动离开底端：冻结当前已展示内容与结构。
final class TimelineEnterHistory extends TimelineCommand {
  const TimelineEnterHistory();
}

/// 显式回到实时（或发送前准备）：建立新订阅基线与新展示代次。
final class TimelineReturnLive extends TimelineCommand {
  const TimelineReturnLive();
}
