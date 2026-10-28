import 'support/conversation_fixtures.dart';

import 'package:anywork/src/features/conversation/timeline/state/timeline_entry.dart';
import 'package:anywork/src/presentation/view_models/timeline_session_owner.dart';
import 'package:anywork_client/studio_client.dart';
import 'package:flutter_chat_core/flutter_chat_core.dart';
import 'package:flutter_test/flutter_test.dart';

/// 展示 lease 的缺陷敏感度：唯一 loadedMessage 集合、身份稳定、真实删除、重叠页去重、
/// History 冻结与真实卸载释放（design/26 §26.3、§26.8）。
void main() {
  ConversationItem item(
    String id,
    int revision, {
    String body = 'body',
    bool saved = false,
    ConversationLifecycle lifecycle = ConversationLifecycle.streaming,
    String turnId = 'turn',
  }) => conversationFixture(
    id: id,
    threadId: 'thread',
    turnId: turnId,
    ordinal: revision,
    revision: revision,
    createdAt: DateTime.utc(2026),
    updatedAt: DateTime.utc(2026),
    saved: saved,
    lifecycle: lifecycle,
    descriptor: ConversationTextDescriptor(
      channel: ThreadTextChannel.finalAnswer,
      attachments: const [],
      lifecycle: lifecycle == ConversationLifecycle.terminal
          ? CompletedThreadContentView(DateTime.utc(2026))
          : const StreamingThreadContentView(),
    ),
    fields: {const ThreadTextFieldView(): body},
  );

  TimelineDisplayLease lease() => TimelineDisplayLease(
    threadId: 'thread',
    generation: 1,
    content: conversationContentFixture(threadId: 'thread'),
  );

  List<String> messageIds(TimelineDisplayLease value) => [
    for (final message in value.controller.messages) message.id,
  ];

  test('baseline becomes the唯一 loaded message collection', () {
    final display = lease();
    display.adoptBaseline(
      ConversationBaseline(
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
      ConversationBaseline(
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
        ConversationPatch(
          subscriptionId: 'sub',
          from: 1,
          to: 2,
          changes: [ConversationAdd(item('a', 1))],
          priority: ConversationPriority.immediate,
        ),
      ),
      isTrue,
    );
    expect(display.controller.messages.single.id, before.id);
    expect(
      timelineEntryOf(display.controller.messages.single)!.first.revision,
      timelineEntryOf(before)!.first.revision,
    );

    // 原位更新：同一身份、新正文。
    expect(
      display.applyPatch(
        ConversationPatch(
          subscriptionId: 'sub',
          from: 2,
          to: 3,
          changes: [
            ConversationUpdateItem(
              itemId: 'a',
              expectedRevision: 1,
              revision: 2,

              saved: true,
              lifecycle: ConversationLifecycle.terminal,
              fields: const [
                ConversationFieldUpdate(
                  field: ThreadTextFieldView(),
                  change: AppendThreadFieldChangeView(' more'),
                  totalBytes: 9,
                  previewBytes: 9,
                ),
              ],
            ),
          ],
          priority: ConversationPriority.coalesced,
        ),
      ),
      isTrue,
    );
    final updated = display.controller.messages.single;
    final payload = timelineEntryOf(updated)!.first;
    expect(payload.id, 'a');
    expect(payload.saved, isTrue, reason: '保存水位独立于执行终态');
    expect(payload.terminal, isTrue);
    final text = timelineText(payload);
    expect(text, 'body more');

    // 真实删除：即使该身份不在 SDK 有界尾部里也必须交付给展示。
    expect(
      display.applyPatch(
        ConversationPatch(
          subscriptionId: 'sub',
          from: 3,
          to: 4,
          changes: const [ConversationRemove('a')],
          priority: ConversationPriority.immediate,
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
      ConversationBaseline(
        subscriptionId: 'sub',
        version: 1,
        items: [item('a', 1)],
        before: null,
        hasOlder: false,
      ),
    );
    expect(
      display.applyPatch(
        ConversationPatch(
          subscriptionId: 'sub',
          from: 7,
          to: 8,
          changes: const [],
          priority: ConversationPriority.coalesced,
        ),
      ),
      isFalse,
      reason: 'a gap must be explicit, never patched locally',
    );
  });

  test('older pages prepend without duplicating loaded identities', () {
    final display = lease();
    display.adoptBaseline(
      ConversationBaseline(
        subscriptionId: 'sub',
        version: 9,
        items: [item('c', 3)],
        before: 'tlp1.c',
        hasOlder: true,
      ),
    );
    final inserted = display.prependOlder(
      ConversationPage(
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
      ConversationBaseline(
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
        ConversationPatch(
          subscriptionId: 'sub',
          from: 1,
          to: 2,
          changes: [
            ConversationAdd(item('new', 1)),
            ConversationUpdateItem(
              itemId: 'a',
              expectedRevision: 1,
              revision: 2,

              saved: true,
              lifecycle: ConversationLifecycle.terminal,
              fields: const [],
            ),
          ],
          priority: ConversationPriority.immediate,
        ),
      ),
      isTrue,
    );
    expect(display.controller.messages.single, same(frozen));
    expect(display.appliedVersion, 1, reason: 'frozen display watermark stays');
    expect(
      timelineEntryOf(frozen)!.first.saved,
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
      content: conversationContentFixture(threadId: 'thread'),
    );
    final second = TimelineDisplayLease(
      threadId: 'thread',
      generation: 2,
      content: conversationContentFixture(threadId: 'thread'),
    );
    expect(first.chatKey, isNot(second.chatKey));
    expect(first.scrollController.keepScrollOffset, isFalse);
    expect(first.controller, isA<InMemoryChatController>());
  });

  ConversationItem waitCall(
    String id,
    int order, {
    String turnId = 'turn',
    ThreadWaitStateView state = ThreadWaitStateView.waiting,
    ConversationToolState? lifecycle,
    int revision = 1,
    String result = '',
    ConversationLifecycle itemLifecycle = ConversationLifecycle.streaming,
  }) => conversationFixture(
    id: id,
    threadId: 'thread',
    turnId: turnId,
    ordinal: order,
    revision: revision,
    createdAt: DateTime.utc(2026),
    updatedAt: DateTime.utc(2026),
    saved: false,
    lifecycle: itemLifecycle,
    descriptor: ConversationToolDescriptor(
      invocation: ConversationToolInvocation(toolCallId: id, name: 'wait'),
      wait: ThreadWaitPresentationView(
        intent: ThreadWaitEventsIntentView(
          targets: [
            ThreadWaitTargetView(
              taskId: 'task:exec-1',
              toolName: 'exec',
              summary: 'cargo test',
              status: ThreadWaitTargetStatusView.running,
            ),
          ],
          timeoutMs: 60000,
        ),
        state: state,
      ),
      state: lifecycle ?? ConversationToolRunning(),
    ),
    fields: {
      const ThreadToolArgumentsFieldView():
          '{"taskIds":["task:exec-1"],"timeoutMs":60000}',
      const ThreadToolResultFieldView(): result,
    },
  );

  ConversationItem sleepCall(String id, int order, {String turnId = 'turn'}) =>
      conversationFixture(
        id: id,
        threadId: 'thread',
        turnId: turnId,
        ordinal: order,
        revision: 1,
        createdAt: DateTime.utc(2026),
        updatedAt: DateTime.utc(2026),
        saved: false,
        lifecycle: ConversationLifecycle.streaming,
        descriptor: ConversationToolDescriptor(
          invocation: ConversationToolInvocation(toolCallId: id, name: 'sleep'),
          wait: const ThreadWaitPresentationView(
            intent: ThreadWaitTimerIntentView(durationMs: 3000),
            state: ThreadWaitStateView.waiting,
          ),
          state: ConversationToolRunning(),
        ),
        fields: {const ThreadToolArgumentsFieldView(): '{"durationMs":3000}'},
      );

  ConversationItem activity(
    String id,
    int order, {
    String? toolName,
    int revision = 1,
    String turnId = 'turn',
    ThreadContentLifecycleView? contentLifecycle,
    ConversationLifecycle itemLifecycle = ConversationLifecycle.streaming,
  }) => conversationFixture(
    id: id,
    threadId: 'thread',
    turnId: turnId,
    ordinal: order,
    revision: revision,
    createdAt: DateTime.utc(2026),
    updatedAt: DateTime.utc(2026),
    saved: false,
    lifecycle: itemLifecycle,
    descriptor: toolName == null
        ? ConversationThinkingDescriptor(
            lifecycle: contentLifecycle ?? const StreamingThreadContentView(),
          )
        : ConversationToolDescriptor(
            invocation: ConversationToolInvocation(
              toolCallId: id,
              name: toolName,
            ),
            state: ConversationToolRunning(),
          ),
    fields: toolName == null
        ? {ThreadThinkingSummaryFieldView(0): 'Investigating'}
        : {const ThreadToolArgumentsFieldView(): '{}'},
  );

  ConversationItem userInputCall(String id, int order) => conversationFixture(
    id: id,
    threadId: 'thread',
    turnId: 'turn',
    ordinal: order,
    revision: 1,
    createdAt: DateTime.utc(2026),
    updatedAt: DateTime.utc(2026),
    saved: false,
    lifecycle: ConversationLifecycle.streaming,
    descriptor: ConversationToolDescriptor(
      invocation: ConversationToolInvocation(toolCallId: id, name: 'ask_user'),
      userInput: (conversationInputFixture(
        interactionId: 'ask-$id',
        questions: const [
          UserQuestionView(
            id: 'q1',
            header: 'Pick one',
            question: 'Which option should the agent use?',
            isOther: false,
            isSecret: false,
            options: [
              UserQuestionOptionView(label: 'A', description: 'first option'),
            ],
          ),
        ],
        state: const ConversationUserInputPending(),
        answers: const <String, List<String>>{},
      )).descriptor,
      state: ConversationToolRunning(),
    ),
    fields: {
      const ThreadToolArgumentsFieldView(): '{}',
      ...(conversationInputFixture(
        interactionId: 'ask-$id',
        questions: const [
          UserQuestionView(
            id: 'q1',
            header: 'Pick one',
            question: 'Which option should the agent use?',
            isOther: false,
            isSecret: false,
            options: [
              UserQuestionOptionView(label: 'A', description: 'first option'),
            ],
          ),
        ],
        state: const ConversationUserInputPending(),
        answers: const <String, List<String>>{},
      )).fields,
    },
  );

  ConversationItem planReceiptCall(String id, int order) => conversationFixture(
    id: id,
    threadId: 'thread',
    turnId: 'turn',
    ordinal: order,
    revision: 1,
    createdAt: DateTime.utc(2026),
    updatedAt: DateTime.utc(2026),
    saved: false,
    lifecycle: ConversationLifecycle.streaming,
    descriptor: ConversationToolDescriptor(
      invocation: ConversationToolInvocation(
        toolCallId: id,
        name: 'confirm_plan',
      ),
      userInput: (conversationInputFixture(
        interactionId: 'plan-$id',
        questions: const [
          UserQuestionView(
            id: agentSessionPlanConfirmationQuestionId,
            header: 'Plan',
            question: '# Plan title\n\n- step one',
            isOther: false,
            isSecret: false,
            options: [],
          ),
        ],
        state: const ConversationUserInputPending(),
        answers: const <String, List<String>>{},
      )).descriptor,
      state: ConversationToolRunning(),
    ),
    fields: {
      const ThreadToolArgumentsFieldView(): '{}',
      ...(conversationInputFixture(
        interactionId: 'plan-$id',
        questions: const [
          UserQuestionView(
            id: agentSessionPlanConfirmationQuestionId,
            header: 'Plan',
            question: '# Plan title\n\n- step one',
            isOther: false,
            isSecret: false,
            options: [],
          ),
        ],
        state: const ConversationUserInputPending(),
        answers: const <String, List<String>>{},
      )).fields,
    },
  );

  /// 一次 `skill_view` 调用：它的 tool call 身份是技能激活的 typed 来源。
  ConversationItem skillCall(
    String id,
    int order, {
    String name = 'skill_view',
    String arguments = '{"name":"pdf"}',
    String result = '{"name":"pdf","instructions":"..."}',
    bool succeeded = true,
    ConversationToolState? lifecycle,
    String turnId = 'turn',
    int revision = 1,
  }) => conversationFixture(
    id: id,
    threadId: 'thread',
    turnId: turnId,
    ordinal: order,
    revision: revision,
    createdAt: DateTime.utc(2026),
    updatedAt: DateTime.utc(2026),
    saved: false,
    lifecycle: lifecycle != null || succeeded
        ? ConversationLifecycle.terminal
        : ConversationLifecycle.streaming,
    descriptor: ConversationToolDescriptor(
      invocation: ConversationToolInvocation(toolCallId: id, name: name),
      state:
          lifecycle ??
          (succeeded
              ? ConversationToolSucceeded(
                  completedAt: DateTime.utc(2026),
                  output: ConversationToolOutputDescriptor(
                    attachments: const [],
                  ),
                )
              : ConversationToolRunning()),
    ),
    fields: {
      const ThreadToolArgumentsFieldView(): arguments,
      const ThreadToolResultFieldView(): lifecycle == null && succeeded
          ? result
          : '',
    },
  );

  /// 一条终态技能激活：来源是同 Turn 的 tool call 或用户手势。
  ConversationItem skillActivation(
    String id,
    int order, {
    String name = 'pdf',
    String? toolCallId,
    String gestureId = 'gesture-1',
    String turnId = 'turn',
    String source = 'project',
    int revision = 1,
    SkillResourceBaseView resourceBase = const SkillResourceBaseView(
      SkillResourceBaseKind.directory,
      '.agents/skills/pdf',
    ),
  }) => conversationFixture(
    id: id,
    threadId: 'thread',
    turnId: turnId,
    ordinal: order,
    revision: revision,
    createdAt: DateTime.utc(2026),
    updatedAt: DateTime.utc(2026),
    saved: true,
    lifecycle: ConversationLifecycle.terminal,
    descriptor: ConversationSkillDescriptor(
      ThreadSkillItemStateView(
        name: name,
        source: source,
        providerId: 'project',
        resourceBase: resourceBase,
        cause: toolCallId == null
            ? SkillActivationCauseView(
                SkillActivationCauseKind.userGesture,
                gestureId,
              )
            : SkillActivationCauseView(
                SkillActivationCauseKind.tool,
                toolCallId,
              ),
        activatedAt: DateTime.utc(2026),
      ),
    ),
    fields: {},
  );

  test(
    'consecutive thoughts/tools and image reads become separate custom items',
    () {
      final display = lease();
      display.adoptBaseline(
        ConversationBaseline(
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

  test('typed wait/sleep join the adjacent thought/tool activity group', () {
    final display = lease();
    addTearDown(display.retire);
    display.adoptBaseline(
      ConversationBaseline(
        subscriptionId: 'sub',
        version: 1,
        before: null,
        hasOlder: false,
        items: [
          activity('thinking', 1),
          activity('command', 2, toolName: 'run_command'),
          waitCall('wait-1', 3),
          activity('later', 4, toolName: 'run_command'),
          sleepCall('sleep-1', 5),
          activity('after-sleep', 6),
        ],
      ),
    );
    final groups = display.controller.messages.map(timelineEntryOf).toList();
    expect(groups, hasLength(1));
    final group = groups.single!;
    expect(group.kind, TimelineEntryKind.activity);
    expect(group.memberIds, [
      'thinking',
      'command',
      'wait-1',
      'later',
      'sleep-1',
      'after-sleep',
    ]);
    expect(group.id, isNot('wait-1'));
    expect(group.id, isNot('sleep-1'));
    expect(group.id, startsWith('timeline-group:'));
    final wait =
        (group.members.firstWhere((item) => item.id == 'wait-1').descriptor
                as ConversationToolDescriptor)
            .wait!;
    expect(wait.state, ThreadWaitStateView.waiting);
    expect(wait.intent, isA<ThreadWaitEventsIntentView>());
    final waitIntent = wait.intent as ThreadWaitEventsIntentView;
    expect(waitIntent.targets.single.taskId, 'task:exec-1');
    expect(waitIntent.targets.single.toolName, 'exec');
    expect(waitIntent.timeoutMs, 60000);
    final sleep =
        (group.members.firstWhere((item) => item.id == 'sleep-1').descriptor
                as ConversationToolDescriptor)
            .wait!;
    expect(sleep.state, ThreadWaitStateView.waiting);
    expect(sleep.intent, isA<ThreadWaitTimerIntentView>());
    expect((sleep.intent as ThreadWaitTimerIntentView).durationMs, 3000);
  });

  test(
    'a successful skill read joins the same-turn thought/tool activity group',
    () {
      final display = lease();
      addTearDown(display.retire);
      display.adoptBaseline(
        ConversationBaseline(
          subscriptionId: 'sub',
          version: 1,
          before: null,
          hasOlder: false,
          items: [
            activity('thinking', 1),
            skillCall('skill-view-1', 2),
            skillActivation('skill-1', 3, toolCallId: 'skill-view-1'),
            activity('command', 4, toolName: 'run_command'),
          ],
        ),
      );
      final groups = display.controller.messages.map(timelineEntryOf).toList();
      expect(groups, hasLength(1), reason: '技能不单独划分活动组边界');
      final group = groups.single!;
      expect(group.kind, TimelineEntryKind.activity);
      expect(group.memberIds, [
        'thinking',
        'skill-view-1',
        'skill-1',
        'command',
      ]);
      expect(display.loadedCount, 4, reason: '配对只是一条可见行，两份 canonical 成员都仍可寻址');
      expect(display.presentationFor('skill-1'), same(group));
      expect(display.presentationFor('skill-view-1'), same(group));
      expect(group.memberIds, [
        'thinking',
        'skill-view-1',
        'skill-1',
        'command',
      ], reason: 'canonical 成员、顺序与身份不因视觉去重被删改');
      expect(group.visibleMemberIds, ['thinking', 'skill-1', 'command']);
      expect(group.pairedToolId('skill-1'), 'skill-view-1');
      expect(group.visibleMemberIds.contains('skill-view-1'), isFalse);
      expect(group.skillCount, 1);
      expect(group.toolCount, 1, reason: '同一次加载不重复计成工具与技能两种活动');
      expect(
        group.members.where(
          (item) =>
              item.descriptor is ConversationToolDescriptor &&
              (item.descriptor as ConversationToolDescriptor).state
                  is ConversationToolRunning,
        ),
        hasLength(1),
      );
    },
  );

  test('a later page converges the skill row with its own original call', () {
    final display = lease();
    addTearDown(display.retire);
    display.adoptBaseline(
      ConversationBaseline(
        subscriptionId: 'sub',
        version: 1,
        items: [
          skillActivation('skill-1', 20, toolCallId: 'skill-view-1'),
          activity('command', 30, toolName: 'run_command'),
        ],
        before: 'older',
        hasOlder: true,
      ),
    );
    expect(
      display.prependOlder(
        ConversationPage(
          items: [skillCall('skill-view-1', 10)],
          before: null,
          hasOlder: false,
        ),
      ),
      1,
    );
    final groups = display.controller.messages.map(timelineEntryOf).toList();
    expect(groups, hasLength(1));
    expect(groups.single!.memberIds, ['skill-view-1', 'skill-1', 'command']);
    expect(groups.single!.visibleMemberIds, ['skill-1', 'command']);
    expect(groups.single!.pairedToolId('skill-1'), 'skill-view-1');
    expect(groups.single!.skillCount, 1);
    expect(groups.single!.toolCount, 1);
  });

  test('repeated loads of one skill stay separate by call identity', () {
    final display = lease();
    addTearDown(display.retire);
    display.adoptBaseline(
      ConversationBaseline(
        subscriptionId: 'sub',
        version: 1,
        before: null,
        hasOlder: false,
        items: [
          skillCall('skill-view-1', 1),
          skillActivation('skill-1', 2, toolCallId: 'skill-view-1'),
          skillCall('skill-view-2', 3),
          skillActivation('skill-2', 4, toolCallId: 'skill-view-2'),
        ],
      ),
    );
    final group = timelineEntryOf(display.controller.messages.single)!;
    expect(group.kind, TimelineEntryKind.activity);
    expect(group.memberIds, [
      'skill-view-1',
      'skill-1',
      'skill-view-2',
      'skill-2',
    ]);
    expect(group.visibleMemberIds, [
      'skill-1',
      'skill-2',
    ], reason: '同名技能的重复加载各占一行，各自配对到自己的调用');
    expect(group.pairedToolId('skill-1'), 'skill-view-1');
    expect(group.pairedToolId('skill-2'), 'skill-view-2');
    expect(group.skillCount, 2);
    expect(group.toolCount, 0);
  });

  test(
    'a half pair keeps the loaded side readable and converges when filled',
    () {
      final display = lease();
      addTearDown(display.retire);
      display.adoptBaseline(
        ConversationBaseline(
          subscriptionId: 'sub',
          version: 1,
          before: null,
          hasOlder: false,
          items: [
            activity('thinking', 1),
            skillActivation('skill-1', 2, toolCallId: 'skill-view-1'),
          ],
        ),
      );
      final group = display.presentationFor('skill-1')!;
      expect(group.visibleMemberIds, ['thinking', 'skill-1']);
      expect(group.pairedToolId('skill-1'), isNull);
      expect(group.skillCount, 1);
      expect(group.toolCount, 0);
      expect(
        display.applyPatch(
          ConversationPatch(
            subscriptionId: 'sub',
            from: 1,
            to: 2,
            priority: ConversationPriority.immediate,
            changes: [ConversationAdd(skillCall('skill-view-1', 3))],
          ),
        ),
        isTrue,
      );
      expect(display.presentationFor('skill-view-1'), same(group));
      expect(group.memberIds, ['thinking', 'skill-1', 'skill-view-1']);
      expect(group.visibleMemberIds, ['thinking', 'skill-1']);
      expect(group.pairedToolId('skill-1'), 'skill-view-1');
      expect(group.skillCount, 1);
      expect(group.toolCount, 0);
    },
  );

  test('a loaded tool stays its own row until the activation side arrives', () {
    final display = lease();
    addTearDown(display.retire);
    display.adoptBaseline(
      ConversationBaseline(
        subscriptionId: 'sub',
        version: 1,
        before: null,
        hasOlder: false,
        items: [skillCall('skill-view-1', 1)],
      ),
    );
    final group = display.presentationFor('skill-view-1')!;
    expect(group.visibleMemberIds, ['skill-view-1']);
    expect(group.pairedToolId('skill-view-1'), isNull);
    expect(group.skillCount, 0);
    expect(group.toolCount, 1);
    expect(
      display.applyPatch(
        ConversationPatch(
          subscriptionId: 'sub',
          from: 1,
          to: 2,
          priority: ConversationPriority.immediate,
          changes: [
            ConversationAdd(
              skillActivation('skill-1', 2, toolCallId: 'skill-view-1'),
            ),
          ],
        ),
      ),
      isTrue,
    );
    expect(group.visibleMemberIds, ['skill-1']);
    expect(group.pairedToolId('skill-1'), 'skill-view-1');
    expect(group.skillCount, 1);
    expect(group.toolCount, 0);
  });

  test('only a successful skill_view call of the same turn is paired', () {
    final display = lease();
    addTearDown(display.retire);
    display.adoptBaseline(
      ConversationBaseline(
        subscriptionId: 'sub',
        version: 1,
        before: null,
        hasOlder: false,
        items: [
          // 运行中的技能读取没有任何激活事实：保留真实工具行。
          skillCall('skill-view-running', 1, succeeded: false),
          // 支持文件读取不是主技能加载：即使身份巧合也不配对。
          skillCall('support-read', 2, name: 'read_file'),
          skillActivation('skill-support', 3, toolCallId: 'support-read'),
          // 用户手势来源不猜测与工具调用配对。
          skillCall('gesture-call', 4),
          skillActivation('skill-gesture', 5, gestureId: 'gesture-call'),
          // 不同 Turn 的成功调用不跨 Turn 配对。
          skillCall('other-turn-call', 6, turnId: 'turn-b'),
          skillActivation(
            'skill-other-turn',
            7,
            toolCallId: 'other-turn-call',
            turnId: 'turn-b',
          ),
        ],
      ),
    );
    final groups = display.controller.messages.map(timelineEntryOf).toList();
    final first = groups.first!;
    expect(first.memberIds, [
      'skill-view-running',
      'support-read',
      'skill-support',
      'gesture-call',
      'skill-gesture',
    ]);
    expect(first.visibleMemberIds, [
      'skill-view-running',
      'support-read',
      'skill-support',
      'gesture-call',
      'skill-gesture',
    ]);
    expect(first.pairedToolId('skill-support'), isNull);
    expect(first.pairedToolId('skill-gesture'), isNull);
    expect(first.skillCount, 2);
    expect(first.toolCount, 3);
    final second = groups.last!;
    expect(second.memberIds, ['other-turn-call', 'skill-other-turn']);
    expect(second.visibleMemberIds, ['skill-other-turn']);
    expect(second.pairedToolId('skill-other-turn'), 'other-turn-call');
  });

  test('removing the activation side restores the real tool row', () {
    final display = lease();
    addTearDown(display.retire);
    display.adoptBaseline(
      ConversationBaseline(
        subscriptionId: 'sub',
        version: 1,
        before: null,
        hasOlder: false,
        items: [
          activity('thinking', 10),
          skillCall('skill-view-1', 20),
          skillActivation('skill-1', 30, toolCallId: 'skill-view-1'),
        ],
      ),
    );
    final group = display.presentationFor('skill-1')!;
    final groupId = group.id;
    expect(group.visibleMemberIds, ['thinking', 'skill-1']);
    expect(
      display.applyPatch(
        ConversationPatch(
          subscriptionId: 'sub',
          from: 1,
          to: 2,
          priority: ConversationPriority.immediate,
          changes: [const ConversationRemove('skill-1')],
        ),
      ),
      isTrue,
    );
    expect(display.presentationFor('skill-view-1'), same(group));
    expect(group.id, groupId);
    expect(group.visibleMemberIds, ['thinking', 'skill-view-1']);
    expect(group.skillCount, 0);
    expect(group.toolCount, 1);
  });

  test('a body split leaves a half pair readable on both sides', () {
    final display = lease();
    addTearDown(display.retire);
    display.adoptBaseline(
      ConversationBaseline(
        subscriptionId: 'sub',
        version: 1,
        before: null,
        hasOlder: false,
        items: [
          activity('thinking', 10),
          skillCall('skill-view-1', 20),
          skillActivation('skill-1', 30, toolCallId: 'skill-view-1'),
        ],
      ),
    );
    expect(display.presentationFor('skill-1')!.visibleMemberIds, [
      'thinking',
      'skill-1',
    ]);
    // 正文划分活动边界：技能与其调用分到两组的半对仍各自可读。
    expect(
      display.applyPatch(
        ConversationPatch(
          subscriptionId: 'sub',
          from: 1,
          to: 2,
          priority: ConversationPriority.immediate,
          changes: [ConversationAdd(item('answer', 25))],
        ),
      ),
      isTrue,
    );
    final afterSplit = display.controller.messages
        .map(timelineEntryOf)
        .toList();
    expect(afterSplit.map((g) => g!.kind), [
      TimelineEntryKind.activity,
      TimelineEntryKind.single,
      TimelineEntryKind.activity,
    ]);
    expect(afterSplit.first!.visibleMemberIds, ['thinking', 'skill-view-1']);
    expect(afterSplit.first!.toolCount, 1);
    expect(afterSplit.first!.skillCount, 0);
    expect(afterSplit.last!.visibleMemberIds, ['skill-1']);
    expect(afterSplit.last!.pairedToolId('skill-1'), isNull);
    expect(afterSplit.last!.skillCount, 1);
    expect(afterSplit.last!.toolCount, 0);
  });

  test('a running skill read joins the skill line only after commit', () {
    final display = lease();
    addTearDown(display.retire);
    display.adoptBaseline(
      ConversationBaseline(
        subscriptionId: 'sub',
        version: 1,
        before: null,
        hasOlder: false,
        items: [
          activity('thinking', 1),
          skillActivation('skill-1', 2, toolCallId: 'skill-view-1'),
          skillCall('skill-view-1', 3, succeeded: false),
        ],
      ),
    );
    final group = display.presentationFor('skill-1')!;
    expect(group.visibleMemberIds, ['thinking', 'skill-1', 'skill-view-1']);
    expect(group.pairedToolId('skill-1'), isNull);
    expect(group.toolCount, 1);
    expect(group.skillCount, 1);
    const memberId = 'skill-view-1';
    final member = group.member(memberId);
    // 监听器里只记录它看到的派生事实，断言在派发结束后进行。
    final seen = <String>[];
    member.addListener(() {
      seen.add(
        [
          switch ((member.item.descriptor as ConversationToolDescriptor)
              .state) {
            ConversationToolSucceeded() => 'succeeded',
            ConversationToolFailed() => 'failed',
            _ => 'other',
          },
          group.visibleMemberIds.join('|'),
          group.visibleMemberIds.contains('skill-view-1')
              ? 'visible'
              : 'hidden',
          group.pairedToolId('skill-1') ?? 'unpaired',
          'tools=${group.toolCount}',
          'running=${group.members.where((item) => item.descriptor is ConversationToolDescriptor && (item.descriptor as ConversationToolDescriptor).state is ConversationToolRunning).length}',
          'skills=${group.skillCount}',
          identical(display.presentationFor('skill-view-1'), group)
              ? 'same-owner'
              : 'other-owner',
        ].join(','),
      );
    });
    expect(
      display.applyPatch(
        ConversationPatch(
          subscriptionId: 'sub',
          from: 1,
          to: 2,
          priority: ConversationPriority.immediate,
          changes: [ConversationAdd(skillCall('skill-view-1', 3, revision: 2))],
        ),
      ),
      isTrue,
    );
    expect(seen, [
      'succeeded,thinking|skill-1,hidden,skill-view-1,tools=0,running=0,'
          'skills=1,same-owner',
    ]);
    expect(group.visibleMemberIds, ['thinking', 'skill-1']);
  });

  test('a failed original call releases its skill line before commit', () {
    final display = lease();
    addTearDown(display.retire);
    display.adoptBaseline(
      ConversationBaseline(
        subscriptionId: 'sub',
        version: 1,
        before: null,
        hasOlder: false,
        items: [
          activity('thinking', 1),
          skillCall('skill-view-1', 2),
          skillActivation('skill-1', 3, toolCallId: 'skill-view-1'),
        ],
      ),
    );
    final group = display.presentationFor('skill-1')!;
    expect(group.visibleMemberIds, ['thinking', 'skill-1']);
    expect(group.pairedToolId('skill-1'), 'skill-view-1');
    const memberId = 'skill-view-1';
    final member = group.member(memberId);
    final seen = <String>[];
    member.addListener(() {
      seen.add(
        [
          switch ((member.item.descriptor as ConversationToolDescriptor)
              .state) {
            ConversationToolSucceeded() => 'succeeded',
            ConversationToolFailed() => 'failed',
            _ => 'other',
          },
          group.visibleMemberIds.join('|'),
          group.visibleMemberIds.contains('skill-view-1')
              ? 'visible'
              : 'hidden',
          group.pairedToolId('skill-1') ?? 'unpaired',
          'tools=${group.toolCount}',
          'skills=${group.skillCount}',
          identical(display.presentationFor('skill-1'), group)
              ? 'same-owner'
              : 'other-owner',
        ].join(','),
      );
    });
    expect(
      display.applyPatch(
        ConversationPatch(
          subscriptionId: 'sub',
          from: 1,
          to: 2,
          priority: ConversationPriority.immediate,
          changes: [
            ConversationAdd(
              skillCall(
                'skill-view-1',
                2,
                revision: 2,
                lifecycle: ConversationToolFailed(
                  failedAt: DateTime.utc(2026),
                  failure: const ThreadToolFailureView(
                    kind: ThreadToolFailureKindView.execution,
                    message: 'skill load failed',
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
      isTrue,
    );
    expect(seen, [
      'failed,thinking|skill-view-1|skill-1,visible,unpaired,tools=1,'
          'skills=1,same-owner',
    ]);
    expect(group.visibleMemberIds, ['thinking', 'skill-view-1', 'skill-1']);
  });

  test('a skill whose cause stops naming its call releases its own pair', () {
    final display = lease();
    addTearDown(display.retire);
    display.adoptBaseline(
      ConversationBaseline(
        subscriptionId: 'sub',
        version: 1,
        before: null,
        hasOlder: false,
        items: [
          activity('thinking', 1),
          skillCall('skill-view-1', 2),
          skillActivation('skill-1', 3, toolCallId: 'skill-view-1'),
        ],
      ),
    );
    final group = display.presentationFor('skill-1')!;
    expect(group.visibleMemberIds, ['thinking', 'skill-1']);
    expect(group.pairedToolId('skill-1'), 'skill-view-1');
    const memberId = 'skill-1';
    final member = group.member(memberId);
    final seen = <String>[];
    member.addListener(() {
      seen.add(
        [
          (member.item.descriptor as ConversationSkillDescriptor)
              .value
              .cause
              .kind
              .name,
          group.visibleMemberIds.join('|'),
          group.visibleMemberIds.contains('skill-view-1')
              ? 'visible'
              : 'hidden',
          group.pairedToolId('skill-1') ?? 'unpaired',
          'tools=${group.toolCount}',
          'skills=${group.skillCount}',
          identical(display.presentationFor('skill-1'), group)
              ? 'same-owner'
              : 'other-owner',
        ].join(','),
      );
    });
    void replaceCause(ConversationItem item) {
      final from = display.appliedVersion!;
      expect(
        display.applyPatch(
          ConversationPatch(
            subscriptionId: 'sub',
            from: from,
            to: from + 1,
            priority: ConversationPriority.immediate,
            changes: [ConversationAdd(item)],
          ),
        ),
        isTrue,
      );
    }

    // 来源改成用户手势：该技能不再接管任何调用，原调用重新成为真实工具行。
    replaceCause(
      skillActivation('skill-1', 3, gestureId: 'gesture-9', revision: 2),
    );
    // 来源再改成空身份：仍不是可配对调用。
    replaceCause(skillActivation('skill-1', 3, toolCallId: '', revision: 3));
    // 来源恢复为原调用身份：重新配对，调用让位给技能行。
    replaceCause(
      skillActivation('skill-1', 3, toolCallId: 'skill-view-1', revision: 4),
    );
    expect(seen, [
      'userGesture,thinking|skill-view-1|skill-1,visible,unpaired,tools=1,'
          'skills=1,same-owner',
      'tool,thinking|skill-view-1|skill-1,visible,unpaired,tools=1,skills=1,'
          'same-owner',
      'tool,thinking|skill-1,hidden,skill-view-1,tools=0,skills=1,same-owner',
    ]);
    expect(group.visibleMemberIds, ['thinking', 'skill-1']);
    expect(group.pairedToolId('skill-1'), 'skill-view-1');
  });

  test(
    'a lone wait still uses an activity container rather than a single card',
    () {
      final display = lease();
      addTearDown(display.retire);
      display.adoptBaseline(
        ConversationBaseline(
          subscriptionId: 'sub',
          version: 1,
          before: null,
          hasOlder: false,
          items: [waitCall('wait-only', 1)],
        ),
      );
      final group = timelineEntryOf(display.controller.messages.single)!;
      expect(group.kind, TimelineEntryKind.activity);
      expect(group.memberIds, ['wait-only']);
      expect(group.id, isNot('wait-only'));
      expect(
        (group.members.firstWhere((item) => item.id == 'wait-only').descriptor
                as ConversationToolDescriptor)
            .wait!,
        isNotNull,
      );
    },
  );

  test('paging joins an older wait into the live activity group without resetting expansion', () {
    final display = lease();
    addTearDown(display.retire);
    display.adoptBaseline(
      ConversationBaseline(
        subscriptionId: 'sub',
        version: 1,
        items: [activity('command', 30, toolName: 'run_command')],
        before: 'older',
        hasOlder: true,
      ),
    );
    final original = timelineEntryOf(display.controller.messages.single)!;
    original.expanded = true;
    expect(
      display.prependOlder(
        ConversationPage(
          items: [activity('thinking', 10), waitCall('wait-older', 20)],
          before: null,
          hasOlder: false,
        ),
      ),
      2,
    );
    expect(display.controller.messages, hasLength(1));
    expect(display.controller.messages.single.id, original.id);
    expect(original.kind, TimelineEntryKind.activity);
    expect(original.memberIds, ['thinking', 'wait-older', 'command']);
    expect(original.expanded, isTrue);
    expect(
      (original.members.firstWhere((item) => item.id == 'wait-older').descriptor
              as ConversationToolDescriptor)
          .wait!
          .state,
      ThreadWaitStateView.waiting,
    );
  });

  test(
    'wait terminal updates keep group identity, expansion and typed wait facts',
    () {
      final display = lease();
      addTearDown(display.retire);
      display.adoptBaseline(
        ConversationBaseline(
          subscriptionId: 'sub',
          version: 1,
          before: null,
          hasOlder: false,
          items: [
            activity('thinking', 1),
            waitCall('wait-1', 2),
            activity('command', 3, toolName: 'run_command'),
          ],
        ),
      );
      final group = timelineEntryOf(display.controller.messages.single)!;
      group.expanded = true;
      final groupId = group.id;
      expect(
        display.applyPatch(
          ConversationPatch(
            subscriptionId: 'sub',
            from: 1,
            to: 2,
            priority: ConversationPriority.immediate,
            changes: [
              ConversationAdd(
                waitCall(
                  'wait-1',
                  2,
                  state: ThreadWaitStateView.ready,
                  revision: 2,
                  result: '{"tasks":[{"taskId":"task:exec-1","status":"succeeded"}],"timedOut":false}',
                  lifecycle: ConversationToolSucceeded(
                    completedAt: DateTime.utc(2026),
                    output: ConversationToolOutputDescriptor(attachments: []),
                  ),
                  itemLifecycle: ConversationLifecycle.terminal,
                ),
              ),
            ],
          ),
        ),
        isTrue,
      );
      expect(display.controller.messages, hasLength(1));
      expect(display.presentationFor('wait-1'), same(group));
      expect(group.id, groupId);
      expect(group.expanded, isTrue);
      expect(group.memberIds, ['thinking', 'wait-1', 'command']);
      final wait =
          (group.members.firstWhere((item) => item.id == 'wait-1').descriptor
                  as ConversationToolDescriptor)
              .wait!;
      expect(wait.state, ThreadWaitStateView.ready);
      expect(
        group.members.firstWhere((item) => item.id == 'wait-1').terminal,
        isTrue,
      );
      expect(
        group.members
            .firstWhere((item) => item.id == 'wait-1')
            .fieldFor(const ThreadToolResultFieldView())
            ?.text,
        contains('task:exec-1'),
      );
    },
  );

  test('bodies, userInput, plan receipts and real different turns still split wait groups', () {
    final display = lease();
    addTearDown(display.retire);
    display.adoptBaseline(
      ConversationBaseline(
        subscriptionId: 'sub',
        version: 1,
        before: null,
        hasOlder: false,
        items: [
          activity('thinking', 1),
          waitCall('wait-1', 2),
          item('answer', 3),
          activity('next-thinking', 4),
          waitCall('wait-2', 5),
          userInputCall('ask-1', 6),
          activity('after-ask', 7, toolName: 'run_command'),
          planReceiptCall('plan-1', 8),
          activity('turn-b-thinking', 9, turnId: 'turn-b'),
          waitCall('wait-turn-b', 10, turnId: 'turn-b'),
        ],
      ),
    );
    final groups = display.controller.messages.map(timelineEntryOf).toList();
    expect(groups.map((g) => g!.kind).toList(), [
      TimelineEntryKind.activity,
      TimelineEntryKind.single,
      TimelineEntryKind.activity,
      TimelineEntryKind.single,
      TimelineEntryKind.activity,
      TimelineEntryKind.single,
      TimelineEntryKind.activity,
    ]);
    expect(groups.map((g) => g!.memberIds).toList(), [
      ['thinking', 'wait-1'],
      ['answer'],
      ['next-thinking', 'wait-2'],
      ['ask-1'],
      ['after-ask'],
      ['plan-1'],
      ['turn-b-thinking', 'wait-turn-b'],
    ]);
    expect(
      (groups[0]!.members.firstWhere((item) => item.id == 'wait-1').descriptor
              as ConversationToolDescriptor)
          .wait,
      isNotNull,
    );
    expect(
      (groups[2]!.members.firstWhere((item) => item.id == 'wait-2').descriptor
              as ConversationToolDescriptor)
          .wait,
      isNotNull,
    );
    expect(groups[3]!.kind, TimelineEntryKind.single);
    expect(groups[3]!.id, 'ask-1');
    expect(groups[5]!.kind, TimelineEntryKind.single);
    expect(groups[5]!.id, 'plan-1');
    expect(groups[6]!.first.header.turnId, 'turn-b');
    expect(groups[0]!.first.header.turnId, 'turn');
  });

  test('retry and result records of one attempt share one GUI item', () {
    ConversationItem recovery(
      String id,
      int order,
      ConversationRecoveryNotice notice,
    ) => conversationCopyFixture(
      item(id, order),
      source: ConversationRecoverySource(attemptId: 'attempt', notice: notice),
      saved: true,
      lifecycle: ConversationLifecycle.terminal,
    );
    final display = lease();
    display.adoptBaseline(
      ConversationBaseline(
        subscriptionId: 'sub',
        version: 1,
        before: null,
        hasOlder: false,
        items: [
          recovery('retry-1', 1, ConversationRecoveryNotice.retry),
          recovery('retry-2', 2, ConversationRecoveryNotice.retry),
          recovery('result', 3, ConversationRecoveryNotice.result),
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
        ConversationBaseline(
          subscriptionId: 'sub',
          version: 1,
          items: [activity('c', 30), activity('d', 40)],
          before: 'older',
          hasOlder: true,
        ),
      );
      final original = timelineEntryOf(display.controller.messages.single)!;
      original.expanded = true;
      expect(
        display.prependOlder(
          ConversationPage(
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
          ConversationPatch(
            priority: ConversationPriority.immediate,
            subscriptionId: 'sub',
            from: 1,
            to: 2,
            changes: [ConversationAdd(item('divider', 25))],
          ),
        ),
        isTrue,
      );
      expect(display.controller.messages.length, 3);
      expect(timelineEntryOf(display.controller.messages.last), same(original));
      expect(original.memberIds, ['c', 'd']);
      final prefix = timelineEntryOf(display.controller.messages.first)!;
      expect(prefix.memberIds, ['a', 'b']);
      expect(prefix.expanded, isTrue);
      expect(
        display.applyPatch(
          ConversationPatch(
            priority: ConversationPriority.immediate,
            subscriptionId: 'sub',
            from: 2,
            to: 3,
            changes: [const ConversationRemove('divider')],
          ),
        ),
        isTrue,
      );
      expect(display.controller.messages.single.id, original.id);
      expect(original.memberIds, ['a', 'b', 'c', 'd']);
      expect(display.items.map((p) => p.id), ['a', 'b', 'c', 'd']);
    },
  );

  test('streaming updates only its member and summary; History freezes the whole group', () {
    final display = lease();
    addTearDown(display.retire);
    display.adoptBaseline(
      ConversationBaseline(
        subscriptionId: 'sub',
        version: 1,
        items: [activity('a', 1), activity('b', 2)],
        before: null,
        hasOlder: false,
      ),
    );
    final group = timelineEntryOf(display.controller.messages.single)!;
    var changed = 0;
    var unaffected = 0;
    var structural = 0;
    group.member('a').addListener(() => changed++);
    group.member('b').addListener(() => unaffected++);
    group.addListener(() => structural++);
    expect(
      display.applyPatch(
        ConversationPatch(
          priority: ConversationPriority.immediate,
          subscriptionId: 'sub',
          from: 1,
          to: 2,
          changes: [ConversationAdd(activity('a', 1, revision: 2))],
        ),
      ),
      isTrue,
    );
    expect(display.itemOf('a')!.revision, 2);
    expect(changed, 1);
    expect(unaffected, 0);
    expect(structural, 0);
    expect(display.controller.messages.single.id, group.id);
    display.enterHistory();
    expect(
      display.applyPatch(
        ConversationPatch(
          priority: ConversationPriority.immediate,
          subscriptionId: 'sub',
          from: 2,
          to: 3,
          changes: [
            ConversationAdd(activity('a', 1, revision: 3)),
            const ConversationRemove('b'),
          ],
        ),
      ),
      isTrue,
    );
    expect(group.memberIds, ['a', 'b']);
    expect(display.itemOf('a')!.revision, 2);
    expect(changed, 1);
  });

  test('structural listeners observe committed member ownership', () {
    final display = lease();
    addTearDown(display.retire);
    display.adoptBaseline(
      ConversationBaseline(
        subscriptionId: 'sub',
        version: 1,
        items: [activity('a', 10)],
        before: null,
        hasOlder: false,
      ),
    );
    final group = display.presentationFor('a')!;
    group.addListener(() {
      for (final id in group.memberIds) {
        expect(display.presentationFor(id), same(group));
        expect(
          display.itemOf(id),
          same(group.members.firstWhere((item) => item.id == id)),
        );
      }
    });
    display.applyPatch(
      ConversationPatch(
        subscriptionId: 'sub',
        from: 1,
        to: 2,
        priority: ConversationPriority.immediate,
        changes: [ConversationAdd(activity('b', 20))],
      ),
    );
    final member = group.member('a');
    member.addListener(() {
      expect(display.itemOf('a'), same(member.item));
      expect(display.presentationFor('a')!.member('a'), same(member));
    });
    display.applyPatch(
      ConversationPatch(
        subscriptionId: 'sub',
        from: 2,
        to: 3,
        priority: ConversationPriority.immediate,
        changes: [
          ConversationAdd(
            conversationCopyFixture(
              item('a', 2),
              saved: false,
              lifecycle: ConversationLifecycle.streaming,
              ordinal: 10,
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
        ConversationBaseline(
          subscriptionId: 'sub',
          version: 1,
          items: [activity('a', 10), activity('b', 20)],
          before: null,
          hasOlder: false,
        ),
      );
      final group = display.presentationFor('a')!..expanded = true;
      display.applyPatch(
        ConversationPatch(
          subscriptionId: 'sub',
          from: 1,
          to: 2,
          priority: ConversationPriority.immediate,
          changes: [
            const ConversationRemove('a'),
            ConversationAdd(item('divider', 15)),
          ],
        ),
      );
      expect(display.presentationFor('b'), same(group));
      expect(group.expanded, isTrue);
      expect(
        display.controller.messages.map((m) => timelineEntryOf(m)!.memberIds),
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
        ConversationBaseline(
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
      final groups = display.controller.messages.map(timelineEntryOf).toList();
      expect(groups.map((g) => g!.kind), [
        TimelineEntryKind.images,
        TimelineEntryKind.activity,
        TimelineEntryKind.images,
      ]);
      expect(groups.first!.memberIds, ['image-a', 'image-b']);
      expect(groups.last!.memberIds, ['image-c']);
    },
  );

  ConversationItem toolTerminal(
    String id,
    int order, {
    required ConversationToolState lifecycle,
    ThreadWaitStateView? waitState,
  }) => conversationFixture(
    id: id,
    threadId: 'thread',
    turnId: 'turn',
    ordinal: order,
    revision: 2,
    createdAt: DateTime.utc(2026),
    updatedAt: DateTime.utc(2026),
    saved: false,
    lifecycle: ConversationLifecycle.terminal,
    descriptor: ConversationToolDescriptor(
      invocation: ConversationToolInvocation(
        toolCallId: id,
        name: 'run_command',
      ),
      wait: waitState == null
          ? null
          : ThreadWaitPresentationView(
              intent: ThreadWaitEventsIntentView(
                targets: [
                  ThreadWaitTargetView(
                    taskId: 'task:exec-1',
                    toolName: 'exec',
                    summary: 'cargo test',
                    status: ThreadWaitTargetStatusView.cancelled,
                  ),
                ],
                timeoutMs: 60000,
              ),
              state: waitState,
            ),
      state: lifecycle,
    ),
    fields: {const ThreadToolArgumentsFieldView(): '{}'},
  );

  ConversationItem turnCall(String id, int order, StudioTurnState state) =>
      conversationFixture(
        id: id,
        threadId: 'thread',
        turnId: 'turn',
        ordinal: order,
        revision: 1,
        createdAt: DateTime.utc(2026),
        updatedAt: DateTime.utc(2026),
        saved: false,
        lifecycle: ConversationLifecycle.terminal,
        descriptor: ConversationTurnDescriptor(ThreadTurnItemStateView(state)),
        fields: {},
      );

  test(
    'stopping a turn keeps cancelled members neutral without losing identity',
    () {
      final display = lease();
      addTearDown(display.retire);
      display.adoptBaseline(
        ConversationBaseline(
          subscriptionId: 'sub',
          version: 1,
          before: null,
          hasOlder: false,
          items: [
            activity('thinking', 1),
            activity('command', 2, toolName: 'run_command'),
            waitCall('wait-1', 3),
          ],
        ),
      );
      final group = timelineEntryOf(display.controller.messages.single)!;
      group.expanded = true;
      expect(group.issueCount, 0);

      // 真实 canonical 终态：用户停止后工具 interrupted、等待 cancelled。
      expect(
        display.applyPatch(
          ConversationPatch(
            subscriptionId: 'sub',
            from: 1,
            to: 2,
            priority: ConversationPriority.immediate,
            changes: [
              ConversationAdd(
                activity(
                  'thinking',
                  1,
                  revision: 2,
                  contentLifecycle: CancelledThreadContentView(
                    DateTime.utc(2026),
                    'Interrupted',
                  ),
                  itemLifecycle: ConversationLifecycle.terminal,
                ),
              ),
              ConversationAdd(
                toolTerminal(
                  'command',
                  2,
                  lifecycle: ConversationToolInterrupted(
                    interruptedAt: DateTime.utc(2026),
                    reason: 'Interrupted',
                  ),
                ),
              ),
              ConversationAdd(
                toolTerminal(
                  'wait-1',
                  3,
                  lifecycle: ConversationToolCancelled(
                    cancelledAt: DateTime.utc(2026),
                    reason: 'Cancelled',
                  ),
                  waitState: ThreadWaitStateView.cancelled,
                ),
              ),
            ],
          ),
        ),
        isTrue,
      );

      expect(display.presentationFor('command'), same(group));
      expect(group.id, startsWith('timeline-group:'));
      expect(group.memberIds, ['thinking', 'command', 'wait-1']);
      expect(group.expanded, isTrue, reason: '展开意图不因终态重置');
      expect(group.issueCount, 0, reason: '取消与中断不是问题');
      expect(group.activeCount, 0);
      expect(
        group.members.firstWhere((item) => item.id == 'command').terminal,
        isTrue,
      );
      expect(
        group.members.firstWhere((item) => item.id == 'wait-1').terminal,
        isTrue,
      );
    },
  );

  test('real failures still count while cancelled members add none', () {
    final display = lease();
    addTearDown(display.retire);
    display.adoptBaseline(
      ConversationBaseline(
        subscriptionId: 'sub',
        version: 1,
        before: null,
        hasOlder: false,
        items: [
          activity('thinking', 1),
          activity('broken', 2, toolName: 'run_command'),
          activity('stopped', 3, toolName: 'run_command'),
        ],
      ),
    );
    expect(
      display.applyPatch(
        ConversationPatch(
          subscriptionId: 'sub',
          from: 1,
          to: 2,
          priority: ConversationPriority.immediate,
          changes: [
            ConversationAdd(
              activity(
                'thinking',
                1,
                revision: 2,
                contentLifecycle: CancelledThreadContentView(
                  DateTime.utc(2026),
                  'Interrupted',
                ),
                itemLifecycle: ConversationLifecycle.terminal,
              ),
            ),
            ConversationAdd(
              toolTerminal(
                'broken',
                2,
                lifecycle: ConversationToolFailed(
                  failedAt: DateTime.utc(2026),
                  failure: const ThreadToolFailureView(
                    kind: ThreadToolFailureKindView.execution,
                    message: 'exit code 1',
                  ),
                ),
              ),
            ),
            ConversationAdd(
              toolTerminal(
                'stopped',
                3,
                lifecycle: ConversationToolInterrupted(
                  interruptedAt: DateTime.utc(2026),
                  reason: 'Interrupted',
                ),
              ),
            ),
          ],
        ),
      ),
      isTrue,
    );
    final group = timelineEntryOf(display.controller.messages.single)!;
    expect(group.memberIds, ['thinking', 'broken', 'stopped']);
    expect(group.issueCount, 1, reason: '只有真实失败计入问题数量');
    expect(group.activeCount, 0);
  });

  test('an interrupted turn stays visible without becoming an issue', () {
    final display = lease();
    addTearDown(display.retire);
    display.adoptBaseline(
      ConversationBaseline(
        subscriptionId: 'sub',
        version: 1,
        before: null,
        hasOlder: false,
        items: [activity('thinking', 1)],
      ),
    );
    expect(
      display.applyPatch(
        ConversationPatch(
          subscriptionId: 'sub',
          from: 1,
          to: 2,
          priority: ConversationPriority.immediate,
          changes: [
            ConversationAdd(
              turnCall(
                'turn-end',
                2,
                const CancelledStudioTurnState(
                  startedAt: 1,
                  requestedAt: 2,
                  completedAt: 3,
                  cause: InterruptedTurnCancellation(),
                ),
              ),
            ),
          ],
        ),
      ),
      isTrue,
    );
    final payload = display.itemOf('turn-end')!;
    expect(
      (payload.descriptor as ConversationTurnDescriptor).value.state,
      isA<CancelledStudioTurnState>(),
    );
    expect(
      timelineKind(payload) != TimelineEntryKind.hidden,
      isTrue,
      reason: '停止终态必须可见，不能被当作空内容隐藏',
    );
    expect(
      timelineEntryOf(display.controller.messages.last)!.issueCount,
      0,
      reason: 'interrupted turn 不产生问题指示',
    );
  });
}
