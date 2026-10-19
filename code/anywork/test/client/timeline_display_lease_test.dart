import 'package:anywork/src/domain/models/timeline_presentation.dart';
import 'package:anywork/src/presentation/view_models/timeline_session_owner.dart';
import 'package:anywork_client/studio_client.dart';
import 'package:flutter_chat_core/flutter_chat_core.dart';
import 'package:flutter_test/flutter_test.dart';

/// 展示 lease 的缺陷敏感度：唯一 loadedMessage 集合、身份稳定、真实删除、重叠页去重、
/// History 冻结与真实卸载释放（design/26 §26.3、§26.8）。
void main() {
  StudioTimelineItem item(
    String id,
    int revision, {
    String body = 'body',
    bool saved = false,
    StudioTimelineLifecycle lifecycle = StudioTimelineLifecycle.streaming,
  }) => StudioTimelineItem(
    item: ThreadItemView(
      id: id,
      threadId: 'thread',
      turnId: 'turn',
      ordinal: revision,
      revision: revision,
      createdAt: DateTime.utc(2026),
      updatedAt: DateTime.utc(2026),
      state: ThreadTextItemStateView(
        channel: ThreadTextChannel.finalAnswer,
        text: body,
        attachments: const [],
        lifecycle: lifecycle == StudioTimelineLifecycle.terminal
            ? CompletedThreadContentView(DateTime.utc(2026))
            : const StreamingThreadContentView(),
      ),
      saved: saved,
    ),
    saved: saved,
    lifecycle: lifecycle,
    omittedBytes: 0,
    details: const [],
  );

  TimelineDisplayLease lease() => TimelineDisplayLease(
    threadId: 'thread',
    generation: 1,
    openQueries: (_) => null,
  );

  List<String> messageIds(TimelineDisplayLease value) => [
    for (final message in value.controller.messages) message.id,
  ];

  test('baseline becomes the唯一 loaded message collection', () {
    final display = lease();
    display.adoptBaseline(
      StudioTimelineBaseline(
        subscriptionId: 'sub',
        version: 4,
        items: [item('a', 1), item('b', 2)],
        before: 'tlp1.before',
        hasOlder: true,
      ),
    );
    expect(messageIds(display), ['a', 'b']);
    expect(display.appliedVersion, 4);
    expect(display.olderCursor, 'tlp1.before');
    expect(display.hasOlder, isTrue);
    expect(display.loadedCount, 2);
  });

  test('add/update/remove keep canonical identity and never re-create it', () {
    final display = lease();
    display.adoptBaseline(
      StudioTimelineBaseline(
        subscriptionId: 'sub',
        version: 1,
        items: [item('a', 1)],
        before: null,
        hasOlder: false,
      ),
    );
    final before = display.controller.messages.single;

    // 重复交付已加载身份：不 remove/reinsert、不改 ID；稳定身份不要求同一 Dart 实例。
    expect(
      display.applyPatch(
        StudioTimelinePatch(
          subscriptionId: 'sub',
          from: 1,
          to: 2,
          changes: [StudioTimelineAdd(item('a', 1))],
          priority: StudioTimelinePriority.immediate,
        ),
      ),
      isTrue,
    );
    expect(display.controller.messages.single.id, before.id);
    expect(
      timelinePayloadOf(display.controller.messages.single)!.revision,
      timelinePayloadOf(before)!.revision,
    );

    // 原位更新：同一身份、新正文。
    expect(
      display.applyPatch(
        StudioTimelinePatch(
          subscriptionId: 'sub',
          from: 2,
          to: 3,
          changes: [
            StudioTimelineUpdateItem(
              itemId: 'a',
              expectedRevision: 1,
              revision: 2,
              omittedBytes: 0,
              saved: true,
              lifecycle: StudioTimelineLifecycle.terminal,
              fields: const [
                StudioFieldUpdateView(
                  field: ThreadTextFieldView(),
                  change: AppendThreadFieldChangeView(' more'),
                  totalBytes: 9,
                  previewBytes: 9,
                ),
              ],
            ),
          ],
          priority: StudioTimelinePriority.coalesced,
        ),
      ),
      isTrue,
    );
    final updated = display.controller.messages.single;
    final payload = timelinePayloadOf(updated)!;
    expect(payload.id, 'a');
    expect(payload.saved, isTrue, reason: '保存水位独立于执行终态');
    expect(payload.terminal, isTrue);
    final text = payload.item.state as ThreadTextItemStateView;
    expect(text.text, 'body more');

    // 真实删除：即使该身份不在 SDK 有界尾部里也必须交付给展示。
    expect(
      display.applyPatch(
        StudioTimelinePatch(
          subscriptionId: 'sub',
          from: 3,
          to: 4,
          changes: const [StudioTimelineRemove('a')],
          priority: StudioTimelinePriority.immediate,
        ),
      ),
      isTrue,
    );
    expect(display.controller.messages, isEmpty);
    expect(display.loadedCount, 0);
  });

  test('a revision the display cannot continue asks for a new baseline', () {
    final display = lease();
    display.adoptBaseline(
      StudioTimelineBaseline(
        subscriptionId: 'sub',
        version: 1,
        items: [item('a', 1)],
        before: null,
        hasOlder: false,
      ),
    );
    expect(
      display.applyPatch(
        StudioTimelinePatch(
          subscriptionId: 'sub',
          from: 7,
          to: 8,
          changes: const [],
          priority: StudioTimelinePriority.coalesced,
        ),
      ),
      isFalse,
      reason: 'a gap must be explicit, never patched locally',
    );
  });

  test('older pages prepend without duplicating loaded identities', () {
    final display = lease();
    display.adoptBaseline(
      StudioTimelineBaseline(
        subscriptionId: 'sub',
        version: 9,
        items: [item('c', 3)],
        before: 'tlp1.c',
        hasOlder: true,
      ),
    );
    final inserted = display.prependOlder(
      StudioTimelinePage(
        items: [item('a', 1), item('b', 2), item('c', 3)],
        before: 'tlp1.a',
        hasOlder: true,
      ),
    );
    expect(inserted, 2, reason: 'overlapping identity is not inserted twice');
    expect(messageIds(display), ['a', 'b', 'c']);
    expect(display.olderCursor, 'tlp1.a');
    // 分页不抬高冻结展示的内容水位。
    expect(display.appliedVersion, 9);
  });

  test('History freezes content, structure and saved facts', () {
    final display = lease();
    display.adoptBaseline(
      StudioTimelineBaseline(
        subscriptionId: 'sub',
        version: 1,
        items: [item('a', 1)],
        before: null,
        hasOlder: false,
      ),
    );
    final frozen = display.controller.messages.single;
    display.enterHistory();
    expect(
      display.applyPatch(
        StudioTimelinePatch(
          subscriptionId: 'sub',
          from: 1,
          to: 2,
          changes: [
            StudioTimelineAdd(item('new', 1)),
            StudioTimelineUpdateItem(
              itemId: 'a',
              expectedRevision: 1,
              revision: 2,
              omittedBytes: 0,
              saved: true,
              lifecycle: StudioTimelineLifecycle.terminal,
              fields: const [],
            ),
          ],
          priority: StudioTimelinePriority.immediate,
        ),
      ),
      isTrue,
    );
    expect(display.controller.messages.single, same(frozen));
    expect(display.appliedVersion, 1, reason: 'frozen display watermark stays');
    expect(
      timelinePayloadOf(frozen)!.saved,
      isFalse,
      reason: 'saved confirmations are frozen too',
    );
  });

  test(
    'an unmounted lease releases directly; a mounted one waits for unmount',
    () async {
      final idle = lease();
      await idle.retire();
      expect(idle.isReleased, isTrue);

      final mounted = lease();
      mounted.bind();
      final retiring = mounted.retire();
      expect(
        mounted.isReleased,
        isFalse,
        reason: 'the real subtree still borrows the controller',
      );
      await mounted.unbind();
      await retiring;
      expect(mounted.isReleased, isTrue);
    },
  );

  test('chat key changes with the generation and scroll keeps no offset', () {
    final first = TimelineDisplayLease(
      threadId: 'thread',
      generation: 1,
      openQueries: (_) => null,
    );
    final second = TimelineDisplayLease(
      threadId: 'thread',
      generation: 2,
      openQueries: (_) => null,
    );
    expect(first.chatKey, isNot(second.chatKey));
    expect(first.scrollController.keepScrollOffset, isFalse);
    expect(first.controller, isA<InMemoryChatController>());
  });

  StudioTimelineItem activity(
    String id,
    int order, {
    String? toolName,
    int revision = 1,
  }) => StudioTimelineItem(
    item: ThreadItemView(
      id: id,
      threadId: 'thread',
      turnId: 'turn',
      ordinal: order,
      revision: revision,
      createdAt: DateTime.utc(2026),
      updatedAt: DateTime.utc(2026),
      state: toolName == null
          ? const ThreadThinkingItemStateView(
              summary: ['Investigating'],
              content: [],
              lifecycle: StreamingThreadContentView(),
            )
          : ThreadToolItemStateView(
              invocation: ThreadToolInvocationView(
                toolCallId: id,
                name: toolName,
                arguments: '{}',
              ),
              lifecycle: const RunningThreadToolView(''),
            ),
    ),
    saved: false,
    lifecycle: StudioTimelineLifecycle.streaming,
    omittedBytes: 0,
    details: const [],
  );

  test(
    'consecutive thoughts/tools and image reads become separate custom items',
    () {
      final display = lease();
      display.adoptBaseline(
        StudioTimelineBaseline(
          subscriptionId: 'sub',
          version: 1,
          before: null,
          hasOlder: false,
          items: [
            activity('thinking', 1),
            activity('command', 2, toolName: 'run_command'),
            activity('image-a', 3, toolName: 'view_image'),
            activity('image-b', 4, toolName: 'view_image'),
            item('answer', 5),
          ],
        ),
      );
      expect(
        display.loadedCount,
        5,
        reason: 'original calls remain individually addressable',
      );
      expect(
        display.controller.messages.length,
        3,
        reason: 'two consecutive activities, two image calls and one answer are three presentation items',
      );
    },
  );

  test('retry and result records of one attempt share one GUI item', () {
    StudioTimelineItem recovery(
      String id,
      int order,
      StudioTimelineRecoveryNotice notice,
    ) => StudioTimelineItem(
      item: item(id, order).item,
      source: StudioTimelineRecoverySource(
        attemptId: 'attempt',
        notice: notice,
      ),
      saved: true,
      lifecycle: StudioTimelineLifecycle.terminal,
      omittedBytes: 0,
      details: const [],
    );
    final display = lease();
    display.adoptBaseline(
      StudioTimelineBaseline(
        subscriptionId: 'sub',
        version: 1,
        before: null,
        hasOlder: false,
        items: [
          recovery('retry-1', 1, StudioTimelineRecoveryNotice.retry),
          recovery('retry-2', 2, StudioTimelineRecoveryNotice.retry),
          recovery('result', 3, StudioTimelineRecoveryNotice.result),
        ],
      ),
    );
    expect(display.loadedCount, 3);
    expect(
      display.controller.messages.length,
      1,
      reason: 'GUI grouping never deletes recovery facts',
    );
  });

  test(
    'paging preserves group identity; late body splits and removal rejoins it',
    () {
      final display = lease();
      addTearDown(display.retire);
      display.adoptBaseline(
        StudioTimelineBaseline(
          subscriptionId: 'sub',
          version: 1,
          items: [activity('c', 30), activity('d', 40)],
          before: 'older',
          hasOlder: true,
        ),
      );
      final original = timelinePresentationOf(
        display.controller.messages.single,
      )!;
      original.setExpanded(true);
      expect(
        display.prependOlder(
          StudioTimelinePage(
            items: [activity('a', 10), activity('b', 20)],
            before: null,
            hasOlder: false,
          ),
        ),
        2,
      );
      expect(display.controller.messages.single.id, original.id);
      expect(original.memberIds, ['a', 'b', 'c', 'd']);
      expect(original.expanded, isTrue);
      expect(
        display.applyPatch(
          StudioTimelinePatch(
            priority: StudioTimelinePriority.immediate,
            subscriptionId: 'sub',
            from: 1,
            to: 2,
            changes: [StudioTimelineAdd(item('divider', 25))],
          ),
        ),
        isTrue,
      );
      expect(display.controller.messages.length, 3);
      expect(
        timelinePresentationOf(display.controller.messages.last),
        same(original),
      );
      expect(original.memberIds, ['c', 'd']);
      final prefix = timelinePresentationOf(display.controller.messages.first)!;
      expect(prefix.memberIds, ['a', 'b']);
      expect(prefix.expanded, isTrue);
      expect(
        display.applyPatch(
          StudioTimelinePatch(
            priority: StudioTimelinePriority.immediate,
            subscriptionId: 'sub',
            from: 2,
            to: 3,
            changes: [const StudioTimelineRemove('divider')],
          ),
        ),
        isTrue,
      );
      expect(display.controller.messages.single.id, original.id);
      expect(original.memberIds, ['a', 'b', 'c', 'd']);
      expect(display.payloads.map((p) => p.id), ['a', 'b', 'c', 'd']);
    },
  );

  test('streaming updates only its member and summary; History freezes the whole group', () {
    final display = lease();
    addTearDown(display.retire);
    display.adoptBaseline(
      StudioTimelineBaseline(
        subscriptionId: 'sub',
        version: 1,
        items: [activity('a', 1), activity('b', 2)],
        before: null,
        hasOlder: false,
      ),
    );
    final group = timelinePresentationOf(display.controller.messages.single)!;
    var changed = 0;
    var unaffected = 0;
    var structural = 0;
    group.member('a').addListener(() => changed++);
    group.member('b').addListener(() => unaffected++);
    group.structure.addListener(() => structural++);
    expect(
      display.applyPatch(
        StudioTimelinePatch(
          priority: StudioTimelinePriority.immediate,
          subscriptionId: 'sub',
          from: 1,
          to: 2,
          changes: [StudioTimelineAdd(activity('a', 1, revision: 2))],
        ),
      ),
      isTrue,
    );
    expect(group.member('a').value.revision, 2);
    expect(changed, 1);
    expect(unaffected, 0);
    expect(structural, 0);
    expect(display.controller.messages.single.id, group.id);
    display.enterHistory();
    expect(
      display.applyPatch(
        StudioTimelinePatch(
          priority: StudioTimelinePriority.immediate,
          subscriptionId: 'sub',
          from: 2,
          to: 3,
          changes: [
            StudioTimelineAdd(activity('a', 1, revision: 3)),
            const StudioTimelineRemove('b'),
          ],
        ),
      ),
      isTrue,
    );
    expect(group.memberIds, ['a', 'b']);
    expect(group.member('a').value.revision, 2);
    expect(changed, 1);
  });

  test('structural listeners observe committed member ownership', () {
    final display = lease();
    addTearDown(display.retire);
    display.adoptBaseline(
      StudioTimelineBaseline(
        subscriptionId: 'sub',
        version: 1,
        items: [activity('a', 10)],
        before: null,
        hasOlder: false,
      ),
    );
    final group = display.presentationFor('a')!;
    group.structure.addListener(() {
      for (final id in group.memberIds) {
        expect(display.presentationFor(id), same(group));
        expect(display.payloadOf(id), same(group.member(id).value));
      }
    });
    display.applyPatch(
      StudioTimelinePatch(
        subscriptionId: 'sub',
        from: 1,
        to: 2,
        priority: StudioTimelinePriority.immediate,
        changes: [StudioTimelineAdd(activity('b', 20))],
      ),
    );
    final member = group.member('a');
    member.addListener(() {
      expect(display.payloadOf('a'), same(member.value));
      expect(display.presentationFor('a')!.member('a'), same(member));
    });
    display.applyPatch(
      StudioTimelinePatch(
        subscriptionId: 'sub',
        from: 2,
        to: 3,
        priority: StudioTimelinePriority.immediate,
        changes: [
          StudioTimelineAdd(
            StudioTimelineItem(
              item: item('a', 2).item.copyWith(ordinal: 10),
              saved: false,
              lifecycle: StudioTimelineLifecycle.streaming,
              omittedBytes: 0,
              details: const [],
            ),
          ),
        ],
      ),
    );
    expect(display.presentationFor('a')!.id, group.id);
  });

  test(
    'deleting an anchor keeps its display ID and correct later insertion order',
    () {
      final display = lease();
      addTearDown(display.retire);
      display.adoptBaseline(
        StudioTimelineBaseline(
          subscriptionId: 'sub',
          version: 1,
          items: [activity('a', 10), activity('b', 20)],
          before: null,
          hasOlder: false,
        ),
      );
      final group = display.presentationFor('a')!..setExpanded(true);
      display.applyPatch(
        StudioTimelinePatch(
          subscriptionId: 'sub',
          from: 1,
          to: 2,
          priority: StudioTimelinePriority.immediate,
          changes: [
            const StudioTimelineRemove('a'),
            StudioTimelineAdd(item('divider', 15)),
          ],
        ),
      );
      expect(display.presentationFor('b'), same(group));
      expect(group.expanded, isTrue);
      expect(
        display.controller.messages.map(
          (m) => timelinePresentationOf(m)!.memberIds,
        ),
        [
          ['divider'],
          ['b'],
        ],
      );
    },
  );

  test(
    'another visible activity ends an image run and different turns never join',
    () {
      final display = lease();
      addTearDown(display.retire);
      display.adoptBaseline(
        StudioTimelineBaseline(
          subscriptionId: 'sub',
          version: 1,
          items: [
            activity('image-a', 1, toolName: 'view_image'),
            activity('image-b', 2, toolName: 'view_image'),
            activity('thinking', 3),
            activity('image-c', 4, toolName: 'view_image'),
          ],
          before: null,
          hasOlder: false,
        ),
      );
      final groups = display.controller.messages
          .map(timelinePresentationOf)
          .toList();
      expect(groups.map((g) => g!.kind), [
        TimelinePresentationKind.images,
        TimelinePresentationKind.activity,
        TimelinePresentationKind.images,
      ]);
      expect(groups.first!.memberIds, ['image-a', 'image-b']);
      expect(groups.last!.memberIds, ['image-c']);
    },
  );
}
