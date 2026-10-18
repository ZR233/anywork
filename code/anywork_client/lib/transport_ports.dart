import 'src/studio/timeline_contract.dart';

/// 聊天内容出口：打开该会话的一条有界内容连接。
///
/// 这是正文显示的必要能力，不是可选后备：生产数据源与可证明内容路径的测试替身必须实现
/// 它；缺少实现时内容同步标为失败，而不是静默当成空会话（design/26 §26.6、§26.8）。
abstract interface class TimelineTransport {
  Future<StudioTimelineConnection> openTimeline(String threadId);
}
