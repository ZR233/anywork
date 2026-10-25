import 'package:anywork_client/conversation_ports.dart';

import 'demo_timeline_connection.dart';

/// The demo content owner: canonical in-memory items for demo runs plus the
/// bounded tail transport that projects them.
///
/// This is the demo native-port implementation of [TimelineTransport], not a
/// Studio facade and not a second business store: the canonical Repository still
/// owns every Session, projection and reducer. Demo scripts write items here,
/// and content leaves this owner only through the same typed tail/page/detail
/// contract the native bridge implements.
final class DemoTimelineContent implements TimelineTransport {
  DemoTimelineContent({this.seedDemoConversations = false});

  /// GUI demo composition seeds one small conversation per opened Thread, so a
  /// demo run has visible content without any workspace product knowledge.
  /// Fixtures keep this off and seed their own canonical items.
  final bool seedDemoConversations;

  final Map<String, _DemoContentThread> _threads = {};
  int _subscriptions = 0;

  @override
  Future<StudioTimelineConnection> openTimeline(String threadId) async =>
      DemoTimelineConnection(
        content: this,
        threadId: threadId,
        subscriptionId: 'demo-timeline-${++_subscriptions}',
      );

  /// Demo scripting/fixture seam: upsert canonical items and notify the tail.
  ///
  /// Each item is one content change (one content revision), exactly like a
  /// native `UpdateItem`/`Add` batch boundary.
  void seedItems(String threadId, Iterable<ThreadItemView> items) {
    final thread = _thread(threadId);
    for (final item in items) {
      _upsert(thread, item);
    }
  }

  /// Demo scripting/fixture seam: retract one canonical item for real.
  void retractItem(String threadId, String itemId) {
    final thread = _thread(threadId);
    final index = thread.items.indexWhere((item) => item.id == itemId);
    if (index < 0) return;
    thread.items.removeAt(index);
    thread.version += 1;
    thread.lastChange = DemoTimelineItemChange(
      version: thread.version,
      itemId: itemId,
      removed: true,
    );
    _notify(thread);
  }

  /// Canonical items of a Thread, ascending by `(ordinal, id)`.
  List<ThreadItemView> itemsOf(String threadId) =>
      List.unmodifiable(_thread(threadId).items);

  /// Current content revision of a Thread, independent of state revisions.
  int versionOf(String threadId) => _thread(threadId).version;

  DemoTimelineItemChange? lastChangeOf(String threadId) =>
      _thread(threadId).lastChange;

  void addContentListener(String threadId, void Function() listener) =>
      _thread(threadId).listeners.add(listener);

  void removeContentListener(String threadId, void Function() listener) =>
      _thread(threadId).listeners.remove(listener);

  _DemoContentThread _thread(String threadId) {
    final existing = _threads[threadId];
    if (existing != null) return existing;
    final created = _DemoContentThread(threadId);
    _threads[threadId] = created;
    if (seedDemoConversations) {
      // Initial demo content is a prepared baseline, not a burst of changes:
      // the first tail connection sees it as one consistent small page.
      created.items.addAll(demoConversation(threadId));
      created.version = 1;
    }
    return created;
  }

  void _upsert(_DemoContentThread thread, ThreadItemView item) {
    final entry = item.executionTerminal
        ? item
        : item.copyWith(executionTerminal: item.isTerminal);
    final index = thread.items.indexWhere(
      (existing) => existing.id == entry.id,
    );
    if (index < 0) {
      thread.items.add(entry);
    } else {
      thread.items[index] = entry;
    }
    thread.items.sort(_compareItems);
    thread.version += 1;
    thread.lastChange = DemoTimelineItemChange(
      version: thread.version,
      itemId: entry.id,
      item: entry,
    );
    _notify(thread);
  }

  void _notify(_DemoContentThread thread) {
    for (final listener in List<void Function()>.of(thread.listeners)) {
      listener();
    }
  }
}

/// One content change: the identity, its new canonical value or a real removal.
///
/// This is the demo producer notification; a tail connection never rebuilds a
/// whole-history version table to express one delta.
final class DemoTimelineItemChange {
  const DemoTimelineItemChange({
    required this.version,
    required this.itemId,
    this.item,
    this.removed = false,
  });

  final int version;
  final String itemId;
  final ThreadItemView? item;
  final bool removed;
}

final class _DemoContentThread {
  _DemoContentThread(this.threadId);

  final String threadId;
  final List<ThreadItemView> items = [];
  final Set<void Function()> listeners = {};
  int version = 0;
  DemoTimelineItemChange? lastChange;
}

int _compareItems(ThreadItemView left, ThreadItemView right) {
  final ordinal = left.ordinal.compareTo(right.ordinal);
  return ordinal != 0 ? ordinal : left.id.compareTo(right.id);
}

const int _demoSeedAt = 1717000000;

/// Small deterministic demo conversation for a Thread opened in demo mode.
///
/// It is demo content only: the same items still leave through the bounded tail
/// and detail reads, and nothing here replaces a Repository projection.
List<ThreadItemView> demoConversation(String threadId) => [
  ThreadItemView(
    id: 'demo-ask',
    threadId: threadId,
    turnId: 'demo-turn',
    ordinal: 0,
    revision: 1,
    createdAt: _demoSeedAt,
    updatedAt: _demoSeedAt,
    executionTerminal: true,
    state: ThreadTextItemStateView(
      channel: ThreadTextChannel.user,
      text: '演示模式：这条会话的内容来自 demo 内容源。',
      attachments: const [],
      lifecycle: const CompletedThreadContentView(_demoSeedAt),
    ),
  ),
  ThreadItemView(
    id: 'demo-reasoning',
    threadId: threadId,
    turnId: 'demo-turn',
    ordinal: 1,
    revision: 1,
    createdAt: _demoSeedAt,
    updatedAt: _demoSeedAt,
    executionTerminal: true,
    state: ThreadThinkingItemStateView(
      summary: const ['确认演示内容只经有界尾部交付'],
      content: const ['正文与工具输出仍然只按需读取完整详情。'],
      lifecycle: const CompletedThreadContentView(_demoSeedAt),
    ),
  ),
  ThreadItemView(
    id: 'demo-tool',
    threadId: threadId,
    turnId: 'demo-turn',
    ordinal: 2,
    revision: 1,
    createdAt: _demoSeedAt,
    updatedAt: _demoSeedAt,
    executionTerminal: true,
    state: ThreadToolItemStateView(
      invocation: const ThreadToolInvocationView(
        toolCallId: 'demo-call',
        name: 'read_file',
        arguments: '{"path":"README.md"}',
      ),
      lifecycle: SucceededThreadToolView(
        _demoSeedAt,
        ThreadToolOutput(
          result: '# 糊来帮',
          attachments: const [],
          outputArtifacts: const [],
        ),
      ),
    ),
  ),
  ThreadItemView(
    id: 'demo-answer',
    threadId: threadId,
    turnId: 'demo-turn',
    ordinal: 3,
    revision: 1,
    createdAt: _demoSeedAt,
    updatedAt: _demoSeedAt,
    executionTerminal: true,
    state: ThreadTextItemStateView(
      channel: ThreadTextChannel.finalAnswer,
      text: '演示内容连接遵守同一「一致小页基线 + 有界尾部」契约。',
      attachments: const [],
      lifecycle: const CompletedThreadContentView(_demoSeedAt),
    ),
  ),
];
