/// 聊天窗口消费路径的轻量计数。
///
/// 只记录次数，不记录正文、凭据或请求载荷。供 Dart 测试与人工验收对照
/// 补页循环、窗口重开和错误清理，不作为性能日志热路径。
abstract final class ChatViewMetrics {
  static int prefetchExtendLatest = 0;
  static int prefetchLoadOlder = 0;
  static int prefetchLoadNewer = 0;
  static int extendLatestCalls = 0;
  static int loadOlderCalls = 0;
  static int loadNewerCalls = 0;
  static int historyClears = 0;
  static int bindingOpens = 0;
  static int bindingCloses = 0;
  static int redundantFocusSkipped = 0;
  static int focusCalls = 0;
  static int framesApplied = 0;
  static int framesResync = 0;

  static void reset() {
    prefetchExtendLatest = 0;
    prefetchLoadOlder = 0;
    prefetchLoadNewer = 0;
    extendLatestCalls = 0;
    loadOlderCalls = 0;
    loadNewerCalls = 0;
    historyClears = 0;
    bindingOpens = 0;
    bindingCloses = 0;
    redundantFocusSkipped = 0;
    focusCalls = 0;
    framesApplied = 0;
    framesResync = 0;
  }
}
