import 'dart:async';
import 'dart:convert';

import 'package:anywork_client/studio_client.dart';
import 'package:flutter_test/flutter_test.dart';

import 'recording_demo_transport.dart';
import 'pump_client_future.dart';

ConversationItem conversationFixture({
  String id = 'item',
  String threadId = 'thread-main',
  String turnId = 'turn',
  int ordinal = 1,
  int revision = 1,
  bool saved = true,
  ConversationLifecycle lifecycle = ConversationLifecycle.terminal,
  ConversationDescriptor? descriptor,
  DateTime? createdAt,
  DateTime? updatedAt,
  ConversationItemSource source = const ConversationContentSource(),
  Map<ThreadContentFieldView, int> totalBytes = const {},
  Map<ThreadContentFieldView, String>? fields,
}) => ConversationItem(
  header: ConversationItemHeader(
    id: id,
    threadId: threadId,
    turnId: turnId,
    ordinal: ordinal,
    createdAt: createdAt ?? DateTime.fromMillisecondsSinceEpoch(1700000000000),
    updatedAt: updatedAt ?? DateTime.fromMillisecondsSinceEpoch(1700000001000),
  ),
  revision: revision,
  descriptor:
      descriptor ??
      ConversationTextDescriptor(
        channel: ThreadTextChannel.finalAnswer,
        attachments: const [],
        lifecycle: CompletedThreadContentView(
          DateTime.fromMillisecondsSinceEpoch(1700000001000),
        ),
      ),
  source: source,
  saved: saved,
  lifecycle: lifecycle,
  fields: List.unmodifiable(
    (fields ?? {const ThreadTextFieldView(): '中文 🐱\n'}).entries.map(
      (entry) => ConversationFieldPreview(
        field: entry.key,
        text: entry.value,
        totalBytes: totalBytes[entry.key] ?? utf8.encode(entry.value).length,
      ),
    ),
  ),
);

/// 借用真实 SDK 内容对象；不设置可见需求，不打开 feed，也不在夹具内归约。
ConversationContent conversationContentFixture({
  String threadId = 'thread',
  WidgetTester? tester,
}) {
  final client = AnyworkClient(
    transport: RecordingDemoTransport(),
    clientId: 'content-fixture',
  );
  addTearDown(() async {
    final report = tester == null
        ? await client.close()
        : await pumpClientFuture(
            tester,
            client.close(),
            'content fixture client teardown close',
          );
    expect(report.complete, isTrue, reason: '无 demand 的内容 fixture 必须真实关闭');
  });
  return client.conversations.session(threadId).content;
}

typedef ConversationInputFixture = ({
  ConversationUserInputDescriptor descriptor,
  Map<ThreadContentFieldView, String> fields,
});

/// 准备独立的读快照；不是更新算法，调用方必须显式给出完整字段事实。
ConversationItem conversationCopyFixture(
  ConversationItem current, {
  int? revision,
  int? ordinal,
  String? turnId,
  DateTime? updatedAt,
  ConversationDescriptor? descriptor,
  ConversationItemSource? source,
  bool? saved,
  ConversationLifecycle? lifecycle,
  Map<ThreadContentFieldView, String>? fields,
  Map<ThreadContentFieldView, int> totalBytes = const {},
}) => conversationFixture(
  id: current.id,
  threadId: current.header.threadId,
  turnId: turnId ?? current.header.turnId,
  ordinal: ordinal ?? current.header.ordinal,
  createdAt: current.header.createdAt,
  updatedAt: updatedAt ?? current.header.updatedAt,
  revision: revision ?? current.revision,
  descriptor: descriptor ?? current.descriptor,
  source: source ?? current.source,
  saved: saved ?? current.saved,
  lifecycle: lifecycle ?? current.lifecycle,
  fields:
      fields ?? {for (final field in current.fields) field.field: field.text},
  totalBytes: {
    for (final field in current.fields) field.field: field.totalBytes,
    ...totalBytes,
  },
);

/// 从交互输入准备读 DTO 的两部分事实，不解析工具正文，也不归约更新。
ConversationInputFixture conversationInputFixture({
  required String interactionId,
  required List<UserQuestionView> questions,
  required ConversationUserInputState state,
  Map<String, List<String>> answers = const {},
}) {
  final fields = <ThreadContentFieldView, String>{};
  for (var i = 0; i < questions.length; i++) {
    final question = questions[i];
    void put(ThreadUserInputFieldPartView part, String value) {
      fields[ThreadToolUserInputFieldView(questionIndex: i, part: part)] =
          value;
    }

    put(const ThreadUserInputHeaderFieldPartView(), question.header);
    put(const ThreadUserInputQuestionFieldPartView(), question.question);
    for (var j = 0; j < question.options.length; j++) {
      put(
        ThreadUserInputOptionLabelFieldPartView(j),
        question.options[j].label,
      );
      put(
        ThreadUserInputOptionDescriptionFieldPartView(j),
        question.options[j].description,
      );
    }
    final answerDescriptor = state is ConversationUserInputResolved
        ? state.answers
              .where((answer) => answer.questionId == question.id)
              .firstOrNull
        : null;
    if (answerDescriptor != null &&
        !answerDescriptor.redacted &&
        !question.isSecret) {
      final values = answers[question.id] ?? const <String>[];
      for (var j = 0; j < values.length; j++) {
        put(ThreadUserInputAnswerFieldPartView(j), values[j]);
      }
    }
  }
  return (
    descriptor: ConversationUserInputDescriptor(
      interactionId: interactionId,
      questions: [
        for (final question in questions)
          ConversationQuestionDescriptor(
            id: question.id,
            isOther: question.isOther,
            isSecret: question.isSecret,
            optionCount: question.options.length,
          ),
      ],
      state: state,
    ),
    fields: fields,
  );
}

/// A real feed consumer for transport tests. ACK is explicit and never part of production adaptation.
final class ConversationProbe {
  ConversationProbe(this.feed) : _iterator = StreamIterator(feed.events);
  final ConversationFeed feed;
  final StreamIterator<ConversationFrame> _iterator;
  Future<ConversationFrame> next() async {
    if (!await _iterator.moveNext()) {
      throw StateError('Feed ended before the expected frame');
    }
    return _iterator.current;
  }

  Future<ConversationBaseline> baseline() async {
    while (true) {
      final frame = await next();
      switch (frame.event) {
        case ConversationBaselineEvent(:final baseline):
          await feed.acknowledge(frame.deliverySequence);
          return baseline;
        case ConversationStateEvent():
          await feed.acknowledge(frame.deliverySequence);
        case ConversationFailureEvent(:final failure):
          throw failure;
        case ConversationClosedEvent():
          throw StateError('Feed closed before baseline');
        case ConversationUpdateEvent():
          throw StateError('Update before baseline');
      }
    }
  }

  Future<ConversationUpdate> update() async {
    while (true) {
      final frame = await next();
      switch (frame.event) {
        case ConversationUpdateEvent(:final update):
          await feed.acknowledge(frame.deliverySequence);
          return update;
        case ConversationStateEvent():
          await feed.acknowledge(frame.deliverySequence);
        case ConversationFailureEvent(:final failure):
          throw failure;
        case ConversationClosedEvent():
          throw StateError('Feed closed before update');
        case ConversationBaselineEvent():
          throw StateError('Unexpected second baseline');
      }
    }
  }

  Future<void> close() async {
    feed.requestClose();
    await feed.close();
    await _iterator.cancel();
  }
}
