/// 聊天窗口消费路径的逐事件记录：给「一次视觉异常」提供可定位的身份与原因。
///
/// 与 [ChatViewMetrics] 的分工：metrics 保留全局累计计数（补页、开关、resync 总数），
/// 本类保留**最近若干条**有序事件及其身份与判定依据。只有 `framesResync=20` 时无法回答
/// 「是哪个 binding、哪条校验失败、哪一行被重建」，因此失败判定与校正都必须带原因。
///
/// 记录只保存身份、枚举与几何数值，不保存正文、凭据或请求载荷；容量有界
/// （[limit]），旧事件在写入时被丢弃。生产路径只在既有分支上追加一次 O(1) 写入，
/// 不作为性能采样或日志热路径。
library;

/// 事件类别。按「哪一层做出的决定」划分，而不是按症状划分。
enum ChatViewEventKind {
  /// 内容泵采纳权威 Reset。
  frameReset,

  /// 内容泵采纳差量 Patch。
  framePatch,

  /// 帧被拒收：身份、epoch 或版本不匹配。
  frameRejected,

  /// 连续性缺口或版本倒退触发重同步。
  frameResync,

  /// 打开一个内容绑定（候选安装）。
  bindingOpening,

  /// 绑定首帧交付成功、泵已建立。
  bindingOpened,

  /// 绑定被关闭（含被换代取代）。
  bindingClosed,

  /// 控制操作在第一个 await 之前占位。
  operationBegun,

  /// 回执到达，按水位继续等待内容帧。
  operationObserved,

  /// 操作结束（已观察 / 无可变化 / 被取代 / 失败）。
  operationSettled,

  /// 采纳一次滚动几何校正。
  scrollCorrection,

  /// 行进入布局集合。
  rowsMounted,

  /// 行离开布局集合。
  rowsUnmounted,
}

/// 单条事件记录。
class ChatViewEvent {
  const ChatViewEvent({
    required this.sequence,
    required this.kind,
    required this.at,
    this.identity = const {},
    this.details = const {},
  });

  /// 单调递增序号：同一帧内的先后顺序据此判定。
  final int sequence;

  final ChatViewEventKind kind;
  final DateTime at;

  /// 事件涉及的稳定身份，例如 `threadId`、`binding`、`itemId`、`operation`。
  final Map<String, String> identity;

  /// 判定依据与几何数值，例如 `reason`、`version`、`delta`、`count`。
  final Map<String, Object?> details;

  @override
  String toString() {
    final identityText = identity.entries
        .map((entry) => '${entry.key}=${entry.value}')
        .join(' ');
    final detailText = details.entries
        .map((entry) => '${entry.key}=${entry.value}')
        .join(' ');
    return '#$sequence ${kind.name} $identityText $detailText'.trim();
  }
}

/// 有界事件环形缓冲。全部状态为静态，与 [ChatViewMetrics] 一样由测试 reset。
abstract final class ChatViewEvents {
  static const int limit = 512;

  static final List<ChatViewEvent> _events = <ChatViewEvent>[];
  static int _sequence = 0;

  /// 最近事件，按写入顺序（最早在前）。
  static List<ChatViewEvent> get events => List.unmodifiable(_events);

  static void reset() {
    _events.clear();
    _sequence = 0;
  }

  /// 记录一条事件，返回刚写入的记录。
  static ChatViewEvent record(
    ChatViewEventKind kind, {
    Map<String, String> identity = const {},
    Map<String, Object?> details = const {},
  }) {
    final event = ChatViewEvent(
      sequence: _sequence++,
      kind: kind,
      at: DateTime.now(),
      identity: Map.unmodifiable(identity),
      details: Map.unmodifiable(details),
    );
    _events.add(event);
    if (_events.length > limit) {
      _events.removeRange(0, _events.length - limit);
    }
    return event;
  }

  /// 该类别的事件，按写入顺序。
  static List<ChatViewEvent> ofKind(ChatViewEventKind kind) {
    return [
      for (final event in _events)
        if (event.kind == kind) event,
    ];
  }

  /// 指定身份（全部键值相等）的事件，按写入顺序。
  static List<ChatViewEvent> forIdentity(String key, String value) {
    return [
      for (final event in _events)
        if (event.identity[key] == value) event,
    ];
  }

  /// 便于失败信息与人工验收读取的单行摘要。
  static String dump() => _events.map((event) => event.toString()).join('\n');
}
