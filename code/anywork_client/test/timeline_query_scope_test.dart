import 'dart:async';

import 'package:anywork_client/studio_client.dart';
import 'package:test/test.dart';

import 'support/timeline_transport.dart';

void main() {
  test('page/detail validation rejects invalid arguments before transport admission', () async {
    final fixture = ConversationFixture();
    final feed = await fixture.open();
    final scope = fixture.session().content.openScope(generation: 1)!;
    for (final limit in [0, 101]) {
      await expectLater(
        scope.page(limit: limit),
        throwsA(isA<StudioFailure>()),
      );
    }
    for (final bytes in [3, 262145]) {
      await expectLater(
        scope.readDetail(
          itemId: 'item',
          query: ConversationDetailQuery(
            field: const ThreadTextFieldView(),
            revision: 1,
            maxBytes: bytes,
          ),
        ),
        throwsA(isA<StudioFailure>()),
      );
    }
    expect(feed.pageRequests, isEmpty);
    expect(feed.detailRequests, isEmpty);
    await scope.page();
    expect(feed.pageRequests.single.limit, 32);
    await scope.close();
    await fixture.close();
  });

  test('opaque cursor and detail continuation retain field/revision and exact UTF-8', () async {
    final fixture = ConversationFixture();
    final feed = await fixture.open();
    final scope = fixture.session().content.openScope(generation: 1)!;
    feed.onPage = (before, limit) async => ConversationPage(
      items: [timelineItem(1, id: 'older', ordinal: 0)],
      before: 'next',
      hasOlder: true,
    );
    final page = await scope.page(before: 'cursor', limit: 7);
    expect(feed.pageRequests.single, (before: 'cursor', limit: 7));
    expect(page.before, 'next');
    expect(page.hasOlder, isTrue);
    feed.onDetail = (item, query) async => ConversationDetailChunk(
      itemId: item,
      field: query.field,
      revision: query.revision,
      text: query.continuation == null ? '中' : '文\n',
      totalBytes: 7,
      continuation: query.continuation == null ? 'opaque' : null,
    );
    final first = await scope.readDetail(
      itemId: 'item',
      query: const ConversationDetailQuery(
        field: ThreadTextFieldView(),
        revision: 1,
        maxBytes: 4,
      ),
    );
    final second = await scope.readDetail(
      itemId: 'item',
      query: ConversationDetailQuery(
        field: first.field,
        revision: first.revision,
        maxBytes: 4,
        continuation: first.continuation,
      ),
    );
    expect(first.text + second.text, '中文\n');
    expect(second.isLast, isTrue);
    feed.onDetail = (item, query) async => ConversationDetailChunk(
      itemId: item,
      field: query.field,
      revision: 2,
      text: 'bad',
      totalBytes: 3,
      continuation: null,
    );
    await expectLater(
      scope.readDetail(
        itemId: 'item',
        query: const ConversationDetailQuery(
          field: ThreadTextFieldView(),
          revision: 1,
        ),
      ),
      throwsA(isA<ConversationContinuityError>()),
    );
    await fixture.close();
  });

  for (final synchronousThrow in [false, true]) {
    test(
      'scope retirement rejects late results but joins their exact native futures (synchronousThrow=$synchronousThrow)',
      () async {
        final budget = ResourceBudget();
        final fixture = ConversationFixture(budget: budget);
        final feed = await fixture.open();
        final scope = fixture.session().content.openScope(generation: 1)!;
        final reply = Completer<ConversationPage>();
        final failure = StateError('synchronous query failure');
        late Future<CloseReport> scopeClosing;
        var closed = false;
        var admittedDuringCallback = -1;
        var permitDuringCallback = false;
        feed.onPage = (_, _) {
          scopeClosing = scope.close().then((report) {
            closed = true;
            return report;
          });
          admittedDuringCallback = scope.pendingQueries;
          permitDuringCallback = budget.usage.any(
            (resource) => resource.owner.startsWith('timeline-page:'),
          );
          if (synchronousThrow) throw failure;
          return reply.future;
        };
        final pending = scope.page();
        final failed = expectLater(
          pending,
          throwsA(
            synchronousThrow ? same(failure) : isA<StaleConversationScope>(),
          ),
        );
        expect(
          admittedDuringCallback,
          1,
          reason: 'The exact query is registered before transport can synchronously close',
        );
        expect(permitDuringCallback, isTrue);
        expect(scope.isActive, isFalse);
        if (!synchronousThrow) {
          await Future<void>.value();
          expect(closed, isFalse);
          expect(scope.pendingQueries, 1);
          expect(
            (await scope.close(deadline: DateTime.now())).complete,
            isFalse,
          );
          final closing = fixture.close(deadline: DateTime.now());
          expect((await closing).complete, isFalse);
          expect(
            budget.usage.any(
              (resource) => resource.owner.startsWith('timeline-page:'),
            ),
            isTrue,
          );
          reply.complete(
            const ConversationPage(items: [], before: null, hasOlder: false),
          );
        }
        await failed;
        expect((await scopeClosing).complete, isTrue);
        expect(closed, isTrue);
        expect(
          budget.usage.where(
            (resource) => resource.owner.startsWith('timeline-page:'),
          ),
          isEmpty,
        );
        if (synchronousThrow) await fixture.close();
        await feed.closeCompleted.future;
        expect((await fixture.client.retryCleanup()).complete, isTrue);
        expect(budget.usage, isEmpty);
      },
    );
  }

  for (final qualified in [false, true]) {
    test(
      'page tail interleaving merges reliable updates and does not resurrect Remove (qualified=$qualified)',
      () async {
        final fixture = ConversationFixture();
        final feed = await fixture.open(
          initial: baseline(
            1,
            items: [
              timelineItem(1, id: 'old', ordinal: 0),
              timelineItem(1, ordinal: 1),
            ],
            before: 'older',
            hasOlder: true,
          ),
        );
        final content = fixture.session().content;
        final scope = content.openScope(
          generation: 1,
          coverage: qualified ? (await content.ready).pageCoverage : null,
        )!;
        final reply = Completer<ConversationPage>();
        feed.onPage = (_, _) => reply.future;
        final page = scope.page(before: 'older');
        await feed.deliver(
          ConversationUpdateEvent(
            update: patch(
              1,
              2,
              changes: [
                const ConversationRemove('old'),
                const ConversationUpdateItem(
                  itemId: 'item',
                  expectedRevision: 1,
                  revision: 1,
                  saved: true,
                  lifecycle: ConversationLifecycle.streaming,
                  fields: [],
                ),
              ],
            ),
          ),
        );
        reply.complete(
          ConversationPage(
            items: [
              timelineItem(1, id: 'old', ordinal: 0),
              timelineItem(1, ordinal: 1),
            ],
            before: 'earlier',
            hasOlder: true,
          ),
        );
        final result = await page;
        expect(result.items.map((i) => i.id), ['item']);
        expect(result.items.single.saved, isTrue);
        expect(result.before, 'earlier');
        await fixture.close();
      },
    );
  }

  test(
    'current tail Turn association overrides a late same-revision page header',
    () async {
      final fixture = ConversationFixture();
      final initial = timelineItem(1, ordinal: 1);
      final feed = await fixture.open(initial: baseline(1, items: [initial]));
      final scope = fixture.session().content.openScope(generation: 1)!;
      final reply = Completer<ConversationPage>();
      feed.onPage = (_, _) => reply.future;
      final page = scope.page();
      final changedHeader = ConversationItemHeader(
        id: initial.id,
        threadId: initial.header.threadId,
        turnId: 'current-tail-turn',
        ordinal: initial.header.ordinal,
        createdAt: initial.header.createdAt,
        updatedAt: DateTime.utc(2026, 2),
      );
      await feed.deliver(
        ConversationUpdateEvent(
          update: ConversationPatch(
            subscriptionId: 'sub',
            from: 1,
            to: 2,
            changes: [
              ConversationUpdateItem(
                itemId: initial.id,
                expectedRevision: initial.revision,
                revision: initial.revision,
                saved: initial.saved,
                lifecycle: initial.lifecycle,
                header: changedHeader,
                fields: const [],
              ),
            ],
            priority: ConversationPriority.coalesced,
          ),
        ),
      );
      reply.complete(
        ConversationPage(items: [initial], before: null, hasOlder: false),
      );
      final result = await page;
      expect(result.items.single.header.turnId, 'current-tail-turn');
      expect(result.items.single.header.updatedAt, DateTime.utc(2026, 2));
      await fixture.close();
    },
  );

  test('page continuity lost to Resync fails explicitly without manufacturing history', () async {
    final fixture = ConversationFixture();
    final feed = await fixture.open();
    final scope = fixture.session().content.openScope(generation: 1)!;
    final reply = Completer<ConversationPage>();
    feed.onPage = (_, _) => reply.future;
    final page = scope.page();
    final failure = expectLater(
      page,
      throwsA(isA<ConversationContinuityError>()),
    );
    await feed.deliver(
      ConversationUpdateEvent(
        update: ConversationResync(
          subscriptionId: 'sub',
          reason: ConversationResyncReason.unavailable,
          baseline: baseline(8),
        ),
      ),
    );
    reply.complete(
      ConversationPage(items: [timelineItem(1)], before: null, hasOlder: false),
    );
    await failure;
    await fixture.close();
  });

  test('page errors remain typed, repeated scope close is a true join and no new demand', () async {
    final fixture = ConversationFixture();
    final feed = await fixture.open();
    final scope = fixture.session().content.openScope(generation: 1)!;
    const failure = StudioFailure(
      code: StudioFailureCode.busy,
      message: 'history busy',
      retryable: true,
      correlationId: 'page',
    );
    feed.onPage = (_, _) => Future.error(failure);
    await expectLater(scope.page(), throwsA(same(failure)));
    expect(scope.pendingQueries, 0);
    expect((await scope.close()).complete, isTrue);
    expect((await scope.close()).complete, isTrue);
    await expectLater(scope.page(), throwsA(isA<StaleConversationScope>()));
    expect(fixture.transport.opens, hasLength(1));
    await fixture.close();
  });

  test('qualified pages cannot skip query-before identities but may return them authoritatively', () async {
    for (final includeKnown in [false, true]) {
      final fixture = ConversationFixture();
      final feed = await fixture.open(
        initial: baseline(
          1,
          items: [
            timelineItem(1, id: 'a', ordinal: 5),
            timelineItem(1, id: 'b', ordinal: 6),
          ],
          before: 'older',
          hasOlder: true,
        ),
      );
      final content = fixture.session().content;
      final coverage = (await content.ready).pageCoverage;
      final scope = content.openScope(generation: 1, coverage: coverage)!;
      await feed.deliver(
        ConversationUpdateEvent(
          update: patch(
            1,
            2,
            changes: [ConversationAdd(timelineItem(1, id: 'x', ordinal: 4))],
          ),
        ),
      );
      final response = ConversationPage(
        items: [
          timelineItem(1, id: 'y', ordinal: 3),
          if (includeKnown) timelineItem(2, id: 'x', ordinal: 4),
        ],
        before: null,
        hasOlder: false,
      );
      Future<ConversationPage> readWithUpdate(
        ConversationPage response,
        int from,
      ) async {
        final gate = Completer<ConversationPage>();
        feed.onPage = (_, _) => gate.future;
        final pending = scope.page(before: 'older');
        await feed.deliver(
          ConversationUpdateEvent(
            update: patch(
              from,
              from + 1,
              changes: [
                const ConversationUpdateItem(
                  itemId: 'x',
                  expectedRevision: 1,
                  revision: 1,
                  saved: true,
                  lifecycle: ConversationLifecycle.streaming,
                  fields: [],
                ),
              ],
            ),
          ),
        );
        gate.complete(response);
        return pending;
      }

      if (includeKnown) {
        final page = await readWithUpdate(response, 2);
        expect(page.items.map((item) => item.id), ['y', 'x']);
        expect(page.items.last.revision, 2);
        expect(scope.pageCoverage, isNot(same(coverage)));
      } else {
        await expectLater(
          readWithUpdate(response, 2),
          throwsA(isA<ConversationContinuityError>()),
        );
        expect(scope.pageCoverage, same(coverage));
        await expectLater(
          readWithUpdate(
            const ConversationPage(items: [], before: null, hasOlder: false),
            3,
          ),
          throwsA(isA<ConversationContinuityError>()),
        );
        expect(scope.pageCoverage, same(coverage));
        expect(
          scope.isActive,
          isTrue,
          reason: 'A continuity error must not refresh or retire before its caller sees it',
        );
      }
      expect(fixture.transport.opens, hasLength(1));
      await fixture.close();
    }
  });

  test('coverage rejects unknown overlap, preserves removed boundaries and accepts proved overlap', () async {
    final fixture = ConversationFixture();
    final a = timelineItem(1, id: 'a', ordinal: 1);
    final b = timelineItem(1, id: 'b', ordinal: 3);
    final feed = await fixture.open(
      initial: baseline(1, items: [a, b], before: 'older', hasOlder: true),
    );
    final content = fixture.session().content;
    final coverage = (await content.ready).pageCoverage;
    final scope = content.openScope(generation: 1, coverage: coverage)!;
    await feed.deliver(
      ConversationUpdateEvent(
        update: patch(
          1,
          2,
          changes: [
            ConversationAdd(timelineItem(1, id: 'x', ordinal: 2)),
            const ConversationRemove('a'),
          ],
        ),
      ),
    );
    for (final unknown in [
      timelineItem(1, id: 'unknown', ordinal: 2),
      timelineItem(1, id: 'z', ordinal: 1),
    ]) {
      feed.onPage = (_, _) async =>
          ConversationPage(items: [unknown], before: null, hasOlder: false);
      await expectLater(
        scope.page(before: 'older'),
        throwsA(isA<ConversationContinuityError>()),
      );
      expect(scope.pageCoverage, same(coverage));
    }
    feed.onPage = (_, _) async => ConversationPage(
      items: [
        timelineItem(1, id: 'older', ordinal: 0),
        timelineItem(1, id: 'x', ordinal: 2),
      ],
      before: null,
      hasOlder: false,
    );
    await expectLater(
      scope.page(before: 'older'),
      throwsA(isA<ConversationContinuityError>()),
    );
    expect(
      scope.pageCoverage,
      same(coverage),
      reason: 'Global knowledge of x is not membership in the frozen coverage',
    );
    feed.onPage = (_, _) async => ConversationPage(
      items: [
        timelineItem(1, id: 'older', ordinal: 0),
        a,
        b,
      ],
      before: 'earlier',
      hasOlder: true,
    );
    final page = await scope.page(before: 'older');
    expect(page.items.map((item) => item.id), ['older', 'b']);
    expect(scope.pageCoverage, isNot(same(coverage)));
    final extended = scope.pageCoverage;
    feed.onPage = (_, _) async => ConversationPage(
      items: [
        timelineItem(1, id: 'older', ordinal: 0),
        b,
      ],
      before: null,
      hasOlder: false,
    );
    expect((await scope.page(before: 'earlier')).items.map((item) => item.id), [
      'older',
      'b',
    ]);
    expect(
      scope.pageCoverage,
      isNot(same(extended)),
      reason:
          'A page-delivered identity remains provable in the extended coverage',
    );
    await fixture.close();
  });

  for (final reentered in [false, true]) {
    test(
      'qualified EOF reconciles a proved concurrent earlier Add without losing its frontier (reentered=$reentered)',
      () async {
        final fixture = ConversationFixture();
        final feed = await fixture.open(
          initial: baseline(
            1,
            items: [timelineItem(1, id: 'a', ordinal: 5)],
            before: 'older',
            hasOlder: true,
          ),
        );
        final content = fixture.session().content;
        final original = (await content.ready).pageCoverage;
        final scope = content.openScope(generation: 1, coverage: original)!;
        if (reentered) {
          await feed.deliver(
            ConversationUpdateEvent(
              update: patch(
                1,
                2,
                changes: [
                  ConversationAdd(
                    timelineItem(1, id: 'concurrent', ordinal: 4),
                  ),
                ],
              ),
            ),
          );
        }
        final reply = Completer<ConversationPage>();
        feed.onPage = (_, _) => reply.future;
        final pending = scope.page(before: 'older');
        await feed.deliver(
          ConversationUpdateEvent(
            update: patch(
              reentered ? 2 : 1,
              reentered ? 3 : 2,
              changes: [
                if (reentered) const ConversationRemove('concurrent'),
                ConversationAdd(
                  timelineItem(reentered ? 2 : 1, id: 'concurrent', ordinal: 4),
                ),
              ],
            ),
          ),
        );
        reply.complete(
          const ConversationPage(items: [], before: null, hasOlder: false),
        );
        final result = await pending;
        expect(result.items.map((item) => item.id), ['concurrent']);
        expect(result.items.single.revision, reentered ? 2 : 1);
        expect(result.hasOlder, isFalse);
        expect(scope.pageCoverage, isNot(same(original)));
        await fixture.close();
      },
    );
  }

  test('forgotten identity count or bytes remain uncertain rather than proving empty history', () async {
    for (final identifierBytes in [0, 230000]) {
      final fixture = ConversationFixture();
      final feed = await fixture.open(
        initial: baseline(
          1,
          items: [
            timelineItem(1, id: 'a', ordinal: 200),
            timelineItem(1, id: 'b', ordinal: 201),
          ],
          before: 'older',
          hasOlder: true,
        ),
      );
      final content = fixture.session().content;
      final coverage = (await content.ready).pageCoverage;
      final scope = content.openScope(generation: 1, coverage: coverage)!;
      final count = identifierBytes == 0 ? 101 : 40;
      final prefix = 'q' * identifierBytes;
      var version = 1;
      for (var index = 0; index < count; index++) {
        await feed.deliver(
          ConversationUpdateEvent(
            update: patch(
              version,
              ++version,
              changes: [
                ConversationAdd(
                  timelineItem(1, id: '$prefix-$index', ordinal: index + 1),
                ),
              ],
            ),
          ),
        );
      }
      for (var index = 0; index < count; index++) {
        await feed.deliver(
          ConversationUpdateEvent(
            update: patch(
              version,
              ++version,
              changes: [ConversationRemove('$prefix-$index')],
            ),
          ),
        );
      }
      feed.onPage = (_, _) async => ConversationPage(
        items: [timelineItem(1, id: 'older', ordinal: 0)],
        before: null,
        hasOlder: false,
      );
      await expectLater(
        scope.page(before: 'older'),
        throwsA(isA<ConversationContinuityError>()),
      );
      expect(scope.pageCoverage, same(coverage));
      await fixture.close();
    }
  });

  test('coverage belongs to its issuer, attempt and baseline epoch without opening hidden feeds', () async {
    final fixture = ConversationFixture();
    final feed = await fixture.open(
      initial: baseline(1, before: 'older', hasOlder: true),
    );
    final content = fixture.session().content;
    final original = (await content.ready).pageCoverage;
    final other = ConversationFixture();
    await other.open(initial: baseline(1, before: 'older', hasOlder: true));
    final foreign = (await other.session().content.ready).pageCoverage;
    expect(
      () => content.openScope(generation: 1, coverage: foreign),
      throwsA(isA<ConversationContinuityError>()),
    );
    final independent = content.openScope(generation: 1)!;
    expect(independent.pageCoverage, isNull);
    await independent.close();
    await feed.deliver(
      ConversationUpdateEvent(
        update: ConversationResync(
          subscriptionId: 'sub',
          reason: ConversationResyncReason.unavailable,
          baseline: baseline(2, before: 'older', hasOlder: true),
        ),
      ),
    );
    expect(
      () => content.openScope(generation: 1, coverage: original),
      throwsA(isA<ConversationContinuityError>()),
    );
    final resynced = (await content.ready).pageCoverage;
    content.refresh();
    await fixture.open(
      index: 1,
      initial: baseline(
        3,
        subscriptionId: 'new-sub',
        before: 'older',
        hasOlder: true,
      ),
    );
    expect(
      () => content.openScope(generation: 1, coverage: resynced),
      throwsA(isA<ConversationContinuityError>()),
    );
    expect(fixture.transport.opens, hasLength(2));
    await fixture.close();
    expect(content.openScope(generation: 1, coverage: original), isNull);
    await other.close();
  });

  test('qualified concurrent pages commit only their captured ticket and retirement still joins native work', () async {
    final fixture = ConversationFixture();
    final feed = await fixture.open(
      initial: baseline(
        1,
        items: [timelineItem(1, id: 'a', ordinal: 5)],
        before: 'older',
        hasOlder: true,
      ),
    );
    final content = fixture.session().content;
    final scope = content.openScope(
      generation: 1,
      coverage: (await content.ready).pageCoverage,
    )!;
    final replies = List.generate(3, (_) => Completer<ConversationPage>());
    var calls = 0;
    feed.onPage = (_, _) => replies[calls++].future;
    final first = scope.page(before: 'older');
    final failedFirst = expectLater(
      first,
      throwsA(isA<ConversationContinuityError>()),
    );
    final second = scope.page(before: 'older');
    replies[1].complete(
      ConversationPage(
        items: [timelineItem(1, id: 'b', ordinal: 4)],
        before: 'earlier',
        hasOlder: true,
      ),
    );
    await second;
    final committed = scope.pageCoverage;
    replies[0].complete(
      ConversationPage(
        items: [timelineItem(1, id: 'c', ordinal: 3)],
        before: null,
        hasOlder: false,
      ),
    );
    await failedFirst;
    expect(scope.pageCoverage, same(committed));
    await expectLater(
      scope.page(before: 'older'),
      throwsA(isA<ConversationContinuityError>()),
    );
    expect(
      calls,
      2,
      reason: 'Wrong cursor is rejected before native admission',
    );
    final pending = scope.page(before: 'earlier');
    final stale = expectLater(pending, throwsA(isA<StaleConversationScope>()));
    scope.retire();
    expect((await scope.close(deadline: DateTime.now())).complete, isFalse);
    var joined = false;
    final closing = scope.close().then((report) {
      joined = true;
      return report;
    });
    expect(joined, isFalse);
    replies[2].complete(
      ConversationPage(
        items: [timelineItem(1, id: 'c', ordinal: 3)],
        before: null,
        hasOlder: false,
      ),
    );
    await stale;
    expect((await closing).complete, isTrue);
    expect(scope.pageCoverage, same(committed));
    await fixture.close();
  });
}
