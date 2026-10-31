import 'dart:async';

import 'package:anywork/src/features/conversation/timeline/state/timeline_atom_equality.dart';
import 'package:anywork/src/features/conversation/timeline/state/timeline_entry.dart';
import 'package:anywork/src/features/conversation/timeline/state/timeline_image_resources.dart';
import 'package:anywork/src/features/conversation/timeline/view_models/timeline_message_controller.dart';
import 'package:anywork_client/models.dart';
import 'package:flutter_chat_core/flutter_chat_core.dart';
import 'package:flutter_test/flutter_test.dart';

final _completedAt = DateTime.utc(2026, 1, 1);

ConversationItem _atom(
  int seq, {
  String? id,
  String? turn = 'turn',
  String text = '',
  ConversationDescriptor? descriptor,
  ConversationItemSource source = const ConversationContentSource(),
  int? sealedAt,
}) => ConversationItem(
  header: ConversationItemHeader(
    id: id ?? 'atom-$seq',
    threadId: 'thread',
    turnId: turn,
    appendSeq: seq,
    sealedAt: sealedAt,
  ),
  descriptor:
      descriptor ??
      ConversationThinkingDescriptor(
        outcome: ConversationContentCompleted(
          CompletedThreadContentView(_completedAt),
        ),
      ),
  source: source,
  fields: [
    ConversationFieldPreview(
      field: const ThreadTextFieldView(),
      text: text,
      totalBytes: text.length,
    ),
  ],
);

ConversationDescriptor _text({
  List<ThreadAttachmentView> attachments = const [],
}) => ConversationTextDescriptor(
  channel: ThreadTextChannel.finalAnswer,
  attachments: attachments,
  outcome: ConversationContentCompleted(
    CompletedThreadContentView(_completedAt),
  ),
);

ConversationDescriptor _tool({
  String name = 'exec',
  String call = 'call',
  ConversationToolState? state,
  List<ThreadAttachmentView> attachments = const [],
}) => ConversationToolDescriptor(
  invocation: ConversationToolInvocation(toolCallId: call, name: name),
  state:
      state ??
      ConversationToolSucceeded(
        completedAt: _completedAt,
        output: ConversationToolOutputDescriptor(attachments: attachments),
      ),
);

ConversationDescriptor _skill({String call = 'call'}) =>
    ConversationSkillDescriptor(
      ThreadSkillItemStateView(
        name: 'skill',
        source: 'project',
        providerId: 'provider',
        resourceBase: const SkillResourceBaseView(
          SkillResourceBaseKind.directory,
          'skills/skill',
        ),
        cause: SkillActivationCauseView(SkillActivationCauseKind.tool, call),
        activatedAt: _completedAt,
      ),
    );

const _image = ThreadAttachmentView(
  id: 'image',
  modality: AttachmentModalityView.image,
  mediaType: 'image/png',
  byteSize: 100,
);
const _file = ThreadAttachmentView(
  id: 'file',
  modality: AttachmentModalityView.file,
  mediaType: 'text/plain',
  byteSize: 5,
);

void main() {
  late InMemoryChatController stock;
  late TimelineMessageController model;
  late TimelineImageResources images;
  late List<ChatOperation> operations;
  late StreamSubscription<ChatOperation> subscription;

  setUp(() {
    stock = InMemoryChatController();
    images = TimelineImageResources(threadId: 'thread');
    model = TimelineMessageController(
      stock,
      generation: 7,
      imageResources: images,
    );
    operations = [];
    subscription = stock.operationsStream.listen(operations.add);
  });

  tearDown(() async {
    model.dispose();
    images.release();
    await subscription.cancel();
    stock.dispose();
  });

  Future<void> flush() => Future<void>.delayed(Duration.zero);

  test('首屏使用不动画的 set，单活动原子立即为固定组壳', () async {
    final item = _atom(10, text: 'completed');
    await model.initialize([item]);
    await flush();
    expect(operations.single.type, ChatOperationType.set);
    expect(operations.single.animated, isFalse);
    expect(stock.messages.single, isA<CustomMessage>());
    final entry = timelineEntryOf(stock.messages.single)!;
    expect(entry.kind, TimelineEntryKind.activity);
    expect(entry.anchorItemId, item.id);
    expect(entry.item(item.id), same(item));
    expect(entry.member(item.id).item, same(item));
    expect(stock.messages.single.createdAt, isNull);
    expect(entry.elapsedDuration, isNull);
  });

  test('完成批仅更新尾组一次并批量插入，正文切断组且旧消息不动', () async {
    await model.initialize([
      _atom(1, descriptor: _text(), text: 'old body'),
      _atom(2),
    ]);
    final oldBody = stock.messages.first;
    final tail = stock.messages.last;
    final entry = timelineEntryOf(tail)!;
    entry.toggle();
    entry.setMemberExpanded('atom-2', true);
    final row = model.memberObservation('atom-2');
    await flush();
    operations.clear();

    await model.append([
      _atom(3, descriptor: _tool()),
      _atom(4, descriptor: _text(), text: 'separator'),
      _atom(5),
      _atom(6, descriptor: _tool()),
    ]);
    await flush();
    expect(operations.map((op) => op.type), [
      ChatOperationType.update,
      ChatOperationType.insertAll,
    ]);
    expect(operations.first.oldMessage, same(tail));
    expect(operations.last.messages, hasLength(2));
    expect(stock.messages.first, same(oldBody));
    expect(stock.messages[1].id, tail.id);
    expect(timelineEntryOf(stock.messages[1]), same(entry));
    expect(entry.anchorItemId, 'atom-2');
    expect(entry.memberIds, ['atom-2', 'atom-3']);
    expect(entry.expanded, isTrue);
    expect(entry.isMemberExpanded('atom-2'), isTrue);
    expect(model.memberObservation('atom-2'), same(row));
    expect(model.ownerOf('atom-5'), isNot(same(entry)));
    expect(model.ownerOf('atom-5'), same(model.ownerOf('atom-6')));
  });

  test('整页并入首组仍返回新增原子数，anchor/消息/展开保持稳定', () async {
    await model.initialize([_atom(10), _atom(11)]);
    final message = stock.messages.single;
    final entry = timelineEntryOf(message)!;
    entry.toggle();
    entry.setMemberExpanded('atom-10', true);
    final row = model.memberObservation('atom-10');
    await flush();
    operations.clear();
    expect(await model.prepend([_atom(8), _atom(9)]), 2);
    await flush();
    expect(operations.single.type, ChatOperationType.update);
    expect(stock.messages, hasLength(1));
    expect(stock.messages.single.id, message.id);
    expect(entry.anchorItemId, 'atom-10');
    expect(entry.first.id, 'atom-8');
    expect(entry.memberIds, ['atom-8', 'atom-9', 'atom-10', 'atom-11']);
    expect(entry.position, (8, 'atom-8'));
    expect(entry.expanded, isTrue);
    expect(entry.isMemberExpanded('atom-10'), isTrue);
    expect(model.memberObservation('atom-10'), same(row));
    expect(model.length, 4);
  });

  test('旧页仅首边界合组，其余旧消息引用保持，不动画插入一次', () async {
    await model.initialize([
      _atom(10),
      _atom(11, descriptor: _text(), text: 'old separator'),
      _atom(12),
    ]);
    final old = List<Message>.of(stock.messages);
    await flush();
    operations.clear();
    expect(
      await model.prepend([
        _atom(6),
        _atom(7, descriptor: _text(), text: 'new separator'),
        _atom(8),
        _atom(9),
      ]),
      4,
    );
    await flush();
    expect(operations.map((op) => op.type), [
      ChatOperationType.update,
      ChatOperationType.insertAll,
    ]);
    expect(operations.first.oldMessage, same(old.first));
    expect(operations.last.index, 0);
    expect(operations.last.animated, isFalse);
    expect(operations.last.messages, hasLength(2));
    expect(stock.messages[3], same(old[1]));
    expect(stock.messages[4], same(old[2]));
    expect(model.ownerOf('atom-8'), same(model.ownerOf('atom-10')));
    expect(model.ownerOf('atom-6'), isNot(same(model.ownerOf('atom-10'))));
  });

  test('重复完整载荷无操作，改正文/描述/header/source明确拒绝', () async {
    await model.initialize([_atom(1, text: 'body', descriptor: _text())]);
    await flush();
    operations.clear();
    await model.append([_atom(1, text: 'body', descriptor: _text())]);
    expect(
      await model.prepend([_atom(1, text: 'body', descriptor: _text())]),
      0,
    );
    for (final changed in [
      _atom(1, text: 'changed', descriptor: _text()),
      _atom(1, text: 'body'),
      _atom(1, text: 'body', descriptor: _text(), sealedAt: 10),
      _atom(
        1,
        text: 'body',
        descriptor: _text(),
        source: const ConversationRecoverySource(
          ConversationRecoveryNotice.retry,
        ),
      ),
    ]) {
      await expectLater(model.append([changed]), throwsStateError);
    }
    await flush();
    expect(operations, isEmpty);
    expect(model.length, 1);
    expect(timelineText(model.items.single), 'body');
  });

  test('整批冲突先于Entry/image/controller修改，seq冲突与逆序也拒绝', () async {
    await model.initialize([_atom(10)]);
    final entry = model.ownerOf('atom-10')!;
    final message = stock.messages.single;
    await flush();
    operations.clear();
    await expectLater(
      model.prepend([
        _atom(8, descriptor: _text(attachments: [_image])),
        _atom(10, text: 'conflict'),
      ]),
      throwsStateError,
    );
    expect(() => images.borrow('image'), throwsStateError);
    await expectLater(
      model.append([
        _atom(11, descriptor: _text(attachments: [_image])),
        _atom(12, id: 'atom-10'),
      ]),
      throwsStateError,
    );
    await expectLater(model.append([_atom(10, id: 'other')]), throwsStateError);
    await expectLater(model.append([_atom(12), _atom(11)]), throwsStateError);
    await expectLater(model.prepend([_atom(11)]), throwsStateError);
    await expectLater(model.append([_atom(9)]), throwsStateError);
    await flush();
    expect(operations, isEmpty);
    expect(entry.memberIds, ['atom-10']);
    expect(stock.messages.single, same(message));
    expect(model.length, 1);
    expect(() => images.borrow('image'), throwsStateError);
  });

  test('多个附件仍同一个正文Message和原子，只有真实sealedAt产生日期', () async {
    final atom = _atom(
      1,
      descriptor: _text(attachments: [_image, _file]),
      text: 'body',
      sealedAt: 123,
    );
    await model.initialize([atom]);
    expect(stock.messages, hasLength(1));
    expect(stock.messages.single, isA<TextMessage>());
    expect(
      (stock.messages.single as TextMessage).text,
      same(timelineText(atom)),
    );
    expect(
      stock.messages.single.createdAt,
      DateTime.fromMillisecondsSinceEpoch(123000, isUtc: true),
    );
    expect(timelineEntryOf(stock.messages.single)!.first, same(atom));
    expect(timelineAttachments(atom), hasLength(2));
    expect(images.borrow('image').attachmentId, 'image');
  });

  test('隐藏原子保留顺序和分页计数，File和恢复回执独立分隔', () async {
    final hidden = ConversationTurnDescriptor(
      outcome: ConversationTurnCompleted(
        const CompletedStudioTurnState(
          startedAt: null,
          completedAt: 1,
          completion: StudioTurnCompletion.normal,
        ),
      ),
    );
    await model.initialize([
      _atom(3),
      _atom(4, descriptor: hidden),
      _atom(5),
      _atom(
        6,
        descriptor: ConversationFileDescriptor(
          ThreadFileItemStateView('file', null, _completedAt),
        ),
      ),
      _atom(7),
      _atom(
        8,
        source: const ConversationRecoverySource(
          ConversationRecoveryNotice.retry,
        ),
      ),
      _atom(
        9,
        source: const ConversationRecoverySource(
          ConversationRecoveryNotice.result,
        ),
      ),
      _atom(10),
    ]);
    expect(model.items.map((atom) => atom.header.appendSeq), [
      3,
      4,
      5,
      6,
      7,
      8,
      9,
      10,
    ]);
    expect(model.length, 8);
    expect(stock.messages, hasLength(6));
    expect(model.ownerOf('atom-3'), same(model.ownerOf('atom-5')));
    expect(model.ownerOf('atom-4')!.kind, TimelineEntryKind.hidden);
    expect(model.ownerOf('atom-6')!.kind, TimelineEntryKind.single);
    expect(model.ownerOf('atom-8'), isNot(same(model.ownerOf('atom-9'))));
    expect(
      await model.prepend([
        _atom(1, descriptor: hidden),
        _atom(2, descriptor: hidden),
      ]),
      2,
    );
    expect(model.items.map((atom) => atom.header.appendSeq), [
      1,
      2,
      3,
      4,
      5,
      6,
      7,
      8,
      9,
      10,
    ]);
    expect(stock.messages, hasLength(6));
  });

  test('仅真实非空同turn活动可合组，图片单原子不互相合并', () async {
    await model.initialize([
      _atom(1, turn: null),
      _atom(2, turn: null),
      _atom(3, turn: ''),
      _atom(4, turn: ''),
      _atom(5, descriptor: _tool(name: 'view_image')),
      _atom(6, descriptor: _tool(name: 'view_image')),
      _atom(7),
      _atom(8, turn: 'other'),
      _atom(
        9,
        descriptor: const ConversationPlanDescriptor(
          interactionId: 'interaction',
          decision: ConversationPlanDecision.approved,
        ),
      ),
      _atom(10),
    ]);
    expect(stock.messages, hasLength(10));
    expect(model.ownerOf('atom-5')!.kind, TimelineEntryKind.images);
    expect(model.ownerOf('atom-5')!.anchorItemId, 'atom-5');
  });

  test('skill_view配对局限当前组，不跨正文修复，旧页可补同组typed调用', () async {
    await model.initialize([
      _atom(4, descriptor: _skill()),
      _atom(5, descriptor: _text(), text: 'separator'),
      _atom(6, descriptor: _tool(name: 'skill_view')),
    ]);
    final first = model.ownerOf('atom-4')!;
    expect(first.pairedToolId('atom-4'), isNull);
    await model.prepend([_atom(3, descriptor: _tool(name: 'skill_view'))]);
    expect(first.anchorItemId, 'atom-4');
    expect(first.pairedToolId('atom-4'), 'atom-3');
    expect(first.visibleMemberIds, ['atom-4']);
    expect(first.toolCount, 0);
    expect(first.skillCount, 1);
    expect(first.length, 2);
    expect(model.ownerOf('atom-6')!.visibleMemberIds, ['atom-6']);
  });

  test('嵌套typed工具/技能载荷值相等，附件与终态变化均非相等', () {
    final original = _atom(
      1,
      descriptor: _tool(name: 'view_image', attachments: [_image]),
    );
    expect(
      timelineAtomsEqual(
        original,
        _atom(
          1,
          descriptor: _tool(
            name: 'view_image',
            attachments: [
              const ThreadAttachmentView(
                id: 'image',
                modality: AttachmentModalityView.image,
                mediaType: 'image/png',
                byteSize: 100,
              ),
            ],
          ),
        ),
      ),
      isTrue,
    );
    expect(
      timelineAtomsEqual(
        original,
        _atom(
          1,
          descriptor: _tool(name: 'view_image', attachments: [_file]),
        ),
      ),
      isFalse,
    );
    expect(
      timelineAtomsEqual(
        _atom(1, descriptor: _skill()),
        _atom(1, descriptor: _skill()),
      ),
      isTrue,
    );
    expect(
      timelineAtomsEqual(
        _atom(1, descriptor: _skill()),
        _atom(1, descriptor: _skill(call: 'different')),
      ),
      isFalse,
    );
    expect(
      timelineAtomsEqual(
        original,
        _atom(
          1,
          descriptor: _tool(
            name: 'view_image',
            state: ConversationToolBackgroundStarted(startedAt: _completedAt),
          ),
        ),
      ),
      isFalse,
    );
  });

  test('空完成批无操作，dispose只释放自有Entry/图片引用', () async {
    await model.initialize([
      _atom(1, descriptor: _text(attachments: [_image])),
    ]);
    await flush();
    operations.clear();
    await model.append([]);
    expect(await model.prepend([]), 0);
    await flush();
    expect(operations, isEmpty);
    model.dispose();
    expect(() => images.borrow('image'), throwsStateError);
    // The stock controller remains owned and usable by the presentation owner.
    await stock.insertAllMessages([
      const Message.custom(id: 'owner', authorId: 'assistant'),
    ]);
    expect(stock.messages, hasLength(2));
    await expectLater(model.append([]), throwsStateError);
  });

  test('独立解码的Turn取消原因与rollover空分支按值幂等', () async {
    ConversationDescriptor cancelled(StudioTurnCancellationCause cause) =>
        ConversationTurnDescriptor(
          outcome: ConversationTurnCancelled(
            CancelledStudioTurnState(
              startedAt: null,
              requestedAt: 1,
              completedAt: 2,
              cause: cause,
            ),
          ),
        );
    ConversationDescriptor budget(StudioTurnRolloverOutcome rollover) =>
        ConversationTurnDescriptor(
          outcome: ConversationTurnBudgetLimited(
            BudgetLimitedStudioTurnState(
              startedAt: 1,
              completedAt: 2,
              limit: const StudioTurnBudgetLimit(
                kind: StudioTurnBudgetLimitKind.toolCall,
                usage: StudioTurnBudgetUsage(
                  modelSteps: 1,
                  toolCalls: 2,
                  waitCalls: 0,
                  elapsedMs: 1000,
                ),
              ),
              rollover: rollover,
            ),
          ),
        );
    await model.initialize([
      _atom(1, descriptor: cancelled(UserRequestedTurnCancellation())),
      _atom(2, descriptor: budget(RolloverNotAttempted())),
      _atom(3, descriptor: budget(RolloverSucceeded())),
    ]);
    await flush();
    operations.clear();
    await model.append([
      _atom(1, descriptor: cancelled(UserRequestedTurnCancellation())),
      _atom(2, descriptor: budget(RolloverNotAttempted())),
      _atom(3, descriptor: budget(RolloverSucceeded())),
    ]);
    await expectLater(
      model.append([_atom(3, descriptor: budget(RolloverNotAttempted()))]),
      throwsStateError,
    );
    await flush();
    expect(operations, isEmpty);
    expect(model.length, 3);
  });
}
