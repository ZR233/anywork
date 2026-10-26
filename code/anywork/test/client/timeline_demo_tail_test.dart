import 'dart:async';
import 'dart:convert';

import 'package:anywork/src/infrastructure/frb/demo/demo_timeline_content.dart';
import 'package:anywork_client/conversation_ports.dart';
import 'package:anywork_client/resources.dart';
import 'package:flutter_test/flutter_test.dart';

/// demo 内容连接遵守同一「一致小页基线 + 有界尾部」契约：首帧只给最新 32 条，之后按
/// 身份交付**可证明连续**的差量，绝不把全部历史当首次增量重投，也不为每次交付重建
/// 全历史版本表（design/26 §26.8）。
void main() {
  ThreadItemView text({
    required String id,
    required int ordinal,
    int revision = 1,
    String body = '正文',
  }) => ThreadItemView(
    id: id,
    threadId: 'thread-main',
    turnId: 'turn-seed',
    ordinal: ordinal,
    revision: revision,
    createdAt: (DateTime.utc(2026).millisecondsSinceEpoch ~/ 1000),
    updatedAt: (DateTime.utc(2026).millisecondsSinceEpoch ~/ 1000),
    state: ThreadTextItemStateView(
      channel: ThreadTextChannel.finalAnswer,
      text: body,
      attachments: const [],
      lifecycle: CompletedThreadContentView(
        (DateTime.utc(2026).millisecondsSinceEpoch ~/ 1000),
      ),
    ),
  );

  /// 一条 canonical 原始记录：`payloads` 是可裁的正文域，`notice` 是不可缩静态原文。
  ThreadItemView raw({
    required String id,
    required int ordinal,
    int revision = 1,
    String notice = '',
    List<RawHistoryPayload> payloads = const [],
  }) => ThreadItemView(
    id: id,
    threadId: 'thread-main',
    turnId: 'turn-seed',
    ordinal: ordinal,
    revision: revision,
    createdAt: (DateTime.utc(2026).millisecondsSinceEpoch ~/ 1000),
    updatedAt: (DateTime.utc(2026).millisecondsSinceEpoch ~/ 1000),
    state: ThreadRawItemStateView(
      payloads,
      notice,
      (DateTime.utc(2026).millisecondsSinceEpoch ~/ 1000),
      origin: ThreadRawItemOrigin.stored,
    ),
  );

  Future<DemoTimelineContent> seeded({int count = 150}) async {
    final transport = DemoTimelineContent();
    transport.seedItems('thread-main', [
      for (var index = 0; index < count; index++)
        text(id: 'seed-$index', ordinal: 1000 + index, body: 'seed 正文 $index'),
    ]);
    return transport;
  }

  test('首帧只交付最新 32 条并给出真实更早边界', () async {
    final transport = await seeded();
    final connection = await transport.openTimeline('thread-main');
    addTearDown(connection.close);
    final tail = _Tail(connection);

    final baseline = await tail.baseline();
    expect(baseline.items.length, 32);
    expect(baseline.items.last.id, 'seed-149');
    expect(baseline.items.first.id, 'seed-118');
    expect(baseline.hasOlder, isTrue);
    expect(baseline.before, isNotNull);
  });

  test('投送窗口满 2 帧后只保留一个 staged 结果，ACK 后按连续性恢复', () async {
    final transport = await seeded(count: 3);
    final connection = await transport.openTimeline('thread-main');
    addTearDown(connection.close);
    final iterator = StreamIterator<StudioTimelineFeedFrame>(connection.events);
    addTearDown(iterator.cancel);
    expect(await iterator.moveNext(), isTrue);
    final first = iterator.current as StudioTimelineFeedData;
    expect(first.deliverySequence, 1);

    // 不 ACK：基线占 1 个未确认额度，第一条变化仍可投送（2 未确认）。
    transport.seedItems('thread-main', [text(id: 'w-1', ordinal: 100)]);
    expect(await iterator.moveNext(), isTrue);
    expect((iterator.current as StudioTimelineFeedData).deliverySequence, 2);

    // 窗口已满：后续变化不排队、不隐藏待发队列，只保留唯一 staged 标记。
    transport.seedItems('thread-main', [text(id: 'w-2', ordinal: 101)]);
    transport.seedItems('thread-main', [text(id: 'w-3', ordinal: 102)]);
    var delivered = false;
    final raced = iterator.moveNext().then((value) => delivered = value);
    await pumpEventQueue();
    expect(delivered, isFalse, reason: '满 2 额度只持一个 staged 结果，不再投送');

    // ACK 释放窗口后恢复：跨过的多次变化无法证明连续，显式重同步。
    await connection.ackThrough(1);
    await connection.ackThrough(2);
    expect(await raced, isTrue);
    final third =
        ((iterator.current as StudioTimelineFeedData).event
                as StudioTimelineFeedUpdate)
            .update;
    expect(third, isA<StudioTimelineResync>(), reason: '跨过的多次变化只能显式重同步');
    await connection.ackThrough(3);
  });

  test('推送流只允许一次订阅：getter 不认领，第二次实际 listen 是 typed Conflict', () async {
    final transport = await seeded(count: 3);
    final connection = await transport.openTimeline('thread-main');
    addTearDown(connection.close);
    // getter 只是视图：多次读取既不认领也不建立第二条流。
    expect(connection.events, isA<Stream<StudioTimelineFeedFrame>>());
    expect(() => connection.events, returnsNormally);
    final tail = _Tail(connection);
    await tail.baseline();
    expect(
      () => connection.events.listen((_) {}),
      throwsA(
        isA<StudioFailure>().having(
          (failure) => failure.code,
          'code',
          StudioFailureCode.conflict,
        ),
      ),
      reason: '首次实际 listen 才认领；第二个实际订阅是 typed Conflict，不另开第二条流',
    );
  });

  test('关闭后调用以 Cancelled 优先', () async {
    final transport = await seeded(count: 3);
    final connection = await transport.openTimeline('thread-main');
    final tail = _Tail(connection);
    await tail.baseline();
    await connection.close();
    for (final call in <Future<Object?> Function()>[
      () => connection.ackThrough(1),
      () async => connection.events,
      () => connection.page(),
      () => connection.readDetail(
        itemId: 'seed-0',
        query: const StudioTimelineDetailQuery(
          field: ThreadTextFieldView(),
          revision: 1,
        ),
      ),
    ]) {
      await expectLater(
        Future<Object?>.sync(call),
        throwsA(
          isA<StudioFailure>().having(
            (failure) => failure.code,
            'code',
            StudioFailureCode.cancelled,
          ),
        ),
      );
    }
  });

  test('一次尾部变化只交付自己的差量，不重投全历史', () async {
    final transport = await seeded();
    final connection = await transport.openTimeline('thread-main');
    addTearDown(connection.close);
    final tail = _Tail(connection);
    final baseline = await tail.baseline();

    final pending = tail.update();
    transport.seedItems('thread-main', [
      text(id: 'live-1', ordinal: 1150, body: '新的一条'),
    ]);
    final patch = (await pending) as StudioTimelinePatch;
    expect(patch.from, baseline.version);
    expect(patch.changes.length, 1, reason: '不把更早的历史重新作为 Adds 交付');
    expect((patch.changes.single as StudioTimelineAdd).item.id, 'live-1');
    expect(patch.changes.whereType<StudioTimelineRemove>(), isEmpty);
  });

  test('跨过的多次变化无法证明连续时显式重同步', () async {
    final transport = await seeded();
    final connection = await transport.openTimeline('thread-main');
    addTearDown(connection.close);
    final tail = _Tail(connection);
    await tail.baseline();

    final pending = tail.update();
    transport.seedItems('thread-main', [
      text(id: 'burst-1', ordinal: 1150),
      text(id: 'burst-2', ordinal: 1151),
    ]);
    final update = (await pending) as StudioTimelineResync;
    expect(update.reason, StudioTimelineResyncReason.lagging);
    expect(update.baseline.items.length, 32, reason: '重同步也只给有界小页');
  });

  test('已交付范围内部出现的新身份显式重同步', () async {
    final transport = await seeded();
    final connection = await transport.openTimeline('thread-main');
    addTearDown(connection.close);
    final tail = _Tail(connection);
    await tail.baseline();

    final pending = tail.update();
    transport.seedItems('thread-main', [text(id: 'insert-mid', ordinal: 1130)]);
    final update = (await pending) as StudioTimelineResync;
    expect(update.reason, StudioTimelineResyncReason.lagging);
    expect(update.baseline.items.length, 32);
  });

  test('更早且从未交付的新身份不插入也不重同步', () async {
    final transport = await seeded();
    final connection = await transport.openTimeline('thread-main');
    addTearDown(connection.close);
    final tail = _Tail(connection);
    final baseline = await tail.baseline();

    final pending = tail.update();
    transport.seedItems('thread-main', [
      text(id: 'insert-old', ordinal: 0, body: '更早的正文'),
    ]);
    final patch = (await pending) as StudioTimelinePatch;
    expect(patch.changes, isEmpty, reason: '更早范围不借尾部提前插入，也不制造分页空洞');
    expect(patch.from, baseline.version);

    // 后续页读取当时的权威值。
    StudioTimelineItem? found;
    var cursor = baseline.before;
    while (cursor != null && found == null) {
      final page = await connection.page(before: cursor, limit: 100);
      for (final item in page.items) {
        if (item.id == 'insert-old') found = item;
      }
      cursor = page.hasOlder ? page.before : null;
    }
    expect(found, isNotNull);
    expect((found!.item.state as ThreadTextItemStateView).text, '更早的正文');
  });

  test('真实删除即使不在有界副本里也自包含交付', () async {
    final transport = await seeded();
    final connection = await transport.openTimeline('thread-main');
    addTearDown(connection.close);
    final tail = _Tail(connection);
    final baseline = await tail.baseline();

    // 34 号早于已交付的 32 条，从未交付给这个连接。
    final pending = tail.update();
    transport.retractItem('thread-main', 'seed-0');
    final patch = (await pending) as StudioTimelinePatch;
    expect(
      patch.changes.single,
      isA<StudioTimelineRemove>().having(
        (remove) => remove.itemId,
        'itemId',
        'seed-0',
      ),
    );
    expect(patch.from, baseline.version);

    // 已交付身份被撤下同样按身份交付删除，并退出本连接副本。
    final delivered = baseline.items.first.id;
    final pendingSecond = tail.update();
    transport.retractItem('thread-main', delivered);
    final second = (await pendingSecond) as StudioTimelinePatch;
    expect((second.changes.single as StudioTimelineRemove).itemId, delivered);
  });

  test('超过 100 条真实连续更新只滑出本地副本，不产生 Remove', () async {
    final transport = await seeded(count: 40);
    final connection = await transport.openTimeline('thread-main');
    addTearDown(connection.close);
    final tail = _Tail(connection);
    final baseline = await tail.baseline();
    expect(baseline.items.length, 32);

    final addedIds = <String>{};
    for (var index = 0; index < 105; index++) {
      final id = 'stream-$index';
      final pending = tail.update();
      transport.seedItems('thread-main', [
        text(id: id, ordinal: 2000 + index, body: '流式正文 $index'),
      ]);
      final patch = (await pending) as StudioTimelinePatch;
      expect(patch.changes.whereType<StudioTimelineRemove>(), isEmpty);
      final adds = patch.changes.whereType<StudioTimelineAdd>().toList();
      expect(adds.map((add) => add.item.id), [id]);
      addedIds.add(id);
    }
    expect(addedIds.length, 105);
    // 副本有界：滑出只影响本地连续性副本，后续变化仍按单条差量交付。
    final pending = tail.update();
    transport.seedItems('thread-main', [
      text(id: 'stream-tail', ordinal: 2200),
    ]);
    final tailPatch = await pending as StudioTimelinePatch;
    expect(
      tailPatch.changes.whereType<StudioTimelineAdd>().map(
        (add) => add.item.id,
      ),
      ['stream-tail'],
    );
    expect(tailPatch.changes.whereType<StudioTimelineRemove>(), isEmpty);
  });

  test('预览按产品预算封顶，完整正文仍由详情读取', () async {
    final transport = DemoTimelineContent();
    final body = 'x' * 40000;
    transport.seedItems('thread-main', [
      text(id: 'big', ordinal: 5000, body: body),
    ]);
    final connection = await transport.openTimeline('thread-main');
    addTearDown(connection.close);
    final tail = _Tail(connection);
    final baseline = await tail.baseline();
    final big = baseline.items.singleWhere((item) => item.id == 'big');
    expect(big.id, 'big');
    final preview = big.item.state as ThreadTextItemStateView;
    expect(preview.text.length, 32 * 1024, reason: '预览只交付 32 KiB');
    expect(big.details.single.totalBytes, 40000);
    expect(big.details.single.previewBytes, 32 * 1024);
    expect(big.omittedBytes, 40000 - 32 * 1024);
    expect(big.item.bodyOmittedUnits, big.omittedBytes);

    final chunk = await connection.readDetail(
      itemId: 'big',
      query: const StudioTimelineDetailQuery(
        field: ThreadTextFieldView(),
        revision: 1,
      ),
    );
    expect(chunk.text, body, reason: '详情返回完整正文');
    expect(chunk.isLast, isTrue);
  });

  test('工具产物与 typed 问答共同计入 32 KiB 预算，完整原文只经详情读取', () async {
    final transport = DemoTimelineContent();
    final artifacts = [
      for (var index = 0; index < 60; index++)
        {'name': 'artifact-$index', 'path': '/tmp/artifact-$index.bin'},
    ];
    final longQuestion = 'Q' * 20000;
    final longAnswer = 'A' * 20000;
    final toolItem = ThreadItemView(
      id: 'tool-big',
      threadId: 'thread-main',
      turnId: 'turn-seed',
      ordinal: 6000,
      revision: 1,
      createdAt: (DateTime.utc(2026).millisecondsSinceEpoch ~/ 1000),
      updatedAt: (DateTime.utc(2026).millisecondsSinceEpoch ~/ 1000),
      executionTerminal: true,
      state: ThreadToolItemStateView(
        invocation: const ThreadToolInvocationView(
          toolCallId: 'call-1',
          name: 'read',
          arguments: '{}',
        ),
        lifecycle: SucceededThreadToolView(
          (DateTime.utc(2026).millisecondsSinceEpoch ~/ 1000),
          ThreadToolOutput(
            result: 'ok',
            attachments: const [],
            outputArtifacts: [
              for (final artifact in artifacts)
                OpaqueArtifactJson(json: jsonEncode(artifact)),
            ],
          ),
        ),
        userInput: ThreadToolUserInputView(
          interactionId: 'interaction-1',
          questions: [
            UserQuestionView(
              id: 'q1',
              header: '确认',
              question: longQuestion,
              isOther: false,
              isSecret: false,
              options: const [
                UserQuestionOptionView(label: 'yes', description: '继续'),
              ],
            ),
          ],
          state: ResolvedThreadToolUserInputView([
            ThreadUserInputAnswerView(questionId: 'q1', answers: [longAnswer]),
          ]),
        ),
      ),
    );
    transport.seedItems('thread-main', [toolItem]);
    final connection = await transport.openTimeline('thread-main');
    addTearDown(connection.close);
    final tail = _Tail(connection);
    final baseline = await tail.baseline();
    final item = baseline.items.singleWhere((entry) => entry.id == 'tool-big');

    // 产物：预览数组为空（不把大载荷塞进 Message.metadata），详情引用保真实总长。
    final artifactsRef = item.detailFor(
      const ThreadToolOutputArtifactsFieldView(),
    )!;
    expect(artifactsRef.previewBytes, 0);
    expect(artifactsRef.totalBytes, greaterThan(1000));
    final state = item.item.state as ThreadToolItemStateView;
    expect(
      (state.lifecycle as SucceededThreadToolView).output.outputArtifacts,
      isEmpty,
      reason: '预览数组可以为空，完整原文只在详情里',
    );

    // typed 问答正文与普通正文共享同一份预算。
    final questionRef = item.detailFor(
      const ThreadToolUserInputFieldView(
        questionIndex: 0,
        part: ThreadUserInputQuestionFieldPartView(),
      ),
    )!;
    final answerRef = item.detailFor(
      const ThreadToolUserInputFieldView(
        questionIndex: 0,
        part: ThreadUserInputAnswerFieldPartView(0),
      ),
    )!;
    expect(questionRef.totalBytes, 20000);
    expect(answerRef.totalBytes, 20000);
    expect(answerRef.previewBytes, lessThan(20000), reason: '后到的答案只能拿到剩余额度');
    expect(
      questionRef.previewBytes + answerRef.previewBytes,
      lessThanOrEqualTo(32 * 1024),
    );
    expect(
      (state.userInput!).questionText(0).length,
      questionRef.previewBytes,
      reason: '承载的预览与账目一致',
    );
    expect(item.omittedBytes, greaterThan(0));
    expect(
      item.omittedBytes,
      item.details.fold<int>(
        0,
        (sum, ref) => sum + (ref.totalBytes - ref.previewBytes),
      ),
      reason: '合成省略量与逐字段账目一致',
    );
    expect(item.item.bodyOmittedUnits, item.omittedBytes);

    // 完整原文按需读取。
    final artifactsChunk = await connection.readDetail(
      itemId: 'tool-big',
      query: const StudioTimelineDetailQuery(
        field: ThreadToolOutputArtifactsFieldView(),
        revision: 1,
      ),
    );
    expect(artifactsChunk.text, contains('artifact-59'));
    expect(artifactsChunk.totalBytes, artifactsRef.totalBytes);
    final answerChunk = await connection.readDetail(
      itemId: 'tool-big',
      query: const StudioTimelineDetailQuery(
        field: ThreadToolUserInputFieldView(
          questionIndex: 0,
          part: ThreadUserInputAnswerFieldPartView(0),
        ),
        revision: 1,
      ),
    );
    expect(answerChunk.text, longAnswer);
    expect(answerChunk.isLast, isTrue);
  });

  test('推理分块额度耗尽不是伪删除：保留身份与详情，只有 canonical 消失才 Remove', () async {
    final transport = DemoTimelineContent();
    final firstChunk = 'x' * (32 * 1024);
    final secondChunk = 'y' * 100;
    ThreadItemView reasoning({
      int revision = 1,
      required List<String> content,
    }) => ThreadItemView(
      id: 'reasoning',
      threadId: 'thread-main',
      turnId: 'turn-seed',
      ordinal: 6001,
      revision: revision,
      createdAt: (DateTime.utc(2026).millisecondsSinceEpoch ~/ 1000),
      updatedAt: (DateTime.utc(2026).millisecondsSinceEpoch ~/ 1000),
      executionTerminal: true,
      state: ThreadThinkingItemStateView(
        summary: const [],
        content: content,
        lifecycle: CompletedThreadContentView(
          (DateTime.utc(2026).millisecondsSinceEpoch ~/ 1000),
        ),
      ),
    );

    transport.seedItems('thread-main', [
      reasoning(content: [firstChunk, secondChunk]),
    ]);
    final connection = await transport.openTimeline('thread-main');
    addTearDown(connection.close);
    final tail = _Tail(connection);
    final baseline = await tail.baseline();
    final item = baseline.items.singleWhere((entry) => entry.id == 'reasoning');
    final state = item.item.state as ThreadThinkingItemStateView;
    final ref0 = item.detailFor(const ThreadThinkingContentFieldView(0))!;
    final ref1 = item.detailFor(const ThreadThinkingContentFieldView(1))!;
    expect(state.content.length, 2, reason: 'chunk 身份不因预算耗尽消失');
    expect(ref0.previewBytes, 32 * 1024);
    expect(ref1.totalBytes, 100);
    expect(ref1.previewBytes, 0, reason: '没额度是空预览，不是字段缺失');
    expect(item.omittedBytes, 100);

    // chunk0 继续增长：只推进元数据，chunk1 仍然存在，绝不产生 Remove。
    final pending = tail.update();
    transport.seedItems('thread-main', [
      reasoning(revision: 2, content: ['$firstChunk more', secondChunk]),
    ]);
    final patch = (await pending) as StudioTimelinePatch;
    expect(patch.changes.whereType<StudioTimelineRemove>(), isEmpty);
    final update = patch.changes.single as StudioTimelineUpdateItem;
    final chunk0Field = update.fields.where(
      (field) => field.field == const ThreadThinkingContentFieldView(0),
    );
    expect(
      chunk0Field.single.change,
      isA<UnchangedThreadFieldChangeView>(),
      reason: '预览封顶但 total 增长仍要推进元数据',
    );
    expect(chunk0Field.single.totalBytes, 32 * 1024 + ' more'.length);
    expect(
      update.fields.where(
        (field) =>
            field.field == const ThreadThinkingContentFieldView(1) &&
            field.change is RemoveThreadFieldChangeView,
      ),
      isEmpty,
      reason: '没额度的 chunk 不是删除',
    );

    // canonical 真的少了一段才发 Remove。
    final pendingRemoval = tail.update();
    transport.seedItems('thread-main', [
      reasoning(revision: 3, content: [firstChunk]),
    ]);
    final removal = await pendingRemoval as StudioTimelinePatch;
    final removedField = removal.changes
        .whereType<StudioTimelineUpdateItem>()
        .single
        .fields
        .singleWhere((field) => field.change is RemoveThreadFieldChangeView);
    expect(removedField.field, const ThreadThinkingContentFieldView(1));
  });

  test('参数化字段详情按绑定 token 逐块读取，跨 scope/版本复用被拒', () async {
    final transport = DemoTimelineContent();
    final bigChunk = 'z' * (3 * 64 * 1024);
    transport.seedItems('thread-main', [
      ThreadItemView(
        id: 'reason-chunks',
        threadId: 'thread-main',
        turnId: 'turn-seed',
        ordinal: 6100,
        revision: 1,
        createdAt: (DateTime.utc(2026).millisecondsSinceEpoch ~/ 1000),
        updatedAt: (DateTime.utc(2026).millisecondsSinceEpoch ~/ 1000),
        executionTerminal: true,
        state: ThreadThinkingItemStateView(
          summary: const [],
          content: [bigChunk, 'tail'],
          lifecycle: CompletedThreadContentView(
            (DateTime.utc(2026).millisecondsSinceEpoch ~/ 1000),
          ),
        ),
      ),
    ]);
    final connection = await transport.openTimeline('thread-main');
    addTearDown(connection.close);
    final tail = _Tail(connection);
    final baseline = await tail.baseline();
    final item = baseline.items.singleWhere(
      (entry) => entry.id == 'reason-chunks',
    );

    // 逐块拼回原文：至少三块、每块都推进 continuation、总字节保真。
    var assembled = '';
    String? cursor;
    var blocks = 0;
    do {
      final chunk = await connection.readDetail(
        itemId: 'reason-chunks',
        query: StudioTimelineDetailQuery(
          field: const ThreadThinkingContentFieldView(0),
          revision: item.revision,
          continuation: cursor,
        ),
      );
      blocks += 1;
      assembled += chunk.text;
      cursor = chunk.continuation;
      expect(chunk.totalBytes, 3 * 64 * 1024);
      expect(chunk.text, isNotEmpty, reason: '非空块必须推进');
    } while (cursor != null);
    expect(blocks, greaterThanOrEqualTo(3));
    expect(assembled, bigChunk);

    // 取一个非末块的 token，验证作用域与版本绑定。
    final firstBlock = await connection.readDetail(
      itemId: 'reason-chunks',
      query: StudioTimelineDetailQuery(
        field: const ThreadThinkingContentFieldView(0),
        revision: item.revision,
        maxBytes: 8,
      ),
    );
    final token = firstBlock.continuation!;
    await expectLater(
      connection.readDetail(
        itemId: 'reason-chunks',
        query: StudioTimelineDetailQuery(
          field: const ThreadThinkingContentFieldView(1),
          revision: item.revision,
          continuation: token,
        ),
      ),
      throwsA(
        isA<StudioFailure>().having(
          (failure) => failure.code,
          'code',
          StudioFailureCode.invalidArgument,
        ),
      ),
      reason: '同一个 token 不能跨字段复用',
    );
    await expectLater(
      connection.readDetail(
        itemId: 'reason-chunks',
        query: StudioTimelineDetailQuery(
          field: const ThreadThinkingContentFieldView(0),
          revision: item.revision + 1,
          continuation: token,
        ),
      ),
      throwsA(
        isA<StudioFailure>().having(
          (failure) => failure.code,
          'code',
          StudioFailureCode.staleRevision,
        ),
      ),
    );

    // 块大小边界：4..262144 全部接受，非法值不 clamp、直接拒绝。
    for (final maxBytes in [65536, 131072, 262144]) {
      final chunk = await connection.readDetail(
        itemId: 'reason-chunks',
        query: StudioTimelineDetailQuery(
          field: const ThreadThinkingContentFieldView(0),
          revision: item.revision,
          maxBytes: maxBytes,
        ),
      );
      expect(chunk.text, isNotEmpty, reason: 'maxBytes=$maxBytes 是合法上界内');
      expect(utf8.encode(chunk.text).length, lessThanOrEqualTo(maxBytes));
    }
    for (final maxBytes in [3, 262145]) {
      await expectLater(
        connection.readDetail(
          itemId: 'reason-chunks',
          query: StudioTimelineDetailQuery(
            field: const ThreadThinkingContentFieldView(0),
            revision: item.revision,
            maxBytes: maxBytes,
          ),
        ),
        throwsA(
          isA<StudioFailure>().having(
            (failure) => failure.code,
            'code',
            StudioFailureCode.invalidArgument,
          ),
        ),
      );
    }
  });

  test('详情 token 绑定 Thread 与 item：跨身份/跨连接复用一律拒绝', () async {
    final transport = DemoTimelineContent();
    final body = 'q' * (200 * 1024);
    ThreadItemView wide(String id, int ordinal) => ThreadItemView(
      id: id,
      threadId: 'thread',
      turnId: 'turn-seed',
      ordinal: ordinal,
      revision: 1,
      createdAt: (DateTime.utc(2026).millisecondsSinceEpoch ~/ 1000),
      updatedAt: (DateTime.utc(2026).millisecondsSinceEpoch ~/ 1000),
      state: ThreadTextItemStateView(
        channel: ThreadTextChannel.finalAnswer,
        text: body,
        attachments: const [],
        lifecycle: CompletedThreadContentView(
          (DateTime.utc(2026).millisecondsSinceEpoch ~/ 1000),
        ),
      ),
    );
    transport.seedItems('thread-main', [
      wide('item-a', 7000),
      wide('item-b', 7001),
    ]);
    transport.seedItems('thread-alt', [wide('item-a', 7100)]);
    final main = await transport.openTimeline('thread-main');
    final alt = await transport.openTimeline('thread-alt');
    addTearDown(main.close);
    addTearDown(alt.close);
    final mainTail = _Tail(main);
    final altTail = _Tail(alt);
    final baseline = await mainTail.baseline();
    final altBaseline = await altTail.baseline();
    final item = baseline.items.singleWhere((entry) => entry.id == 'item-a');
    final firstBlock = await main.readDetail(
      itemId: 'item-a',
      query: StudioTimelineDetailQuery(
        field: const ThreadTextFieldView(),
        revision: item.revision,
        maxBytes: 8,
      ),
    );
    final token = firstBlock.continuation!;

    // 跨 item（同 Thread、同字段）。
    await expectLater(
      main.readDetail(
        itemId: 'item-b',
        query: StudioTimelineDetailQuery(
          field: const ThreadTextFieldView(),
          revision: item.revision,
          continuation: token,
        ),
      ),
      throwsA(
        isA<StudioFailure>().having(
          (failure) => failure.code,
          'code',
          StudioFailureCode.invalidArgument,
        ),
      ),
    );

    // 跨 Thread（同名 item id、同字段、同 revision）。
    final altItem = altBaseline.items.singleWhere(
      (entry) => entry.id == 'item-a',
    );
    expect(altItem.revision, item.revision);
    await expectLater(
      alt.readDetail(
        itemId: 'item-a',
        query: StudioTimelineDetailQuery(
          field: const ThreadTextFieldView(),
          revision: altItem.revision,
          continuation: token,
        ),
      ),
      throwsA(
        isA<StudioFailure>().having(
          (failure) => failure.code,
          'code',
          StudioFailureCode.invalidArgument,
        ),
      ),
    );
  });

  test('落在 UTF-8 续字节上的详情游标被判非法，不泄漏解码异常', () async {
    final transport = DemoTimelineContent();
    transport.seedItems('thread-main', [
      text(id: 'wide', ordinal: 7200, body: '汉' * 40),
    ]);
    final connection = await transport.openTimeline('thread-main');
    addTearDown(connection.close);
    final tail = _Tail(connection);
    final baseline = await tail.baseline();
    final item = baseline.items.singleWhere((entry) => entry.id == 'wide');
    final firstBlock = await connection.readDetail(
      itemId: 'wide',
      query: StudioTimelineDetailQuery(
        field: const ThreadTextFieldView(),
        revision: item.revision,
        maxBytes: 4,
      ),
    );
    expect(
      utf8.encode(firstBlock.text).length,
      3,
      reason: 'maxBytes=4 只够一个 3 字节汉字',
    );
    expect(firstBlock.continuation, isNotNull);

    // 复用服务器签发的 token 形状，只把 offset 改到汉字内部（续字节）：
    // 这不是另一个 codec 实现，而是模拟损坏游标。
    final tampered = _withOffset(firstBlock.continuation!, 1);
    await expectLater(
      connection.readDetail(
        itemId: 'wide',
        query: StudioTimelineDetailQuery(
          field: const ThreadTextFieldView(),
          revision: item.revision,
          continuation: tampered,
        ),
      ),
      throwsA(
        isA<StudioFailure>().having(
          (failure) => failure.code,
          'code',
          StudioFailureCode.invalidArgument,
        ),
      ),
    );
  });

  test('预算重新分配挤掉已交付预览时显式重同步，不伪装连续', () async {
    final transport = DemoTimelineContent();
    final first = 'a' * (16 * 1024);
    final second = 'b' * (16 * 1024);
    ThreadItemView reasoning({
      int revision = 1,
      required List<String> content,
    }) => ThreadItemView(
      id: 'reason-budget',
      threadId: 'thread-main',
      turnId: 'turn-seed',
      ordinal: 6200,
      revision: revision,
      createdAt: (DateTime.utc(2026).millisecondsSinceEpoch ~/ 1000),
      updatedAt: (DateTime.utc(2026).millisecondsSinceEpoch ~/ 1000),
      executionTerminal: true,
      state: ThreadThinkingItemStateView(
        summary: const [],
        content: content,
        lifecycle: CompletedThreadContentView(
          (DateTime.utc(2026).millisecondsSinceEpoch ~/ 1000),
        ),
      ),
    );

    transport.seedItems('thread-main', [
      reasoning(content: [first, second]),
    ]);
    final connection = await transport.openTimeline('thread-main');
    addTearDown(connection.close);
    final tail = _Tail(connection);
    final baseline = await tail.baseline();
    final item = baseline.items.singleWhere(
      (entry) => entry.id == 'reason-budget',
    );
    expect(
      item.detailFor(const ThreadThinkingContentFieldView(1))!.previewBytes,
      16 * 1024,
      reason: '起始两段都有预览额度',
    );

    // 前一段增长吃掉整份额度：后一段预览被挤空而原文没有变短 → 无法证明连续。
    final pending = tail.update();
    transport.seedItems('thread-main', [
      reasoning(revision: 2, content: ['$first${'a' * 2048}', second]),
    ]);
    final update = await pending;
    expect(
      update,
      isA<StudioTimelineResync>(),
      reason: '预算挤短已交付预览时必须显式重同步，不能悄悄清掉已显示正文',
    );
    final rebased = (update as StudioTimelineResync).baseline.items.singleWhere(
      (entry) => entry.id == 'reason-budget',
    );
    expect(
      rebased.detailFor(const ThreadThinkingContentFieldView(1))!.totalBytes,
      16 * 1024,
      reason: '重同步后的新基线仍保真实总长与详情引用',
    );
    expect(
      rebased.detailFor(const ThreadThinkingContentFieldView(1))!.previewBytes,
      lessThan(16 * 1024),
      reason: '新基线如实报告被挤短后的预览额度',
    );
  });

  test('更高 revision 的原文确实变短时原位替换，不当作预算缩减', () async {
    final transport = DemoTimelineContent();
    transport.seedItems('thread-main', [
      text(id: 'shrink', ordinal: 6300, body: 'body-long-value'),
    ]);
    final connection = await transport.openTimeline('thread-main');
    addTearDown(connection.close);
    final tail = _Tail(connection);
    await tail.baseline();

    final pending = tail.update();
    transport.seedItems('thread-main', [
      text(id: 'shrink', ordinal: 6300, revision: 2, body: 'abc'),
    ]);
    final patch = await pending;
    expect(patch, isA<StudioTimelinePatch>(), reason: '权威缩短是合法修订');
    final update =
        (patch as StudioTimelinePatch).changes.single
            as StudioTimelineUpdateItem;
    expect(update.revision, 2);
    expect(update.fields.single.change, isA<ReplaceThreadFieldChangeView>());
    expect(update.fields.single.totalBytes, 3);
  });

  test('短/空字段不耗光共享预算，问答全部可显示且无省略', () async {
    final transport = DemoTimelineContent();
    transport.seedItems('thread-main', [
      ThreadItemView(
        id: 'ask-short',
        threadId: 'thread-main',
        turnId: 'turn-seed',
        ordinal: 6400,
        revision: 1,
        createdAt: (DateTime.utc(2026).millisecondsSinceEpoch ~/ 1000),
        updatedAt: (DateTime.utc(2026).millisecondsSinceEpoch ~/ 1000),
        executionTerminal: true,
        state: ThreadToolItemStateView(
          invocation: const ThreadToolInvocationView(
            toolCallId: 'call-short',
            name: 'ask',
            arguments: '',
          ),
          lifecycle: SucceededThreadToolView(
            (DateTime.utc(2026).millisecondsSinceEpoch ~/ 1000),
            ThreadToolOutput(result: '', attachments: [], outputArtifacts: []),
          ),
          userInput: ThreadToolUserInputView(
            interactionId: 'interaction-short',
            questions: [
              UserQuestionView(
                id: 'q1',
                header: '',
                question: 'Hi',
                isOther: false,
                isSecret: false,
                options: [
                  UserQuestionOptionView(label: 'OK', description: 'go'),
                ],
              ),
            ],
            state: ResolvedThreadToolUserInputView([
              ThreadUserInputAnswerView(questionId: 'q1', answers: ['Yes']),
            ]),
          ),
        ),
      ),
    ]);
    final connection = await transport.openTimeline('thread-main');
    addTearDown(connection.close);
    final tail = _Tail(connection);
    final baseline = await tail.baseline();
    final item = baseline.items.singleWhere((entry) => entry.id == 'ask-short');
    final input = (item.item.state as ThreadToolItemStateView).userInput!;
    expect(input.questionText(0), 'Hi');
    expect(input.optionLabel(0, 0), 'OK');
    expect(input.answerText(0, 0), 'Yes');
    expect(item.omittedBytes, 0, reason: '短/空字段不得提前扣满额度');
    for (final ref in item.details) {
      expect(ref.previewBytes, ref.totalBytes);
    }
  });

  test('计划确认的权威决定标记不被正文预算截掉', () async {
    final transport = DemoTimelineContent();
    // 问题正文先占一部分额度，剩余额度仍要能交付非空反馈。
    final longPlan = '# 计划标题\n\n${'正文' * 4000}';
    final feedback = '反馈' * 8000;
    ThreadItemView plan({required String decision}) => ThreadItemView(
      id: 'plan-ask',
      threadId: 'thread-main',
      turnId: 'turn-seed',
      ordinal: 6500,
      revision: 1,
      createdAt: (DateTime.utc(2026).millisecondsSinceEpoch ~/ 1000),
      updatedAt: (DateTime.utc(2026).millisecondsSinceEpoch ~/ 1000),
      executionTerminal: true,
      state: ThreadToolItemStateView(
        invocation: const ThreadToolInvocationView(
          toolCallId: 'call-plan',
          name: 'ask',
          arguments: '{}',
        ),
        lifecycle: SucceededThreadToolView(
          (DateTime.utc(2026).millisecondsSinceEpoch ~/ 1000),
          ThreadToolOutput(result: 'ok', attachments: [], outputArtifacts: []),
        ),
        userInput: ThreadToolUserInputView(
          interactionId: 'interaction-plan',
          questions: [
            UserQuestionView(
              id: agentSessionPlanConfirmationQuestionId,
              header: '计划',
              question: longPlan,
              isOther: false,
              isSecret: false,
              options: const [],
            ),
          ],
          state: ResolvedThreadToolUserInputView([
            ThreadUserInputAnswerView(
              questionId: agentSessionPlanConfirmationQuestionId,
              answers: [decision, feedback],
            ),
          ]),
        ),
      ),
    );

    for (final entry in {
      agentSessionPlanApproveAnswer: PlanConfirmationDecisionView.approved,
      agentSessionPlanReviseAnswer:
          PlanConfirmationDecisionView.revisionRequested,
    }.entries) {
      transport.seedItems('thread-main', [plan(decision: entry.key)]);
      final connection = await transport.openTimeline('thread-main');
      final tail = _Tail(connection);
      final baseline = await tail.baseline();
      final item = baseline.items.singleWhere((e) => e.id == 'plan-ask');
      final input = (item.item.state as ThreadToolItemStateView).userInput!;
      expect(
        input.planReceipt!.decision,
        entry.value,
        reason: '权威决定标记不能被正文预算挤成 generic resolved',
      );
      // 权威决定与反馈都在公开 typed 字段里：标题来自问题正文，反馈来自答案段。
      expect(input.planReceipt!.title, '计划标题');
      if (entry.value == PlanConfirmationDecisionView.revisionRequested) {
        expect(
          input.planReceipt!.feedback,
          isNotEmpty,
          reason: '请求修改必须带回权威反馈正文',
        );
      } else {
        expect(input.planReceipt!.feedback, isEmpty, reason: '批准不产生反馈正文');
      }
      expect(item.omittedBytes, greaterThan(0));
      // 反馈正文仍按预算截断在 typed 字段里（不是藏进 meta），完整原文可读。
      final answerText = input.answerText(0, 1);
      expect(answerText.length, lessThan(feedback.length));
      final chunk = await connection.readDetail(
        itemId: 'plan-ask',
        query: const StudioTimelineDetailQuery(
          field: ThreadToolUserInputFieldView(
            questionIndex: 0,
            part: ThreadUserInputAnswerFieldPartView(1),
          ),
          revision: 1,
        ),
      );
      expect(chunk.text, feedback);
      await connection.close();
    }
  });

  test('页查询按游标读取更早内容并可继续详情', () async {
    final transport = await seeded();
    final connection = await transport.openTimeline('thread-main');
    addTearDown(connection.close);
    final tail = _Tail(connection);
    final baseline = await tail.baseline();

    final page = await connection.page(before: baseline.before, limit: 32);
    expect(page.items.length, 32);
    expect(page.items.last.id, 'seed-117');
    expect(page.hasOlder, isTrue);

    final target = page.items.last;
    final chunk = await connection.readDetail(
      itemId: target.id,
      query: StudioTimelineDetailQuery(
        field: const ThreadTextFieldView(),
        revision: target.revision,
      ),
    );
    expect(chunk.itemId, target.id);
    expect(chunk.text, isNotEmpty);
    expect(chunk.isLast, isTrue, reason: '小正文单块读完');
  });

  test('空字段声明不是免费结构：不可缩结构超单条上限时 typed Overloaded', () async {
    final transport = DemoTimelineContent();
    // 一万多个空分块：正文全是空串，但每个分块都有自己的身份、字段声明与容器成本。
    transport.seedItems('thread-main', [
      ThreadItemView(
        id: 'reason-empty',
        threadId: 'thread-main',
        turnId: 'turn-seed',
        ordinal: 8000,
        revision: 1,
        createdAt: (DateTime.utc(2026).millisecondsSinceEpoch ~/ 1000),
        updatedAt: (DateTime.utc(2026).millisecondsSinceEpoch ~/ 1000),
        executionTerminal: true,
        state: ThreadThinkingItemStateView(
          summary: const [],
          content: List.filled(12000, ''),
          lifecycle: CompletedThreadContentView(
            (DateTime.utc(2026).millisecondsSinceEpoch ~/ 1000),
          ),
        ),
      ),
    ]);
    final connection = await transport.openTimeline('thread-main');
    addTearDown(connection.close);
    final tail = _Tail(connection);
    await expectLater(
      tail.baseline(),
      throwsA(
        isA<StudioFailure>()
            .having(
              (failure) => failure.code,
              'code',
              StudioFailureCode.overloaded,
            )
            .having((failure) => failure.retryable, 'retryable', isFalse),
      ),
      reason: '空正文的字段声明仍有结构性成本，不能被当成免费内容',
    );
    // 首帧失败即封本连接准入：再次订阅是 typed Cancelled（关闭优先于重复
    // 消费者的 Conflict），失败不把同一连接变成“再拿一页”的入口。
    expect(
      () => connection.events.listen((_) {}),
      throwsA(
        isA<StudioFailure>().having(
          (failure) => failure.code,
          'code',
          StudioFailureCode.cancelled,
        ),
      ),
    );
    // 源仍超限：旧 feed 的失败不被当成“源已修好”，恢复只能新 open 取新基线，
    // 新连接重新计量同一事实并再次 typed Overloaded。
    final reopened = await transport.openTimeline('thread-main');
    addTearDown(reopened.close);
    await expectLater(
      _Tail(reopened).baseline(),
      throwsA(
        isA<StudioFailure>()
            .having(
              (failure) => failure.code,
              'code',
              StudioFailureCode.overloaded,
            )
            .having((failure) => failure.retryable, 'retryable', isFalse),
      ),
      reason: '新 open 的新 baseline 仍按同一预算计量，不因旧 feed 失败而放宽',
    );
  });

  test('Raw.notice 是不可缩静态结构：超限 typed Overloaded，不被裁空', () async {
    final transport = DemoTimelineContent();
    final notice = 'n' * (300 * 1024);
    transport.seedItems('thread-main', [
      raw(
        id: 'raw-huge',
        ordinal: 8010,
        notice: notice,
        payloads: const [RawHistoryPayload('json', 1, '{"a":1}')],
      ),
    ]);
    final connection = await transport.openTimeline('thread-main');
    addTearDown(connection.close);
    final tail = _Tail(connection);
    await expectLater(
      tail.baseline(),
      throwsA(
        isA<StudioFailure>()
            .having(
              (failure) => failure.code,
              'code',
              StudioFailureCode.overloaded,
            )
            .having((failure) => failure.retryable, 'retryable', isFalse),
      ),
      reason: 'static 原文超结构上限时明确报告资源限制，不回退完整载荷也不伪装 EOF',
    );
    // 页查询同样 typed 失败，而不是静默丢掉该条或返回空页：首帧失败已封旧
    // feed 准入，因此该风险用独立未终止的连接验证。
    final pageConnection = await transport.openTimeline('thread-main');
    addTearDown(pageConnection.close);
    await expectLater(
      pageConnection.page(limit: 32),
      throwsA(
        isA<StudioFailure>().having(
          (failure) => failure.code,
          'code',
          StudioFailureCode.overloaded,
        ),
      ),
    );
  });

  test('结构挤占正文额度：预览变短但保真实总长、详情入口与静态原文', () async {
    final transport = DemoTimelineContent();
    final notice = 'n' * (245 * 1024);
    final body = 'b' * 40000;
    transport.seedItems('thread-main', [
      raw(
        id: 'raw-budget',
        ordinal: 8020,
        notice: notice,
        payloads: [RawHistoryPayload('json', 1, body)],
      ),
    ]);
    final connection = await transport.openTimeline('thread-main');
    addTearDown(connection.close);
    final tail = _Tail(connection);
    final baseline = await tail.baseline();
    final item = baseline.items.singleWhere(
      (entry) => entry.id == 'raw-budget',
    );
    expect(
      (item.item.state as ThreadRawItemStateView).notice,
      notice,
      reason: 'notice 原样交付，不裁空也不挪成动态字段',
    );
    final ref = item.detailFor(const ThreadRawPayloadFieldView(0))!;
    expect(ref.totalBytes, 40000, reason: '真实总长不受结构占用影响');
    expect(
      ref.previewBytes,
      lessThan(32 * 1024),
      reason: '静态结构先占额度，正文预览取交集后必然小于产品正文上限',
    );
    expect(ref.previewBytes, greaterThan(0));
    expect(item.omittedBytes, 40000 - ref.previewBytes);
    expect(item.item.bodyOmittedUnits, item.omittedBytes);

    final chunk = await connection.readDetail(
      itemId: 'raw-budget',
      query: StudioTimelineDetailQuery(
        field: const ThreadRawPayloadFieldView(0),
        revision: item.revision,
      ),
    );
    expect(chunk.text, body, reason: '完整正文仍只经详情读取');
    expect(chunk.isLast, isTrue);
  });

  test('页预算 2 MiB 提前截页：游标连续覆盖更早条目，不伪造 EOF', () async {
    final transport = DemoTimelineContent();
    final notice = 'n' * (200 * 1024);
    const total = 60;
    transport.seedItems('thread-main', [
      for (var index = 0; index < total; index++)
        raw(id: 'big-$index', ordinal: 1000 + index, notice: notice),
    ]);
    final connection = await transport.openTimeline('thread-main');
    addTearDown(connection.close);
    final tail = _Tail(connection);
    final baseline = await tail.baseline();
    expect(
      baseline.items.length,
      lessThan(32),
      reason: '每条静态结构约 200 KiB：按字节预算提前截页，而不是固定条数',
    );
    expect(baseline.hasOlder, isTrue);
    expect(baseline.before, isNotNull);
    expect(
      baseline.items.every(
        (item) =>
            item.id.startsWith('big-') &&
            (item.item.state as ThreadRawItemStateView).notice.length ==
                notice.length,
      ),
      isTrue,
      reason: '截页不裁剪条目的不可缩结构',
    );

    final baselineIds = baseline.items.map((item) => item.id).toSet();
    // demo 的 bootstrap 已有 4 条更早的基础条目：它们是最后一页的真实剩余内容。
    final allIds = {for (var index = 0; index < total; index++) 'big-$index'};
    final seen = <String>[];
    var cursor = baseline.before;
    var oldestSoFar = baseline.items.first.item.ordinal;
    var pages = 1;
    while (cursor != null) {
      final page = await connection.page(before: cursor, limit: 100);
      expect(page.items, isNotEmpty, reason: 'hasOlder 为真时下一页不能是空页');
      final ordinals = page.items.map((item) => item.item.ordinal).toList();
      expect(
        ordinals,
        orderedEquals([...ordinals]..sort()),
        reason: '页内按 canonical 顺序升序',
      );
      expect(
        ordinals.last,
        lessThan(oldestSoFar),
        reason: '每页续读的都严格早于上一页交付的最早条目',
      );
      oldestSoFar = ordinals.first;
      seen.addAll(page.items.map((item) => item.id));
      cursor = page.hasOlder ? page.before : null;
      pages += 1;
      if (pages > 40) fail('分页未收敛');
    }
    expect(seen.length, seen.toSet().length, reason: '不重复交付同一条目');
    expect(
      seen.toSet().intersection(allIds),
      allIds.difference(baselineIds),
      reason: '被预算截掉的条目留在下一页，不跳过也不丢',
    );
    expect(seen, contains('big-0'), reason: '更早页确实读到最早的受测条目');
  });

  test('连续性副本按 8 MiB 而非仅 100 条淘汰：被淘汰身份显式重同步', () async {
    final transport = DemoTimelineContent();
    // 每条的结构与正文合计接近单条上限：8 MiB 副本只能容纳约 32 条，远少于 100 条。
    final notice = 'n' * (240 * 1024);
    final body = 'b' * 40000;
    final ordinals = <String, int>{};
    final seeds = <ThreadItemView>[];
    for (var index = 0; index < 8; index++) {
      final id = 'seed-big-$index';
      ordinals[id] = 1000 + index;
      seeds.add(
        raw(
          id: id,
          ordinal: 1000 + index,
          notice: notice,
          payloads: [RawHistoryPayload('json', 1, body)],
        ),
      );
    }
    transport.seedItems('thread-main', seeds);
    final connection = await transport.openTimeline('thread-main');
    addTearDown(connection.close);
    final tail = _Tail(connection);
    final baseline = await tail.baseline();
    expect(baseline.items.length, lessThanOrEqualTo(8));
    expect(baseline.items.first.id, 'seed-big-0', reason: '首帧是这 8 条的小页');

    for (var index = 0; index < 34; index++) {
      final id = 'stream-big-$index';
      ordinals[id] = 2000 + index;
      final pending = tail.update();
      transport.seedItems('thread-main', [
        raw(
          id: id,
          ordinal: 2000 + index,
          notice: notice,
          payloads: [RawHistoryPayload('json', 1, body)],
        ),
      ]);
      final patch = (await pending) as StudioTimelinePatch;
      expect(patch.changes.whereType<StudioTimelineRemove>(), isEmpty);
    }
    expect(
      baseline.items.length + 34,
      lessThan(100),
      reason: '已交付身份总数远少于 100 条：淘汰只能来自字节预算',
    );

    // 首帧里最早的一条此刻已被字节预算淘汰：它的后续事实变化无法用差量证明。
    final evicted = baseline.items.first.id;
    final pending = tail.update();
    transport.seedItems('thread-main', [
      raw(
        id: evicted,
        ordinal: ordinals[evicted]!,
        revision: 2,
        notice: notice,
        payloads: [RawHistoryPayload('json', 1, '$body-2')],
      ),
    ]);
    final update = await pending;
    expect(
      update,
      isA<StudioTimelineResync>(),
      reason: '被字节预算淘汰的身份不能伪装成单条连续差量',
    );
    final resync = (update as StudioTimelineResync).baseline;
    expect(resync.items.length, lessThan(42));
    expect(resync.hasOlder, isTrue);
    expect(
      resync.items.any((item) => item.id == evicted),
      isFalse,
      reason: '重同步基线仍只给最新小页',
    );
  });

  test('推送预算错误终止旧 feed：源修好后只能由新 baseline 恢复', () async {
    final transport = DemoTimelineContent();
    transport.seedItems('thread-main', [
      text(id: 'small-1', ordinal: 100),
      text(id: 'small-2', ordinal: 101),
    ]);
    final connection = await transport.openTimeline('thread-main');
    addTearDown(connection.close);
    final iterator = StreamIterator<StudioTimelineFeedFrame>(connection.events);
    addTearDown(iterator.cancel);
    expect(await iterator.moveNext(), isTrue);
    final first = iterator.current as StudioTimelineFeedData;
    expect(first.deliverySequence, 1);
    final baseline = (first.event as StudioTimelineFeedBaseline).baseline;
    await connection.ackThrough(1);

    // 一条无法计量的巨大条目：投送失败是 typed Failure，不被吞成空差量或 EOF。
    transport.seedItems('thread-main', [
      raw(id: 'huge', ordinal: 200, notice: 'n' * (300 * 1024)),
    ]);
    expect(await iterator.moveNext(), isTrue);
    final terminal = iterator.current as StudioTimelineFeedFailure;
    expect(terminal.error.code, StudioFailureCode.overloaded);
    expect(terminal.error.retryable, isFalse);

    // 旧 feed 已终态：即使源被修好，同一连接也不再交付 Data——失败不被当成
    // “可继续的水位”，也不静默恢复成正常流。
    transport.retractItem('thread-main', 'huge');
    await pumpEventQueue();
    expect(
      await iterator.moveNext(),
      isFalse,
      reason: '源恢复不能复活旧 feed：终态之后没有任何 Data 帧',
    );
    await expectLater(
      Future<void>.sync(() => connection.ackThrough(1)),
      throwsA(
        isA<StudioFailure>().having(
          (failure) => failure.code,
          'code',
          StudioFailureCode.cancelled,
        ),
      ),
      reason: '终态后准入已封，ACK 同样是 typed Cancelled',
    );

    // 恢复只能新 open 取新 baseline：版本按 canonical 真实推进（新增 + 撤回），
    // 超限条目不再进入新事实。
    final recovered = await transport.openTimeline('thread-main');
    addTearDown(recovered.close);
    final recoveredBaseline = await _Tail(recovered).baseline();
    expect(
      recoveredBaseline.version,
      greaterThan(baseline.version),
      reason: '两次 canonical 变化都真实推进新连接的基线版本',
    );
    final ids = recoveredBaseline.items.map((item) => item.id).toList();
    expect(ids, containsAllInOrder(['small-1', 'small-2']));
    expect(ids, isNot(contains('huge')));
  });

  test('详情默认块大小是 64 KiB：首块恰好 65536 字节并可继续读到末尾', () async {
    final transport = DemoTimelineContent();
    final body = 'a' * 70000;
    transport.seedItems('thread-main', [
      text(id: 'detail-default', ordinal: 8030, body: body),
    ]);
    final connection = await transport.openTimeline('thread-main');
    addTearDown(connection.close);
    final tail = _Tail(connection);
    final baseline = await tail.baseline();
    final item = baseline.items.singleWhere(
      (entry) => entry.id == 'detail-default',
    );

    final first = await connection.readDetail(
      itemId: 'detail-default',
      query: StudioTimelineDetailQuery(
        field: const ThreadTextFieldView(),
        revision: item.revision,
      ),
    );
    expect(utf8.encode(first.text).length, 65536, reason: '默认块大小就是 64 KiB');
    expect(first.isLast, isFalse);
    expect(first.continuation, isNotNull);

    final second = await connection.readDetail(
      itemId: 'detail-default',
      query: StudioTimelineDetailQuery(
        field: const ThreadTextFieldView(),
        revision: item.revision,
        continuation: first.continuation,
      ),
    );
    expect(utf8.encode(second.text).length, 70000 - 65536);
    expect(second.isLast, isTrue);
    expect(first.text + second.text, body);
  });

  test('产物预览数组不随原始元素数计费：多元素合法 JSON 仍给有界预览与完整详情', () async {
    final transport = DemoTimelineContent();
    // 两万个完全合法的小 JSON 元素：动态原文只经字段与详情交付，预览数组恒为空。
    final artifacts = [
      for (var index = 0; index < 20000; index++) {'n': index},
    ];
    transport.seedItems('thread-main', [
      ThreadItemView(
        id: 'tool-artifacts',
        threadId: 'thread-main',
        turnId: 'turn-seed',
        ordinal: 8040,
        revision: 1,
        createdAt: (DateTime.utc(2026).millisecondsSinceEpoch ~/ 1000),
        updatedAt: (DateTime.utc(2026).millisecondsSinceEpoch ~/ 1000),
        executionTerminal: true,
        state: ThreadToolItemStateView(
          invocation: const ThreadToolInvocationView(
            toolCallId: 'call-artifacts',
            name: 'artifact_tool',
            arguments: '{"a":1}',
          ),
          lifecycle: SucceededThreadToolView(
            (DateTime.utc(2026).millisecondsSinceEpoch ~/ 1000),
            ThreadToolOutput(
              result: 'ok',
              attachments: const [],
              outputArtifacts: [
                for (final artifact in artifacts)
                  OpaqueArtifactJson(json: jsonEncode(artifact)),
              ],
            ),
          ),
        ),
      ),
    ]);
    final connection = await transport.openTimeline('thread-main');
    addTearDown(connection.close);
    final tail = _Tail(connection);

    final baseline = await tail.baseline();
    final item = baseline.items.singleWhere(
      (entry) => entry.id == 'tool-artifacts',
    );
    final output =
        ((item.item.state as ThreadToolItemStateView).lifecycle
                as SucceededThreadToolView)
            .output;
    expect(output.outputArtifacts, isEmpty, reason: '预览数组为空，不是没有产物');
    final ref = item.detailFor(const ThreadToolOutputArtifactsFieldView())!;
    expect(ref.previewBytes, 0);
    expect(
      ref.totalBytes,
      greaterThan(200000),
      reason: '动态原文的真实总长仍然可读，不受结构计量影响',
    );
    expect(item.omittedBytes, greaterThanOrEqualTo(ref.totalBytes));

    // 页查询同样只给有界预览，不因为原始元素多就失败。
    final page = await connection.page(limit: 32);
    final paged = page.items.singleWhere(
      (entry) => entry.id == 'tool-artifacts',
    );
    expect(
      paged.detailFor(const ThreadToolOutputArtifactsFieldView())!.totalBytes,
      ref.totalBytes,
    );

    // 逐块详情能完整读回原始 JSON，元素一个不少、顺序不变。
    final assembled = StringBuffer();
    String? cursor;
    var blocks = 0;
    do {
      final chunk = await connection.readDetail(
        itemId: 'tool-artifacts',
        query: StudioTimelineDetailQuery(
          field: const ThreadToolOutputArtifactsFieldView(),
          revision: item.revision,
          continuation: cursor,
        ),
      );
      blocks += 1;
      assembled.write(chunk.text);
      cursor = chunk.continuation;
    } while (cursor != null);
    expect(blocks, greaterThan(1), reason: '大载荷按块读取');
    expect(jsonDecode(assembled.toString()), artifacts);
  });

  test(
    'Turn 失败/回滚的任意 String 元数据计入不可缩结构：initial/page 均 typed Overloaded',
    () async {
      // 新 schema 将 category/providerKind 封闭为枚举；仍可任意增长的 code
      // 和 message 各 150 KiB。漏计任一 String 域都会错误地落回单条上限内。
      final part = 'x' * (150 * 1024);
      // 两种情况都让 reason 保持很短，只有另外的任意 String 原文超限。
      final states = <String, TurnState>{
        'failure-metadata': FailedTurn(
          startedAt: 1,
          completedAt: 2,
          failure: TurnFailure(
            category: TurnFailureCategory.provider,
            providerKind: ProviderFailureKind.protocol,
            code: part,
            httpStatus: 500,
            message: part,
            retry: const RetryDisposition.retryable(retryAfterMs: 1000),
          ),
        ),
        'rollover-error': BudgetLimitedTurn(
          startedAt: 1,
          completedAt: 2,
          limit: const BudgetLimitSnapshot(
            kind: BudgetLimitKind.modelStep,
            usage: BudgetUsage(
              modelSteps: 1,
              toolCalls: 0,
              waitCalls: 0,
              elapsedMs: 1,
            ),
          ),
          rollover: TurnRolloverFailed(error: 'y' * (300 * 1024)),
        ),
      };
      for (final entry in states.entries) {
        final transport = DemoTimelineContent();
        transport.seedItems('thread-main', [
          ThreadItemView(
            id: 'turn-${entry.key}',
            threadId: 'thread-main',
            turnId: 'turn-seed',
            ordinal: 9000,
            revision: 1,
            createdAt: (DateTime.utc(2026).millisecondsSinceEpoch ~/ 1000),
            updatedAt: (DateTime.utc(2026).millisecondsSinceEpoch ~/ 1000),
            state: ThreadTurnItemStateView(entry.value),
          ),
        ]);
        final connection = await transport.openTimeline('thread-main');
        final tail = _Tail(connection);
        final overloaded = throwsA(
          isA<StudioFailure>()
              .having(
                (failure) => failure.code,
                'code',
                StudioFailureCode.overloaded,
              )
              .having((failure) => failure.retryable, 'retryable', isFalse),
        );
        await expectLater(
          tail.baseline(),
          overloaded,
          reason: '${entry.key} 的任意 String 原文不能被固定壳豁免',
        );
        // 首帧失败已封旧 feed 准入：页查询的同一风险用独立未终止连接验证。
        final pageConnection = await transport.openTimeline('thread-main');
        await expectLater(pageConnection.page(limit: 32), overloaded);
        await pageConnection.close();
        await connection.close();
      }
    },
  );

  test('未匹配问题 id 的答案值不属于任何内容域：计入不可缩结构而不是免费随预览交付', () async {
    ThreadItemView ask({required String orphanAnswer}) => ThreadItemView(
      id: 'ask-orphan',
      threadId: 'thread-main',
      turnId: 'turn-seed',
      ordinal: 9100,
      revision: 1,
      createdAt: (DateTime.utc(2026).millisecondsSinceEpoch ~/ 1000),
      updatedAt: (DateTime.utc(2026).millisecondsSinceEpoch ~/ 1000),
      executionTerminal: true,
      state: ThreadToolItemStateView(
        invocation: const ThreadToolInvocationView(
          toolCallId: 'call-orphan',
          name: 'ask',
          arguments: '{}',
        ),
        lifecycle: SucceededThreadToolView(
          (DateTime.utc(2026).millisecondsSinceEpoch ~/ 1000),
          ThreadToolOutput(result: 'ok', attachments: [], outputArtifacts: []),
        ),
        userInput: ThreadToolUserInputView(
          interactionId: 'interaction-orphan',
          questions: [
            UserQuestionView(
              id: 'q1',
              header: '确认',
              question: '继续？',
              isOther: false,
              isSecret: false,
              options: [UserQuestionOptionView(label: 'OK', description: '')],
            ),
          ],
          state: ResolvedThreadToolUserInputView([
            ThreadUserInputAnswerView(questionId: 'q1', answers: ['yes']),
            // 找不到对应问题的答案：既没有内容字段，也无法按字段读详情。
            ThreadUserInputAnswerView(
              questionId: 'orphan-q',
              answers: [orphanAnswer],
            ),
          ]),
        ),
      ),
    );

    // 短值：原样保留在 typed 结构里，可寻址字段照常交付、不受影响。
    final shortTransport = DemoTimelineContent();
    shortTransport.seedItems('thread-main', [ask(orphanAnswer: 'ghost')]);
    final shortConnection = await shortTransport.openTimeline('thread-main');
    addTearDown(shortConnection.close);
    final shortTail = _Tail(shortConnection);
    final baseline = await shortTail.baseline();
    final item = baseline.items.singleWhere(
      (entry) => entry.id == 'ask-orphan',
    );
    final input = (item.item.state as ThreadToolItemStateView).userInput!;
    expect(input.answerText(0, 0), 'yes');
    expect(
      input.answers.last.questionId,
      'orphan-q',
      reason: '未知问题的答案身份不被删除或篡改',
    );
    expect(input.answers.last.answers, ['ghost'], reason: '短值原样保留');
    // 可寻址字段 = header + 问题 + 选项 label/description + 有效答案 = 5。
    expect(
      item.details
          .where((ref) => ref.field is ThreadToolUserInputFieldView)
          .length,
      5,
      reason: '只有 header/问题/有效答案是可寻址字段，未知答案不造伪字段',
    );
    expect(item.omittedBytes, 0);

    // 巨值：没有字段与详情入口可供按需读取，只能按实际字节计入不可缩结构。
    final longTransport = DemoTimelineContent();
    longTransport.seedItems('thread-main', [
      ask(orphanAnswer: 'g' * (300 * 1024)),
    ]);
    final longConnection = await longTransport.openTimeline('thread-main');
    addTearDown(longConnection.close);
    final longTail = _Tail(longConnection);
    final overloaded = throwsA(
      isA<StudioFailure>()
          .having(
            (failure) => failure.code,
            'code',
            StudioFailureCode.overloaded,
          )
          .having((failure) => failure.retryable, 'retryable', isFalse),
    );
    await expectLater(
      longTail.baseline(),
      overloaded,
      reason: '任意 String 不能因为找不到问题就被固定壳豁免',
    );
    // 首帧失败已封旧 feed 准入：页查询的同一风险用独立未终止连接验证。
    final longPageConnection = await longTransport.openTimeline('thread-main');
    addTearDown(longPageConnection.close);
    await expectLater(longPageConnection.page(limit: 32), overloaded);
  });
}

/// 把服务器签发的详情 token 的字节偏移改掉（模拟损坏游标；不另实现一套 codec）。
String _withOffset(String token, int offset) {
  final payload =
      jsonDecode(utf8.decode(base64Url.decode(token))) as Map<String, Object?>;
  payload['o'] = offset;
  return base64Url.encode(utf8.encode(jsonEncode(payload)));
}

/// 逐帧读取 demo 推送的测试 helper：每帧读出后立即按生产口径 ACK，保持两额度窗口
/// 可用；typed Failure 帧按原错误抛出，与旧 pump 语义一致。
final class _Tail {
  _Tail(this.connection)
    : _iterator = StreamIterator<StudioTimelineFeedFrame>(connection.events);

  final StudioTimelineConnection connection;
  final StreamIterator<StudioTimelineFeedFrame> _iterator;

  Future<StudioTimelineFeedData> _data() async {
    if (!await _iterator.moveNext()) {
      throw StateError('The demo tail feed ended');
    }
    final frame = _iterator.current;
    if (frame is StudioTimelineFeedFailure) {
      throw frame.error;
    }
    if (frame is! StudioTimelineFeedData) {
      throw StateError('Unexpected feed frame: $frame');
    }
    await connection.ackThrough(frame.deliverySequence);
    return frame;
  }

  Future<StudioTimelineBaseline> baseline() async {
    final frame = await _data();
    final event = frame.event;
    if (event is! StudioTimelineFeedBaseline) {
      throw StateError('Unexpected feed event: $event');
    }
    return event.baseline;
  }

  Future<StudioTimelineUpdate> update() async {
    final frame = await _data();
    final event = frame.event;
    if (event is! StudioTimelineFeedUpdate) {
      throw StateError('Unexpected feed event: $event');
    }
    return event.update;
  }
}
