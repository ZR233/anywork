/// 一条内容连接的观察面：只表达连接阶段与最近交付的一份内容。
///
/// `S` 是唯一内容泵交付的帧类型；这里不携带窗口、行集合或几何事实。连接阶段与内容帧
/// 都属于同一条连接的事实，Thread 状态同步另有自己的观察通道，两者互不推导。
sealed class ChatUiState<S> {
  const ChatUiState(this.threadId);
  final String threadId;

  /// 最近一次已交付的内容（`Open`/`Reconnecting`/`Failed` 时保留最后有效帧）。
  S? get snapshot;
}

final class ChatIdle<S> extends ChatUiState<S> {
  const ChatIdle(super.threadId);
  @override
  S? get snapshot => null;
}

final class ChatOpening<S> extends ChatUiState<S> {
  const ChatOpening(super.threadId, {this.lastGood});
  final S? lastGood;
  @override
  S? get snapshot => lastGood;
}

final class ChatReady<S> extends ChatUiState<S> {
  const ChatReady(super.threadId, this.snapshot);
  @override
  final S snapshot;
}

final class ChatReconnecting<S> extends ChatUiState<S> {
  const ChatReconnecting(super.threadId, {this.lastGood, required this.error});
  final S? lastGood;
  final Object error;
  @override
  S? get snapshot => lastGood;
}

final class ChatFailed<S> extends ChatUiState<S> {
  const ChatFailed(super.threadId, {this.lastGood, required this.error});
  final S? lastGood;
  final Object error;
  @override
  S? get snapshot => lastGood;
}

final class ChatClosed<S> extends ChatUiState<S> {
  const ChatClosed(super.threadId);
  @override
  S? get snapshot => null;
}

/// transport 中立的内容协议违规（本地判定，不是后端错误分类）。
final class ChatProtocolError implements Exception {
  const ChatProtocolError(this.message);
  final String message;

  @override
  String toString() => 'Chat protocol error: $message';
}
