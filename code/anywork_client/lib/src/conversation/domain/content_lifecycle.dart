/// 一次内容尝试已被新的展示代次/重连取代。
final class StaleConversationAttempt implements Exception {
  const StaleConversationAttempt();

  @override
  String toString() => 'The timeline content attempt has been retired';
}

/// 尾部连接不再发布进度；错误绝不伪装成正常结束。
final class ConversationStreamEnded implements Exception {
  const ConversationStreamEnded();

  @override
  String toString() => 'The timeline content stream ended';
}

/// 已交付版本无法用本批次连续表达：显式重同步，不在本地拼接。
final class ConversationContinuityError implements Exception {
  const ConversationContinuityError(this.reason);

  final String reason;

  @override
  String toString() => 'Timeline continuity error: $reason';
}

/// 一个展示代次持有的 scope 已退役：拒绝新工作与迟到发布。
final class StaleConversationScope implements Exception {
  const StaleConversationScope();

  @override
  String toString() => 'The timeline query scope has been retired';
}

final class RetryPolicy {
  const RetryPolicy({
    this.delays = const [
      Duration(milliseconds: 100),
      Duration(milliseconds: 400),
      Duration(seconds: 1),
    ],
  });

  final List<Duration> delays;
}

/// 页请求允许的条目范围（design/26 §26.2：默认 32，显式 1..100）。
const int conversationPageDefaultLimit = 32;
const int conversationPageMaxLimit = 100;

/// 详情块允许的字节范围：默认 64 KiB，最小 4 字节，最大 256 KiB。
const int conversationDetailMaxBytes = 256 * 1024;
const int conversationDetailMinBytes = 4;
