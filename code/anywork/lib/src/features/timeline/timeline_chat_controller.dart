part of 'timeline_view.dart';

const String _timelineUserAuthorId = 'user';
const String _timelineParentAgentAuthorId = 'parent-agent';
const String _timelineAssistantAuthorId = 'assistant';

/// 将 `TimelineRow` 窗口投影桥接到 `flutter_chat_core` 的 [ChatController] 操作流。
///
/// - 既有行内容/状态变化（流式增量、工具进度、`saved` 落盘确认、正文回源状态）只发出
///   [ChatOperation.update]，由对应行的 `ChatMessageInternal` 局部重建，不触发整表重建或退场动画；
/// - 尾部追加、顶部历史补页、滑窗淘汰分别映射为 [ChatOperation.insert] /
///   [ChatOperation.insertAll] / [ChatOperation.remove] / [ChatOperation.set]。
final class TimelineChatController
    with UploadProgressMixin, ScrollToMessageMixin
    implements ChatController {
  TimelineChatController({
    required List<TimelineRow> rows,
    required ThreadHistoryWindow body,
  }) : _messages = _buildChatMessages(rows, body);

  List<Message> _messages;
  final StreamController<ChatOperation> _operationsController =
      StreamController<ChatOperation>.broadcast(sync: true);

  @override
  List<Message> get messages => _messages;

  @override
  Stream<ChatOperation> get operationsStream => _operationsController.stream;

  void syncWindow(List<TimelineRow> rows, ThreadHistoryWindow body) {
    final nextMessages = _buildChatMessages(rows, body);
    final nextById = <String, Message>{
      for (final message in nextMessages) message.id: message,
    };

    // 1. 先对仍然留在窗口内的行做原地 update，使 ChatMessageInternal 局部刷新，
    //    同时避免后续结构 diff 把内容更新当成 remove + insert。
    for (var i = 0; i < _messages.length; i += 1) {
      final current = _messages[i];
      final updated = nextById[current.id];
      if (updated != null && current != updated) {
        _messages[i] = updated;
        _operationsController.add(ChatOperation.update(current, updated, i));
      }
    }

    // 2. 若行身份序列未变，原地 update 已完成全部同步。
    if (_sameMessageIds(_messages, nextMessages)) {
      return;
    }

    // 3. 纯尾部追加：直接发出 insert / insertAll。
    if (nextMessages.length > _messages.length &&
        _isPrefixIds(_messages, nextMessages)) {
      final appended = nextMessages.sublist(_messages.length);
      if (appended.length == 1) {
        unawaited(insertMessage(appended.single, animated: false));
      } else {
        unawaited(insertAllMessages(appended, animated: false));
      }
      return;
    }

    // 4. 纯顶部前置（向上懒加载未触发尾部淘汰）：直接发出 index=0 的 insertAll。
    if (nextMessages.length > _messages.length &&
        _isSuffixIds(_messages, nextMessages)) {
      final prependedCount = nextMessages.length - _messages.length;
      final prepended = nextMessages.sublist(0, prependedCount);
      unawaited(insertAllMessages(prepended, index: 0, animated: false));
      return;
    }

    // 5. 滑窗淘汰、分组归并或整窗替换：交由 setMessages 做最小结构 diff。
    unawaited(setMessages(nextMessages, animated: false));
  }

  @override
  Future<void> insertMessage(
    Message message, {
    int? index,
    bool animated = true,
  }) async {
    if (_messages.any((m) => m.id == message.id)) return;
    if (index == null) {
      _messages.add(message);
      _operationsController.add(
        ChatOperation.insert(message, _messages.length - 1, animated: animated),
      );
    } else {
      _messages.insert(index, message);
      _operationsController.add(
        ChatOperation.insert(message, index, animated: animated),
      );
    }
  }

  @override
  Future<void> insertAllMessages(
    List<Message> messages, {
    int? index,
    bool animated = true,
  }) async {
    if (messages.isEmpty) return;
    if (index == null) {
      final originalLength = _messages.length;
      _messages.addAll(messages);
      _operationsController.add(
        ChatOperation.insertAll(messages, originalLength, animated: animated),
      );
    } else {
      _messages.insertAll(index, messages);
      _operationsController.add(
        ChatOperation.insertAll(messages, index, animated: animated),
      );
    }
  }

  @override
  Future<void> removeMessage(Message message, {bool animated = true}) async {
    final index = _messages.indexWhere((m) => m.id == message.id);
    if (index != -1) {
      final removed = _messages.removeAt(index);
      _operationsController.add(
        ChatOperation.remove(removed, index, animated: animated),
      );
    }
  }

  @override
  Future<void> updateMessage(Message oldMessage, Message newMessage) async {
    final index = _messages.indexWhere((m) => m.id == oldMessage.id);
    if (index != -1) {
      final actualOld = _messages[index];
      if (actualOld == newMessage) return;
      _messages[index] = newMessage;
      _operationsController.add(
        ChatOperation.update(actualOld, newMessage, index),
      );
    }
  }

  @override
  Future<void> setMessages(
    List<Message> messages, {
    bool animated = true,
  }) async {
    _messages = List.from(messages);
    _operationsController.add(
      ChatOperation.set(
        _messages,
        animated: _messages.isEmpty ? false : animated,
      ),
    );
  }

  @override
  void dispose() {
    _operationsController.close();
    disposeUploadProgress();
    disposeScrollMethods();
  }
}

List<Message> _buildChatMessages(
  List<TimelineRow> rows,
  ThreadHistoryWindow body,
) {
  return <Message>[for (final row in rows) _rowToChatMessage(row, body)];
}

Message _rowToChatMessage(TimelineRow row, ThreadHistoryWindow body) {
  final authorId = switch (row.type) {
    TimelineRowType.userMessage => _timelineUserAuthorId,
    TimelineRowType.parentAgentMessage => _timelineParentAgentAuthorId,
    _ => _timelineAssistantAuthorId,
  };
  final metadata = <String, dynamic>{
    'row': row,
    'renderVersion': row.renderVersion,
    'bodySignature': _rowBodySignature(row, body),
  };
  if (row is TimelineTextRow) {
    final part = row.part;
    if (!row.isPrompt && part.status == 'streaming') {
      return Message.textStream(
        id: row.id,
        authorId: authorId,
        streamId: row.id,
        createdAt: row.createdAt,
        updatedAt: part.updatedAt,
        metadata: metadata,
      );
    }
    return Message.text(
      id: row.id,
      authorId: authorId,
      text: part.text,
      createdAt: row.createdAt,
      updatedAt: part.updatedAt,
      metadata: metadata,
    );
  }
  return Message.custom(
    id: row.id,
    authorId: authorId,
    createdAt: row.createdAt,
    metadata: metadata,
  );
}

int _rowBodySignature(TimelineRow row, ThreadHistoryWindow body) {
  return Object.hashAll([
    for (final part in row.entries) ...[
      part.id,
      body.previewedItemIds.contains(part.id),
      body.loadingItemIds.contains(part.id),
      body.pendingItemBodyIds.contains(part.id),
      body.unavailableItemIds.contains(part.id),
      body.itemBodyErrors[part.id],
    ],
  ]);
}

bool _sameMessageIds(List<Message> left, List<Message> right) {
  if (left.length != right.length) return false;
  for (var i = 0; i < left.length; i += 1) {
    if (left[i].id != right[i].id) return false;
  }
  return true;
}

bool _isPrefixIds(List<Message> prefix, List<Message> full) {
  if (prefix.length > full.length) return false;
  for (var i = 0; i < prefix.length; i += 1) {
    if (prefix[i].id != full[i].id) return false;
  }
  return true;
}

bool _isSuffixIds(List<Message> suffix, List<Message> full) {
  if (suffix.length > full.length) return false;
  final offset = full.length - suffix.length;
  for (var i = 0; i < suffix.length; i += 1) {
    if (suffix[i].id != full[offset + i].id) return false;
  }
  return true;
}
