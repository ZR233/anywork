import 'package:flutter_test/flutter_test.dart';

import 'package:anywork/src/domain/models/studio_models.dart';

/// 行级更新范围：流式增量只应影响真正变化的条目，不能把整窗重排、重建分组或重新拼接
/// 无关正文。断言的是投影产物的**对象身份**，不是内容相等。
void main() {
  test('单条正文变化只重建该条目的行，其余行与分组身份保持不变', () {
    final projector = TimelineRowProjector();
    final before = projector.project(_window(texts: const ['一', '二', '三']));
    expect(before, hasLength(3));

    // 只有第二条条目的正文变化（窗口按稳定字段身份整体替换该条目状态）。
    final after = projector.project(_window(texts: const ['一', '二改', '三']));
    expect(after, hasLength(3));
    expect(
      identical(after[0], before[0]),
      isTrue,
      reason: '未变化的行不能重新构造',
    );
    expect(
      identical(after[2], before[2]),
      isTrue,
      reason: '未变化的行不能重新构造',
    );
    expect(
      identical(after[1], before[1]),
      isFalse,
      reason: '变化的行必须重新构造',
    );
    expect(after[1].part!.text, '二改');
    expect(
      identical(after[0].part, before[0].part),
      isTrue,
      reason: '未变化条目的投影结果必须复用',
    );
  });

  test('窗口事实完全没变时整个行列表复用', () {
    final projector = TimelineRowProjector();
    final items = _items(const ['一', '二']);
    final first = projector.project(items);
    final second = projector.project(items);
    expect(
      identical(first, second),
      isTrue,
      reason: '同一份窗口事实不应重新投影',
    );
  });

  test('结构变化（新增条目）时按身份保留未变化行的对象', () {
    final projector = TimelineRowProjector();
    final before = projector.project(_window(texts: const ['一', '二']));
    final after = projector.project(_window(texts: const ['一', '二', '三']));
    expect(after, hasLength(3));
    expect(identical(after[0], before[0]), isTrue);
    expect(identical(after[1], before[1]), isTrue);
  });

  test('推理分组仍能从分块派生摘要与展开正文', () {
    final item = _thinkingItem(
      content: const ['**判断**', '第一段推理内容', '第二段推理内容'],
    );
    final group = TimelineRowProjector().project([item]).single.reasoningGroup!;
    expect(
      group.summaries,
      isNotEmpty,
      reason: '摘要必须从分块派生：投影不再为推理预拼 text',
    );
    expect(group.summaries.first, '判断');
    expect(group.latestSummary, '判断');
    expect(group.details, contains('第一段推理内容'));
    expect(
      group.details,
      contains('判断'),
      reason: '展开正文只由分块列表派生',
    );
  });

  test('推理条目的投影不预先拼接整段正文', () {
    final item = _thinkingItem(
      content: const ['第一段推理内容', '第二段推理内容'],
    );
    final entry = TimelineRowProjector()
        .project([item])
        .single
        .reasoningGroup!
        .parts
        .single;
    expect(
      entry.text,
      isEmpty,
      reason: '推理正文按分块交付，不在投影里预拼成整段字符串',
    );
    expect(entry.reasoningContent, const ['第一段推理内容', '第二段推理内容']);
  });
}

List<ThreadItemView> _window({required List<String> texts}) {
  final now = DateTime.utc(2026, 1, 1);
  return [
    for (var index = 0; index < texts.length; index++)
      ThreadItemView(
        id: 'item-$index',
        threadId: 'thread-main',
        turnId: 'turn-1',
        ordinal: index,
        revision: 1,
        createdAt: now,
        updatedAt: now,
        state: ThreadTextItemStateView(
          channel: ThreadTextChannel.finalAnswer,
          text: texts[index],
          attachments: const [],
          lifecycle: CompletedThreadContentView(now),
        ),
      ),
  ];
}

List<ThreadItemView> _items(List<String> texts) => _window(texts: texts);

ThreadItemView _thinkingItem({required List<String> content}) {
  final now = DateTime.utc(2026, 1, 1);
  return ThreadItemView(
    id: 'thinking-1',
    threadId: 'thread-main',
    turnId: 'turn-1',
    ordinal: 0,
    revision: 1,
    createdAt: now,
    updatedAt: now,
    state: ThreadThinkingItemStateView(
      summary: const [],
      content: content,
      lifecycle: CompletedThreadContentView(now),
    ),
  );
}
