import 'package:anywork_client/studio_client.dart';
import 'package:test/test.dart';

import 'support/timeline_transport.dart';

ConversationUpdateItem update({
  int expected = 1,
  int revision = 2,
  bool saved = false,
  ConversationLifecycle lifecycle = ConversationLifecycle.streaming,
  List<ConversationFieldUpdate> fields = const [],
  ConversationItemHeader? header,
  ConversationDescriptor? descriptor,
}) => ConversationUpdateItem(
  itemId: 'item',
  expectedRevision: expected,
  revision: revision,
  saved: saved,
  lifecycle: lifecycle,
  fields: fields,
  header: header,
  descriptor: descriptor,
);
ConversationFieldUpdate textUpdate(
  ThreadFieldChangeView change, {
  required int total,
  required int preview,
}) => ConversationFieldUpdate(
  field: const ThreadTextFieldView(),
  change: change,
  totalBytes: total,
  previewBytes: preview,
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
    final content = fixture.session().content;
    final failure = content.state.waitFor(
      (state) =>
          state is ChatReconnecting<ConversationContentFrame> ||
          state is ChatFailed<ConversationContentFrame>,
    );
    feed.send(
      event,
      sequence: sequence,
      frameThread: frameThread,
      frameSubscription: frameSubscription,
    );
    final result = await failure;
    expect(feed.acknowledgements, [1]);
    expect(
      content.lastDeliveredFrame,
      isA<ConversationBaselineFrame>().having(
        (frame) => frame.baseline.version,
        'last committed version',
        1,
      ),
    );
    await fixture.close();
    return switch (result) {
      ChatReconnecting(:final error) || ChatFailed(:final error) => error,
      _ => throw StateError('Expected an explicit sync failure'),
    };
  }

  test(
    'a batch over 8 MiB fails atomically before copying otherwise valid items',
    () async {
      final notice = List.filled(200 * 1024, 'x').join();
      final changes = List<ConversationChange>.generate(
        50,
        (index) => ConversationAdd(
          ConversationItem(
            header: timelineItem(index + 2, id: 'raw-$index').header,
            revision: 1,
            descriptor: ConversationRawDescriptor(
              origin: ThreadRawItemOrigin.stored,
              payloads: const [],
              notice: notice,
              recordedAt: DateTime.utc(2026),
            ),
            saved: true,
            lifecycle: ConversationLifecycle.terminal,
            fields: const [],
          ),
        ),
      );
      expect(
        await reject(
          ConversationUpdateEvent(update: patch(1, 2, changes: changes)),
        ),
        isA<ConversationContinuityError>(),
      );
    },
  );

  test(
    'subscription, thread, delivery prefix and content version are independent',
    () async {
      for (final event in [
        ConversationUpdateEvent(update: patch(9, 10)),
        ConversationUpdateEvent(update: patch(1, 1)),
        ConversationUpdateEvent(update: patch(1, 2, subscriptionId: 'other')),
      ]) {
        expect(await reject(event), isA<ConversationContinuityError>());
      }
      expect(
        await reject(ConversationUpdateEvent(update: patch(1, 2)), sequence: 3),
        isA<ConversationContinuityError>(),
      );
      expect(
        await reject(
          ConversationUpdateEvent(update: patch(1, 2)),
          frameThread: 'other',
        ),
        isA<ConversationContinuityError>(),
      );
      expect(
        await reject(
          ConversationUpdateEvent(update: patch(1, 2)),
          frameSubscription: 'other',
        ),
        isA<ConversationContinuityError>(),
      );
    },
  );

  test('whole item update validates on a candidate and commits no partial field or revision', () async {
    final fixture = ConversationFixture();
    final content = fixture.session().content;
    final initial = timelineItem(1, body: '中', totalBytes: 3);
    final candidate = update(
      fields: [
        textUpdate(
          const AppendThreadFieldChangeView('文'),
          total: 6,
          preview: 6,
        ),
        const ConversationFieldUpdate(
          field: ThreadThinkingSummaryFieldView(0),
          change: AppendThreadFieldChangeView('bad'),
          totalBytes: 3,
          previewBytes: 3,
        ),
      ],
    );
    expect(
      () => content.reduceItem(initial, candidate),
      throwsA(isA<ConversationContinuityError>()),
    );
    expect(initial.revision, 1);
    expect(initial.fieldFor(const ThreadTextFieldView())!.text, '中');
    final next = content.reduceItem(
      initial,
      update(
        fields: [
          textUpdate(
            const AppendThreadFieldChangeView('文\n'),
            total: 7,
            preview: 7,
          ),
        ],
      ),
    );
    expect(next.revision, 2);
    expect(next.fieldFor(const ThreadTextFieldView())!.text, '中文\n');
    expect(next.omittedBytes, 0);
    expect(next.details.single.previewBytes, 7);
    await fixture.close();
  });

  test('same revision completeness, saving and terminal reliable corrections retain exact text', () async {
    final fixture = ConversationFixture();
    final content = fixture.session().content;
    final partial = timelineItem(
      1,
      body: 'a',
      totalBytes: 3,
      lifecycle: ConversationLifecycle.terminal,
    );
    final complete = content.reduceItem(
      partial,
      update(
        revision: 1,
        lifecycle: ConversationLifecycle.terminal,
        fields: [
          textUpdate(
            const AppendThreadFieldChangeView('b\n'),
            total: 3,
            preview: 3,
          ),
        ],
      ),
    );
    expect(complete.fieldFor(const ThreadTextFieldView())!.text, 'ab\n');
    final saved = content.reduceItem(
      complete,
      update(
        revision: 1,
        saved: true,
        lifecycle: ConversationLifecycle.terminal,
      ),
    );
    expect(saved.saved, isTrue);
    final corrected = content.reduceItem(
      saved,
      update(
        saved: false,
        lifecycle: ConversationLifecycle.terminal,
        fields: [
          textUpdate(
            const ReplaceThreadFieldChangeView('x'),
            total: 1,
            preview: 1,
          ),
        ],
      ),
    );
    expect(corrected.terminal, isTrue);
    expect(corrected.saved, isFalse);
    expect(corrected.fields.single.text, 'x');
    expect(
      () => content.reduceItem(
        saved,
        update(
          revision: 1,
          saved: true,
          lifecycle: ConversationLifecycle.terminal,
          fields: [
            textUpdate(
              const ReplaceThreadFieldChangeView('a'),
              total: 3,
              preview: 1,
            ),
          ],
        ),
      ),
      throwsA(isA<ConversationContinuityError>()),
    );
    expect(
      () => content.reduceItem(saved, update(revision: 0, saved: true)),
      throwsA(isA<ConversationContinuityError>()),
    );
    expect(
      () => content.reduceItem(saved, update(saved: true)),
      throwsA(isA<ConversationContinuityError>()),
    );
    await fixture.close();
  });

  test(
    'UTF-8 lengths, duplicate fields and all four patch operations are strict',
    () async {
      final fixture = ConversationFixture();
      final content = fixture.session().content;
      final initial = timelineItem(1, body: 'é');
      for (final invalid in [
        update(expected: 0),
        update(
          fields: [
            textUpdate(
              const AppendThreadFieldChangeView('!'),
              total: 2,
              preview: 2,
            ),
          ],
        ),
        update(
          fields: [
            textUpdate(
              const UnchangedThreadFieldChangeView(),
              total: 1,
              preview: 1,
            ),
          ],
        ),
        update(
          fields: [
            textUpdate(
              const RemoveThreadFieldChangeView(),
              total: 1,
              preview: 0,
            ),
          ],
        ),
        update(
          fields: [
            textUpdate(
              const UnchangedThreadFieldChangeView(),
              total: 2,
              preview: 2,
            ),
            textUpdate(
              const UnchangedThreadFieldChangeView(),
              total: 2,
              preview: 2,
            ),
          ],
        ),
      ]) {
        expect(
          () => content.reduceItem(initial, invalid),
          throwsA(isA<ConversationContinuityError>()),
        );
      }
      final unchanged = content.reduceItem(
        initial,
        update(
          fields: [
            textUpdate(
              const UnchangedThreadFieldChangeView(),
              total: 2,
              preview: 2,
            ),
          ],
        ),
      );
      expect(unchanged.fields.single.text, 'é');
      final removed = content.reduceItem(
        unchanged,
        update(
          expected: 2,
          revision: 3,
          fields: [
            textUpdate(
              const RemoveThreadFieldChangeView(),
              total: 0,
              preview: 0,
            ),
          ],
        ),
      );
      expect(removed.fields, isEmpty);
      expect(removed.omittedBytes, 0);
      await fixture.close();
    },
  );

  test('Add updates known identity; old-order Add and untracked Remove are delivered, not guessed away', () async {
    final fixture = ConversationFixture();
    final feed = await fixture.open();
    final content = fixture.session().content;
    await feed.deliver(
      ConversationUpdateEvent(
        update: patch(
          1,
          2,
          changes: [
            ConversationAdd(timelineItem(2, body: 'replacement')),
            ConversationAdd(timelineItem(1, id: 'earlier', ordinal: 0)),
            const ConversationRemove('loaded-only-in-history'),
          ],
        ),
      ),
    );
    final frame = content.lastDeliveredFrame as ConversationPatchFrame;
    expect(frame.patch.changes, hasLength(3));
    // The next update proves the SDK committed Add's revision, rather than
    // waiting for an unpromised later replacement from the producer.
    await feed.deliver(
      ConversationUpdateEvent(
        update: patch(
          2,
          3,
          changes: [update(expected: 2, revision: 3, saved: true)],
        ),
      ),
    );
    expect(feed.acknowledgements, [1, 2, 3]);
    await fixture.close();
  });

  test(
    'explicit Resync adopts a new baseline on the same subscription only',
    () async {
      final fixture = ConversationFixture();
      final feed = await fixture.open();
      await feed.deliver(
        ConversationUpdateEvent(
          update: ConversationResync(
            subscriptionId: 'sub',
            reason: ConversationResyncReason.lagging,
            baseline: baseline(50),
          ),
        ),
      );
      final frame =
          fixture.session().content.lastDeliveredFrame
              as ConversationBaselineFrame;
      expect(frame.isResync, isTrue);
      expect(frame.baseline.version, 50);
      await feed.deliver(ConversationUpdateEvent(update: patch(50, 51)));
      await fixture.close();
      expect(
        await reject(
          ConversationUpdateEvent(
            update: ConversationResync(
              subscriptionId: 'sub',
              reason: ConversationResyncReason.lagging,
              baseline: baseline(3, subscriptionId: 'other'),
            ),
          ),
        ),
        isA<ConversationContinuityError>(),
      );
    },
  );

  test('Failure/Closed terminal envelopes repeat the last data sequence without ACK', () async {
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
