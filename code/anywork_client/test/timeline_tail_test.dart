import 'package:anywork_client/studio_client.dart';
import 'package:test/test.dart';

import 'support/timeline_transport.dart';

ConversationBatch batch({
  int from = 1,
  int through = 2,
  String epoch = 'epoch',
  String subscription = 'sub',
  List<ConversationItem>? items,
}) => ConversationBatch(
  subscriptionId: subscription,
  timelineEpoch: epoch,
  fromSeq: from,
  throughSeq: through,
  items: items ?? [timelineItem(2, id: 'second')],
);

void main() {
  Future<Object> reject(
    ConversationEvent event, {
    int? sequence,
    String? frameThread,
    String? frameSubscription,
  }) async {
    final fixture = ConversationFixture();
    final feed = await fixture.open();
    final consumer = fixture.consumers['thread']!;
    final failure = fixture.session().content.state.waitFor(
      (state) => state is ChatReconnecting<bool> || state is ChatFailed<bool>,
    );
    feed.send(
      event,
      sequence: sequence,
      frameThread: frameThread,
      frameSubscription: frameSubscription,
    );
    final result = await failure;
    expect(feed.acknowledgements, [1]);
    expect(consumer.frames, hasLength(1));
    await fixture.close();
    return switch (result) {
      ChatReconnecting(:final error) || ChatFailed(:final error) => error,
      _ => throw StateError('expected failure'),
    };
  }

  test('a continuous batch is accepted as immutable items and acked', () async {
    final fixture = ConversationFixture();
    final feed = await fixture.open();
    final consumer = fixture.consumers['thread']!;
    final items = [timelineItem(2, id: 'next', body: 'hello')];
    final update = batch(items: items);
    items.clear();
    await feed.deliver(ConversationUpdateEvent(update: update));
    final frame = consumer.frames.last as ConversationCompletedBatchFrame;
    expect(
      frame.batch.items.single.fieldFor(const ThreadTextFieldView())!.text,
      'hello',
    );
    expect(() => frame.batch.items.clear(), throwsUnsupportedError);
    expect(feed.acknowledgements, [1, 2]);
    await fixture.close();
  });

  test('subscription, epoch, delivery sequence and completion cursor are independent', () async {
    for (final update in [
      batch(from: 7, through: 8, items: [timelineItem(8)]),
      batch(epoch: 'wrong'),
      batch(subscription: 'wrong'),
    ]) {
      expect(
        await reject(ConversationUpdateEvent(update: update)),
        isA<ConversationContinuityError>(),
      );
    }
    expect(
      await reject(ConversationUpdateEvent(update: batch()), sequence: 3),
      isA<ConversationContinuityError>(),
    );
    expect(
      await reject(
        ConversationUpdateEvent(update: batch()),
        frameThread: 'other',
      ),
      isA<ConversationContinuityError>(),
    );
    expect(
      await reject(
        ConversationUpdateEvent(update: batch()),
        frameSubscription: 'other',
      ),
      isA<ConversationContinuityError>(),
    );
  });

  test(
    'invalid item identity or byte lengths do not reach consumer or ACK',
    () async {
      final duplicate = batch(
        through: 3,
        items: [
          timelineItem(2, id: 'same'),
          timelineItem(3, id: 'same'),
        ],
      );
      final badLength = batch(
        items: [timelineItem(2, body: '你好', totalBytes: 1)],
      );
      final badThread = batch(items: [timelineItem(2, threadId: 'other')]);
      for (final value in [duplicate, badLength, badThread]) {
        expect(
          await reject(ConversationUpdateEvent(update: value)),
          isA<ConversationContinuityError>(),
        );
      }
    },
  );

  test(
    'oversized immutable metadata or batch is rejected before delivery',
    () async {
      ConversationItem raw(int seq, String notice) => ConversationItem(
        header: ConversationItemHeader(
          id: 'raw-$seq',
          threadId: 'thread',
          appendSeq: seq,
        ),
        source: const ConversationContentSource(),
        descriptor: ConversationRawDescriptor(
          origin: ThreadRawItemOrigin.stored,
          payloads: const [],
          notice: notice,
          recordedAt: DateTime.utc(2026),
        ),
        fields: const [],
      );
      expect(
        await reject(
          ConversationUpdateEvent(
            update: batch(items: [raw(2, 'x' * (256 * 1024))]),
          ),
        ),
        isA<ConversationContinuityError>(),
      );
      final large = 'x' * (240 * 1024);
      expect(
        await reject(
          ConversationUpdateEvent(
            update: batch(
              through: 10,
              items: [for (var seq = 2; seq <= 10; seq++) raw(seq, large)],
            ),
          ),
        ),
        isA<ConversationContinuityError>(),
      );
    },
  );

  test(
    'body and tool argument preview caps are enforced before delivery',
    () async {
      final text = timelineItem(2, body: 'x' * (32 * 1024 + 1));
      expect(
        await reject(ConversationUpdateEvent(update: batch(items: [text]))),
        isA<ConversationContinuityError>(),
      );
      final tool = ConversationItem(
        header: const ConversationItemHeader(
          id: 'tool',
          threadId: 'thread',
          appendSeq: 2,
        ),
        source: const ConversationContentSource(),
        descriptor: ConversationToolDescriptor(
          invocation: const ConversationToolInvocation(
            toolCallId: 'call',
            name: 'exec',
          ),
          state: ConversationToolSucceeded(
            completedAt: DateTime.utc(2026),
            output: ConversationToolOutputDescriptor(attachments: const []),
          ),
        ),
        fields: [
          ConversationFieldPreview(
            field: const ThreadToolArgumentsFieldView(),
            text: 'x' * 4097,
            totalBytes: 4097,
          ),
        ],
      );
      expect(
        await reject(ConversationUpdateEvent(update: batch(items: [tool]))),
        isA<ConversationContinuityError>(),
      );
    },
  );

  test('all Turn failure and rollover strings are charged before consumer acceptance', () async {
    ConversationItem turn(int seq, String field, String payload) {
      final failure = StudioTurnFailureView(
        category: field == 'category' ? payload : 'category',
        providerKind: field == 'providerKind' ? payload : 'provider',
        code: field == 'code' ? payload : 'code',
        httpStatus: 500,
        message: field == 'message' ? payload : 'message',
        retryable: false,
        retryAfterMs: null,
      );
      final ConversationTurnOutcome outcome = field == 'rollover'
          ? ConversationTurnBudgetLimited(
              BudgetLimitedStudioTurnState(
                startedAt: 1,
                completedAt: 2,
                limit: const StudioTurnBudgetLimit(
                  kind: StudioTurnBudgetLimitKind.modelStep,
                  usage: StudioTurnBudgetUsage(
                    modelSteps: 1,
                    toolCalls: 0,
                    waitCalls: 0,
                    elapsedMs: 1,
                  ),
                ),
                rollover: RolloverFailed(error: payload),
              ),
            )
          : ConversationTurnFailed(
              FailedStudioTurnState(
                startedAt: 1,
                completedAt: 2,
                failure: failure,
              ),
            );
      return ConversationItem(
        header: ConversationItemHeader(
          id: 'turn-$seq',
          threadId: 'thread',
          appendSeq: seq,
        ),
        source: const ConversationContentSource(),
        descriptor: ConversationTurnDescriptor(
          inputId: 'input-$seq',
          outcome: outcome,
        ),
        fields: const [],
      );
    }

    for (final field in [
      'message',
      'category',
      'providerKind',
      'code',
      'rollover',
    ]) {
      final oversized = turn(2, field, 'x' * (256 * 1024));
      expect(
        await reject(
          ConversationUpdateEvent(update: batch(items: [oversized])),
        ),
        isA<ConversationContinuityError>(),
        reason: '$field must be charged',
      );
      final large = 'x' * (240 * 1024);
      expect(
        await reject(
          ConversationUpdateEvent(
            update: batch(
              through: 10,
              items: [
                for (var seq = 2; seq <= 10; seq++) turn(seq, field, large),
              ],
            ),
          ),
        ),
        isA<ConversationContinuityError>(),
        reason: '$field must count toward batch',
      );
    }

    final fixture = ConversationFixture();
    final feed = await fixture.open();
    final originals = [
      for (final (index, field) in [
        'message',
        'category',
        'providerKind',
        'code',
        'rollover',
      ].indexed)
        turn(index + 2, field, 'value-$field'),
    ];
    await feed.deliver(
      ConversationUpdateEvent(update: batch(through: 6, items: originals)),
    );
    final delivered =
        (fixture.consumers['thread']!.frames.last
                as ConversationCompletedBatchFrame)
            .batch
            .items;
    for (var i = 0; i < delivered.length; i++) {
      expect(delivered[i], same(originals[i]));
    }
    final failure =
        ((delivered[1].descriptor as ConversationTurnDescriptor).outcome
                as ConversationTurnFailed)
            .value
            .failure;
    expect(failure.category, 'value-category');
    expect(
      ((delivered.last.descriptor as ConversationTurnDescriptor).outcome
              as ConversationTurnBudgetLimited)
          .value
          .rollover,
      isA<RolloverFailed>().having((v) => v.error, 'error', 'value-rollover'),
    );
    expect(feed.acknowledgements, [1, 2]);
    await fixture.close();
  });

  test(
    'reset changes epoch and next batch uses the newly accepted cursor',
    () async {
      final fixture = ConversationFixture();
      final feed = await fixture.open();
      final consumer = fixture.consumers['thread']!;
      await feed.deliver(
        ConversationUpdateEvent(
          update: ConversationReset(
            baseline(
              5,
              timelineEpoch: 'next',
              items: [timelineItem(5, id: 'new')],
            ),
          ),
        ),
      );
      await feed.deliver(
        ConversationUpdateEvent(
          update: batch(
            from: 5,
            through: 6,
            epoch: 'next',
            items: [timelineItem(6, id: 'after')],
          ),
        ),
      );
      expect(consumer.frames[1], isA<ConversationResetFrame>());
      expect(
        (consumer.frames[2] as ConversationCompletedBatchFrame)
            .batch
            .throughSeq,
        6,
      );
      expect(feed.acknowledgements, [1, 2, 3]);
      await fixture.close();
      expect(
        await reject(
          ConversationUpdateEvent(update: ConversationReset(baseline(5))),
        ),
        isA<ConversationContinuityError>(),
      );
    },
  );

  test('Failure and Closed terminal envelopes do not consume ACK', () async {
    const failure = StudioFailure(
      code: StudioFailureCode.busy,
      message: 'producer unavailable',
      retryable: true,
      correlationId: 'terminal',
    );
    expect(
      await reject(
        const ConversationFailureEvent(failure: failure),
        sequence: 1,
      ),
      same(failure),
    );
    expect(
      await reject(const ConversationClosedEvent(), sequence: 1),
      isA<ConversationStreamEnded>(),
    );
  });
}
