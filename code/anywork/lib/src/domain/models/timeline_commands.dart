/// 主时间线的阅读意图。历史浏览固定已加载窗口，实时跟随持续接纳最新页。
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
