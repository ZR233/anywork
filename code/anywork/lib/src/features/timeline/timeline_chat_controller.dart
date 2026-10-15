part of 'timeline_view.dart';

/// 一次窗口对齐的诊断快照：Driver 与门禁测试据此断言「未变化行复用同一消息实例」、
/// 「每帧只做一次线性对齐」以及「新增/淘汰只表达对应区间」。
final class TimelineChatDiff {
  const TimelineChatDiff({
    required this.inserts,
    required this.removes,
    required this.updates,
    required this.reused,
    required this.operations,
    required this.comparisons,
    required this.relocations,
  });

  static const TimelineChatDiff empty = TimelineChatDiff(
    inserts: 0,
    removes: 0,
    updates: 0,
    reused: 0,
    operations: 0,
    comparisons: 0,
    relocations: 0,
  );

  /// 本轮新增的消息数（`insertAll` 也按消息条数计）。
  final int inserts;

  /// 本轮淘汰的消息数。
  final int removes;

  /// 本轮原位更新的消息数。
  final int updates;

  /// 本轮复用同一 `Message` 实例、未发出任何操作的行数。
  final int reused;

  /// 本轮实际发出的操作条数（连续新增会合并为一次 `insertAll`）。
  final int operations;

  /// 本轮按顺序比较过的行数；线性对齐下不超过两侧行数之和。
  final int comparisons;

  /// 因顺序变化而需要「先移除再插入」的行数。稳定顺序的投影下应为 0。
  final int relocations;

  bool get isIdle =>
      inserts == 0 && removes == 0 && updates == 0 && operations == 0;
}

/// 应用侧唯一的「窗口 → 消息集合」写入者。
///
/// 一条 `TimelineRow` 对应一条自定义消息（`id = row.id`，`metadata` 持有行对象与
/// 该行的正文状态），因此列表身份始终取自行身份。每次窗口变化只做一次线性有序对齐：
/// 未变化的行复用同一个 `Message` 实例，只对实际变化的行发出 `update`，新增与淘汰只
/// 表达对应区间；不使用 `setMessages`、不整表排序、不在每帧重建整份列表。
///
/// 所有操作都显式 `animated: false`：流式正文、分页插入、窗口淘汰与正文补齐一律原位
/// 生效，不产生进出场动画。
final class TimelineChatController implements ChatController {
  TimelineChatController();

  /// 应用自有作者身份。行外壳、气泡、时间戳与头像都由应用自己的构建器渲染，
  /// `authorId` 只用于稳定身份与上游分组判定的输入，不表达业务所有权。
  static const String localAuthorId = 'anywork:local';
  static const String agentAuthorId = 'anywork:agent';

  static const String rowMetadataKey = 'anywork.timeline.row';
  static const String bodyMetadataKey = 'anywork.timeline.body';

  final StreamController<ChatOperation> _operations =
      StreamController<ChatOperation>.broadcast(sync: true);

  List<Message> _messages = const <Message>[];
  List<TimelineRow> _rows = const <TimelineRow>[];
  List<String> _stateSignatures = const <String>[];
  ThreadHistoryWindow _body = const ThreadHistoryWindow();
  TimelineChatDiff _lastDiff = TimelineChatDiff.empty;
  Object? _failure;
  bool _disposed = false;

  @override
  List<Message> get messages => _messages;

  @override
  Stream<ChatOperation> get operationsStream => _operations.stream;

  /// 当前窗口的行投影，顺序与 [messages] 一致。
  List<TimelineRow> get rows => _rows;

  /// 当前窗口的正文状态（预览/回源/错误）。行渲染据此展示回源入口。
  ThreadHistoryWindow get body => _body;

  /// 最近一次对齐的只读诊断。
  TimelineChatDiff get lastDiff => _lastDiff;

  /// 投影失败（例如行身份重复）时的最后错误：状态可诊断，不静默丢弃。
  Object? get failure => _failure;

  /// 从窗口对齐消息集合。这是应用侧唯一的写入入口。
  ///
  /// [expandedReasoningGroups] / [expandedToolGroups] 是展示层自己的展开意图，参与
  /// 「这一行是否需要原位重建」的判定，因此展开与收起只会更新对应行，不会重挂载列表。
  void applyWindow(
    List<TimelineRow> rows,
    ThreadHistoryWindow body, {
    Set<String> expandedReasoningGroups = const <String>{},
    Set<String> expandedToolGroups = const <String>{},
  }) {
    if (_disposed) return;
    final previousRows = _rows;
    final previousMessages = _messages;
    final previousSignatures = _stateSignatures;
    final previousIndexById = <String, int>{};
    for (var index = 0; index < previousMessages.length; index += 1) {
      previousIndexById[previousMessages[index].id] = index;
    }

    final nextMessages = <Message>[];
    final nextSignatures = <String>[];
    final seen = <String>{};
    Object? failure;
    var reused = 0;
    for (var index = 0; index < rows.length; index += 1) {
      final row = rows[index];
      if (!seen.add(row.id)) {
        failure ??= StateError(
          'Duplicate Timeline row identity "${row.id}" in one window',
        );
      }
      final signature = _rowStateSignature(
        row,
        body,
        expandedReasoningGroups,
        expandedToolGroups,
      );
      final previousIndex = previousIndexById[row.id];
      final reusable =
          previousIndex != null &&
          previousSignatures[previousIndex] == signature &&
          identical(previousRows[previousIndex], row);
      if (reusable) {
        reused += 1;
        nextMessages.add(previousMessages[previousIndex]);
      } else {
        nextMessages.add(_messageFor(row, body));
      }
      nextSignatures.add(signature);
    }

    final diff = _align(previousMessages, nextMessages, reused: reused);
    _rows = List<TimelineRow>.unmodifiable(rows);
    _body = body;
    _messages = List<Message>.unmodifiable(nextMessages);
    _stateSignatures = List<String>.unmodifiable(nextSignatures);
    _lastDiff = diff;
    if (failure != null) _failure = failure;
  }

  Message _messageFor(TimelineRow row, ThreadHistoryWindow body) =>
      Message.custom(
        id: row.id,
        authorId: row.isPrompt ? localAuthorId : agentAuthorId,
        createdAt: row.createdAt,
        metadata: <String, Object?>{rowMetadataKey: row, bodyMetadataKey: body},
      );

  /// 从消息取回它承载的行投影。
  static TimelineRow? rowOf(Message message) =>
      message.metadata?[rowMetadataKey] as TimelineRow?;

  /// 从消息取回它承载的正文状态。
  static ThreadHistoryWindow bodyOf(Message message) =>
      message.metadata?[bodyMetadataKey] as ThreadHistoryWindow? ??
      const ThreadHistoryWindow();

  /// 一行随时间变化的展示状态签名：正文状态与展开意图。
  ///
  /// 行内容本身的版本由行对象的 `renderVersion` 与投影对象驻留表达，因此这里只覆盖
  /// 「不改变行身份、但改变该行渲染」的展示事实。
  static String _rowStateSignature(
    TimelineRow row,
    ThreadHistoryWindow body,
    Set<String> expandedReasoningGroups,
    Set<String> expandedToolGroups,
  ) {
    final buffer = StringBuffer();
    for (final candidate in _rowBodyCandidates(row)) {
      buffer
        ..write(candidate.id)
        ..write(body.previewedItemIds.contains(candidate.id) ? 'p' : '-')
        ..write(body.loadingItemIds.contains(candidate.id) ? 'l' : '-')
        ..write(body.pendingItemBodyIds.contains(candidate.id) ? 'w' : '-')
        ..write(body.unavailableItemIds.contains(candidate.id) ? 'u' : '-')
        ..write(body.itemBodyErrors[candidate.id] ?? '')
        ..write('|');
    }
    final reasoning = row.reasoningGroup;
    if (reasoning != null) {
      buffer.write(
        expandedReasoningGroups.contains(reasoning.id) ? 'reasoning:1' : '0',
      );
    }
    final tools = row.toolGroup;
    if (tools != null) {
      buffer.write(expandedToolGroups.contains(tools.id) ? 'tools:1' : '0');
    }
    return buffer.toString();
  }

  /// 一次线性有序对齐：旧集合 → 新集合。
  ///
  /// 分三步：先淘汰新窗口不再包含的身份（按当前索引原地移除），再按新窗口顺序做一次
  /// 从左到右的比较，逐位复用同一实例、对变化行发 `update`、对缺失身份发区间插入。
  /// 只有顺序真的变化时才会走「先移除再插入」的重定位路径。
  TimelineChatDiff _align(
    List<Message> previous,
    List<Message> next, {
    required int reused,
  }) {
    final nextIds = <String>{for (final message in next) message.id};
    final work = List<Message>.of(previous);
    final operations = <ChatOperation>[];
    var removes = 0;
    var inserts = 0;
    var updates = 0;
    var comparisons = 0;
    var relocations = 0;

    for (var index = work.length - 1; index >= 0; index -= 1) {
      if (nextIds.contains(work[index].id)) continue;
      operations.add(ChatOperation.remove(work[index], index, animated: false));
      work.removeAt(index);
      removes += 1;
    }

    final pending = <Message>[];
    var pendingIndex = -1;
    void flushInserts() {
      if (pending.isEmpty) return;
      if (pending.length == 1) {
        operations.add(
          ChatOperation.insert(pending.first, pendingIndex, animated: false),
        );
      } else {
        operations.add(
          ChatOperation.insertAll(
            List<Message>.of(pending),
            pendingIndex,
            animated: false,
          ),
        );
      }
      pending.clear();
      pendingIndex = -1;
    }

    var cursor = 0;
    for (final message in next) {
      if (cursor < work.length && work[cursor].id == message.id) {
        flushInserts();
        comparisons += 1;
        if (!identical(work[cursor], message)) {
          operations.add(ChatOperation.update(work[cursor], message, cursor));
          work[cursor] = message;
          updates += 1;
        }
        cursor += 1;
        continue;
      }
      final later = _indexOfId(work, message.id, cursor);
      if (later != null) {
        flushInserts();
        relocations += 1;
        operations.add(
          ChatOperation.remove(work[later], later, animated: false),
        );
        work.removeAt(later);
        removes += 1;
      }
      if (pending.isEmpty) pendingIndex = cursor;
      pending.add(message);
      work.insert(cursor, message);
      inserts += 1;
      cursor += 1;
    }
    flushInserts();

    for (final operation in operations) {
      if (_disposed) break;
      _operations.add(operation);
    }
    return TimelineChatDiff(
      inserts: inserts,
      removes: removes,
      updates: updates,
      reused: reused,
      operations: operations.length,
      comparisons: comparisons,
      relocations: relocations,
    );
  }

  static int? _indexOfId(List<Message> work, String id, int from) {
    for (var index = from; index < work.length; index += 1) {
      if (work[index].id == id) return index;
    }
    return null;
  }

  @override
  Future<void> insertMessage(Message message, {int? index}) async {
    throw UnsupportedError('TimelineChatController 的窗口只能由 applyWindow 写入');
  }

  @override
  Future<void> insertAllMessages(List<Message> messages, {int? index}) async {
    throw UnsupportedError('TimelineChatController 的窗口只能由 applyWindow 写入');
  }

  @override
  Future<void> updateMessage(Message oldMessage, Message newMessage) async {
    throw UnsupportedError('TimelineChatController 的窗口只能由 applyWindow 写入');
  }

  @override
  Future<void> removeMessage(Message message) async {
    throw UnsupportedError('TimelineChatController 的窗口只能由 applyWindow 写入');
  }

  @override
  Future<void> setMessages(List<Message> messages) async {
    throw UnsupportedError('TimelineChatController 不整表替换：窗口增量由 applyWindow 对齐');
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _messages = const <Message>[];
    _rows = const <TimelineRow>[];
    _stateSignatures = const <String>[];
    _operations.close();
  }
}

/// 一行底层承载的条目身份：单条/raw 行是自身条目，分组行是其全部成员条目。
///
/// [isText] 标记该身份的正文由窗口按身份自动补齐：它不再需要「加载完整内容」入口。
typedef _RowBodyCandidate = ({String id, String? label, bool isText});

List<_RowBodyCandidate> _rowBodyCandidates(TimelineRow row) {
  final isTextRow = switch (row.type) {
    TimelineRowType.userMessage ||
    TimelineRowType.parentAgentMessage ||
    TimelineRowType.commentary ||
    TimelineRowType.finalAnswer => true,
    _ => false,
  };
  if (row.part case final part?) {
    return <_RowBodyCandidate>[(id: part.id, label: null, isText: isTextRow)];
  }
  if (row.toolGroup case final group?) {
    return <_RowBodyCandidate>[
      for (final item in group.items)
        (id: item.id, label: item.name, isText: false),
    ];
  }
  if (row.reasoningGroup case final group?) {
    return <_RowBodyCandidate>[
      for (final part in group.parts) (id: part.id, label: null, isText: false),
    ];
  }
  return const <_RowBodyCandidate>[];
}
