import 'dart:async';

import 'package:anywork/src/domain/models/timeline_commands.dart';
import 'package:anywork/src/presentation/view_models/timeline_session_owner.dart';
import 'package:anywork/src/features/conversation/timeline/state/timeline_display_unit.dart';
import 'package:anywork_client/studio_client.dart';
import 'package:flutter_chat_core/flutter_chat_core.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/chat_fixtures.dart';

// These tests exercise the presentation owner with the real Flyer controller.
// SDK transport/ACK and native-reader lifecycles have their own integration tests;
// the doubles here only expose explicit completion and page handoff barriers.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final failClose in [false, true]) {
    test(
      'group body fold revokes synchronously and retains original IO/close responsibility (failure: $failClose)',
      () async {
        final h = _Harness();
        await h.openA([workItem('group')], hasOlder: true);
        final lease = h.owner.lease('a')!;
        final unit =
            lease.controller.messages.single.metadata![timelineDisplayUnitKey]
                as TimelineDisplayUnit;
        final token = Object();
        unit.expansion.setBodyVisible(token, true);
        final generation = unit.expansion.bodyGeneration;
        const reference = ContentRef(
          databaseId: 'database',
          target: ItemPayloadTarget(itemId: 'member-body'),
        );
        final original = unit.expansion.readBody!(
          generation,
          reference,
          const ContentRange(offset: 0, maxBytes: 100),
        );
        final rejected = expectLater(
          original,
          throwsA(isA<StaleConversationScope>()),
        );
        final scope = h.a.scopes.single..failClose = failClose;
        unit.expansion.setBodyVisible(token, false);
        expect(scope.isActive, isFalse);
        expect(scope.closed, isFalse);
        expect(lease.olderCursor, 'before-3');
        scope.bodyRequests.single.complete(
          ContentWindow(
            bytes: const [65],
            offset: 0,
            generation: 'g',
            availableThrough: 1,
            sealed: true,
          ),
        );
        await rejected;
        await Future<void>.delayed(Duration.zero);
        if (failClose) {
          expect(lease.queryCleanupError, isNotNull);
          scope.failClose = false;
          await lease.closeDetailQueries(scope);
        }
        expect(scope.closed, isTrue);
        unit.expansion.setBodyVisible(token, true);
        final freshRead = unit.expansion.readBody!(
          unit.expansion.bodyGeneration,
          reference,
          const ContentRange(offset: 0, maxBytes: 100),
        );
        final fresh = h.a.scopes.last;
        expect(fresh, isNot(same(scope)));
        fresh.bodyRequests.single.complete(
          ContentWindow(
            bytes: const [66],
            offset: 0,
            generation: 'fresh',
            availableThrough: 1,
            sealed: true,
          ),
        );
        expect((await freshRead).bytes, [66]);
        unit.expansion.setBodyVisible(token, false);
        expect((await h.owner.close()).complete, isTrue);
      },
    );
  }
  test('selection alone does not attach; first viewport demand attaches only the latest selection', () async {
    final h = _Harness(viewport: false);
    h.owner.select('a');
    h.owner.select('b');
    expect(h.a.consumer, isNull);
    expect(h.b.consumer, isNull);
    expect(h.a.attaches + h.b.attaches, 0);
    h.owner.updateReadDemand(chatDemand);
    expect(h.a.consumer, isNull);
    expect(h.b.consumer, isNotNull);
    await h.b.deliver(chatBatch([_text('b', 1)]));
    expect(h.owner.lease('b')!.controller.messages.single.id, 'b-1');
    await h.owner.close();
  });

  test('visible layout snapshot borrows only the mounted accepted selection and original layout span without reads', () async {
    final h = _Harness(viewport: false);
    final leases = <TimelineDisplayLease>[];
    addTearDown(() async {
      for (final lease in leases) {
        if (lease.isMounted) unawaited(lease.unbind());
      }
      expect((await h.owner.close()).complete, isTrue);
    });
    expect(h.owner.visibleLayoutSnapshot, isNull);
    h.owner.noteVisibleSelection('a');
    h.owner.select('a');
    final waitingSource = h.owner.source.value;
    expect(h.owner.visibleLayoutSnapshot, isNull);
    expect(h.owner.visibleLayoutSnapshot, isNull);
    expect(h.owner.source.value, same(waitingSource));
    expect(h.a.consumer, isNull);
    expect(h.a.demands, isEmpty);
    expect(h.a.attaches + h.b.attaches, 0);
    expect(h.a.scopes, isEmpty);
    expect(h.b.scopes, isEmpty);

    h.owner.updateReadDemand(chatDemand);
    await h.a.deliver(chatBatch([_text('a', 1)], before: 'before-3'));
    final first = h.owner.lease('a')!;
    leases.add(first);
    expect(first.isMounted, isFalse);
    expect(h.owner.visibleLayoutSnapshot, isNull);
    h.owner.recordContentLayout(first, 'a-1', h.owner.monotonicMicros);
    expect(first.firstContentLayout, isNull);
    first.bind();
    final controller = first.controller;
    final message = controller.messages.single;
    final consumer = h.a.consumer;
    final source = h.owner.source.value;
    void expectOriginalResources() {
      expect(h.owner.source.value, same(source));
      expect(h.owner.lease('a'), same(first));
      expect(first.controller, same(controller));
      expect(controller.messages.single, same(message));
      expect(first.isMounted, isTrue);
      expect(first.olderCursor, 'before-3');
      expect(first.hasOlder, isTrue);
      expect(first.demand, same(chatDemand));
      expect(
        (first.appliedSets, first.appliedPrepends, first.appliedAppends),
        (1, 0, 0),
      );
      expect(h.a.consumer, same(consumer));
      expect(h.a.attaches, 1);
      expect(h.a.demands, [chatDemand]);
      expect(h.a.refreshes, 0);
      expect(
        h.a.scopes,
        isEmpty,
        reason: 'A snapshot must not open a query or load an older page',
      );
      expect(h.b.attaches, 0);
      expect(h.b.scopes, isEmpty);
    }

    final pending = h.owner.visibleLayoutSnapshot!;
    expect(pending.threadId, 'a');
    expect(pending.selectionId, first.selectionId);
    expect(pending.generation, first.generation);
    expect(pending.firstContentLayout, isNull);
    expect(h.owner.visibleLayoutSnapshot, pending);
    expect(first.firstContentLayout, isNull);
    expectOriginalResources();
    final completedMicros = h.owner.monotonicMicros;
    h.owner.recordContentLayout(first, 'a-1', completedMicros);
    final observed = h.owner.visibleLayoutSnapshot!;
    final span = observed.firstContentLayout!;
    expect(span, same(first.firstContentLayout));
    expect(span.selectionId, pending.selectionId);
    expect(span.generation, pending.generation);
    expect(span.itemId, 'a-1');
    expect(span.selectionStartedMicros, first.selectionStartedMicros);
    expect(span.layoutCompletedMicros, completedMicros);
    expect(h.owner.visibleLayoutSnapshot, observed);
    expectOriginalResources();

    final released = first.unbind();
    expect(h.owner.visibleLayoutSnapshot, isNull);
    first.bind();
    expect(h.owner.visibleLayoutSnapshot!.firstContentLayout, same(span));
    // Visible selection may change before its next Set is admitted. Even an
    // A -> B -> A notification must not lend the first A's observed span.
    h.owner.noteVisibleSelection('b');
    expect(first.isMounted, isTrue);
    expect(h.owner.visibleLayoutSnapshot, isNull);
    h.owner.noteVisibleSelection('a');
    expect(h.owner.lease('a'), same(first));
    expect(h.owner.visibleLayoutSnapshot, isNull);
    await h.a.deliver(chatBatch([_text('a', 2)], before: 'new-before'));
    final next = h.owner.lease('a')!;
    leases.add(next);
    expect(first.isRetired, isTrue);
    expect(first.isReleased, isFalse);
    expect(h.owner.visibleLayoutSnapshot, isNull);
    next.bind();
    final nextPending = h.owner.visibleLayoutSnapshot!;
    expect(nextPending.threadId, 'a');
    expect(nextPending.generation, greaterThan(pending.generation));
    expect(nextPending.selectionId, greaterThan(pending.selectionId));
    expect(nextPending.firstContentLayout, isNull);
    h.owner.recordContentLayout(first, 'a-1', h.owner.monotonicMicros);
    expect(h.owner.visibleLayoutSnapshot, nextPending);
    h.owner.recordContentLayout(next, 'a-2', h.owner.monotonicMicros);
    final nextSpan = h.owner.visibleLayoutSnapshot!.firstContentLayout!;
    expect(nextSpan, same(next.firstContentLayout));
    expect(nextSpan, isNot(same(span)));
    expect(nextSpan.itemId, 'a-2');
    expect(nextSpan.selectionId, nextPending.selectionId);
    expect(nextSpan.generation, nextPending.generation);
    expect(h.a.demands, [chatDemand]);
    expect(h.a.attaches, 1);
    expect(h.a.scopes, isEmpty);
    unawaited(first.unbind());
    await released;
    expect(
      first.isReleased,
      isTrue,
      reason: 'Keeping the returned record/span must not retain a lease',
    );
    final retiringNext = next.retire();
    expect(next.isMounted, isTrue);
    expect(next.isRetired, isTrue);
    expect(
      h.owner.visibleLayoutSnapshot,
      isNull,
      reason: 'An observed lease loses snapshot eligibility before unmount',
    );
    unawaited(next.unbind());
    await retiringNext;
    expect(next.isReleased, isTrue);
  });

  for (final phase in [
    TimelineConnectionPhase.idle,
    TimelineConnectionPhase.ready,
  ]) {
    test(
      'reentrant $phase selection retains only the final consumer',
      () async {
        final h = _Harness();
        var switched = false;
        final observation = h.owner.source.watch((state) {
          if (!switched &&
              state?.threadId == 'a' &&
              state?.connection == phase) {
            switched = true;
            h.owner.select('b');
          }
        });
        addTearDown(observation.cancel);
        h.owner.select('a');
        expect(switched, isTrue);
        expect(h.owner.source.value?.threadId, 'b');
        expect(h.a.consumer, isNull);
        expect(h.b.consumer, isNotNull);
        expect(h.a.state.observerCount, 0);
        expect(h.b.state.observerCount, 1);
        h.owner.select(null);
        expect(h.b.consumer, isNull);
        h.owner.select('b');
        await h.b.deliver(chatBatch([_text('b', 1)]));
        expect(h.owner.lease('b')!.controller.messages.single.id, 'b-1');
        expect((await h.owner.close()).complete, isTrue);
        expect(h.a.consumer, isNull);
        expect(h.b.consumer, isNull);
        expect(h.a.state.observerCount + h.b.state.observerCount, 0);
      },
    );
  }

  test(
    'reentrant binding A to B to A releases the provisional consumer',
    () async {
      final h = _Harness();
      h.a.onAttach = () {
        h.a.onAttach = null;
        h.owner.select('b');
        h.owner.select('a');
      };
      h.owner.select('a');
      expect(h.owner.source.value?.threadId, 'a');
      expect(h.owner.source.value?.connectionError, isNull);
      expect(h.a.consumer, isNotNull);
      expect(h.b.consumer, isNull);
      await h.a.deliver(chatBatch([_text('a', 1)]));
      expect(h.owner.lease('a')!.controller.messages.single.id, 'a-1');
      expect((await h.owner.close()).complete, isTrue);
      expect(h.a.consumer, isNull);
      expect(h.b.consumer, isNull);
      expect(h.a.state.observerCount + h.b.state.observerCount, 0);
    },
  );

  test('reentrant detach cannot retire the newly selected display', () async {
    final h = _Harness();
    await h.openA([_text('a', 1)]);
    final previous = h.owner.lease('a')!;
    h.a.onDetach = () {
      h.a.onDetach = null;
      h.owner.select('b');
    };
    h.owner.select(null);
    expect(h.owner.source.value?.threadId, 'b');
    expect(h.a.consumer, isNull);
    expect(h.b.consumer, isNotNull);
    await h.b.deliver(chatBatch([_text('b', 1)]));
    expect(h.owner.lease('b')!.controller.messages.single.id, 'b-1');
    await previous.released;
    expect((await h.owner.close()).complete, isTrue);
    expect(h.a.consumer, isNull);
    expect(h.b.consumer, isNull);
  });

  test(
    'reentrant close during binding joins the provisional consumer',
    () async {
      final h = _Harness();
      late Future<CloseReport> closing;
      h.a.onAttach = () {
        closing = h.owner.close();
        h.owner.select('b');
      };
      h.owner.select('a');
      expect((await closing).complete, isTrue);
      expect(h.owner.source.value, isNull);
      expect(h.a.consumer, isNull);
      expect(h.b.consumer, isNull);
      expect(h.a.state.observerCount + h.b.state.observerCount, 0);
    },
  );

  test(
    'reentrant close publication shares the mounted display obligation',
    () async {
      final h = _Harness();
      await h.openA([_text('a', 1)]);
      final lease = h.owner.lease('a')!..bind();
      late Future<CloseReport> nested;
      final observation = h.owner.source.watch((state) {
        if (state == null) nested = h.owner.close(deadline: DateTime.utc(2000));
      });
      addTearDown(observation.cancel);
      final closing = h.owner.close(deadline: DateTime.utc(2000));
      expect(nested, same(closing));
      final report = await nested;
      expect(report.complete, isFalse);
      expect(report.unresolved.single.owner, 'timeline-display:a');
      expect(lease.isReleased, isFalse);
      await lease.unbind();
      expect((await h.owner.close()).complete, isTrue);
    },
  );

  test('reentrant close from detach retains the old mounted display', () async {
    final h = _Harness();
    await h.openA([_text('a', 1)]);
    final lease = h.owner.lease('a')!..bind();
    late Future<CloseReport> closing;
    h.a.onDetach = () {
      h.a.onDetach = null;
      closing = h.owner.close(deadline: DateTime.utc(2000));
    };
    h.owner.select('b');
    final report = await closing;
    expect(report.complete, isFalse);
    expect(report.unresolved.single.owner, 'timeline-display:a');
    expect(h.owner.source.value, isNull);
    expect(h.b.consumer, isNull);
    expect(lease.isReleased, isFalse);
    await lease.unbind();
    expect((await h.owner.close()).complete, isTrue);
  });

  test('Set admits a message without synthesizing timestamps or a completion cursor', () async {
    final h = _Harness();
    h.owner.select('a');
    final atom = _text('a', 1);
    await h.a.deliver(chatBatch([atom]));
    final lease = h.owner.lease('a')!;
    expect(lease.controller.messages.single.id, atom.id);
    expect(lease.controller.messages, hasLength(1));
    expect(h.a.attaches, 1);
    expect(h.a.refreshes, 0);
    expect((await h.owner.close()).complete, isTrue);
  });

  test(
    'reading and return-to-latest preserve the consumer and loaded window',
    () async {
      final h = _Harness();
      await h.openA([_text('a', 1)]);
      final lease = h.owner.lease('a')!;
      await h.owner.dispatch('a', const TimelineEnterHistory());
      await h.a.deliver(
        chatBatch([_text('a', 2)], placement: ChatPlacement.append),
      );
      expect(h.owner.lease('a'), same(lease));
      expect(lease.loadedCount, 2);
      expect(h.owner.source.value?.hasNewOutput, isTrue);
      await h.owner.returnToLive('a');
      expect(h.owner.lease('a'), same(lease));
      expect(lease.loadedCount, 2);
      expect(h.owner.source.value?.mode, TimelineDisplayMode.live);
      expect(h.owner.source.value?.hasNewOutput, isFalse);
      expect(h.a.attaches, 1);
      expect(h.a.refreshes, 0);
      await h.owner.close();
    },
  );

  test(
    'connection/save notifications perform no historical controller operation',
    () async {
      final h = _Harness();
      await h.openA([_text('a', 1)]);
      final lease = h.owner.lease('a')!;
      final operations = <ChatOperation>[];
      final observed = lease.controller.operationsStream.listen(operations.add);
      h.a.state.publish(const ChatReconnecting('a', error: 'offline'));
      h.a.state.publish(const ChatReady('a', true));
      await Future<void>.delayed(Duration.zero);
      expect(operations, isEmpty);
      expect(lease.loadedCount, 1);
      await observed.cancel();
      await h.owner.close();
    },
  );

  test('pending older read does not hold completion acceptance or require a ready feed', () async {
    final h = _Harness();
    await h.openA([_text('a', 3)], hasOlder: true);
    final lease = h.owner.lease('a')!;
    h.a.state.publish(const ChatFailed('a', error: 'offline'));
    final loading = h.owner.loadOlder('a', generation: lease.generation);
    final scope = h.a.scopes.single;
    await scope.requested.future;
    await h.a.deliver(
      chatBatch([_text('a', 4)], placement: ChatPlacement.append),
    );
    expect(lease.loadedCount, 2);
    scope.reply.complete(
      ChatBatch(
        placement: ChatPlacement.prepend,
        entries: ([
          _text('a', 1),
          _text('a', 2),
        ]).map(ItemChatEntry.new).toList(),
        before: 'before-1',
      ),
    );
    await loading;
    expect(lease.loadedCount, 4);
    expect(lease.controller.messages.map((message) => message.id), [
      'a-1',
      'a-2',
      'a-3',
      'a-4',
    ]);
    expect(lease.olderCursor, 'before-1');
    expect(h.owner.source.value?.isLoadingOlder, isFalse);
    expect(h.a.attaches, 1);
    await h.owner.close();
  });

  test('A to B to A rejects a page from the first A generation', () async {
    final h = _Harness();
    await h.openA([_text('a', 3)], hasOlder: true);
    final first = h.owner.lease('a')!;
    final oldPage = h.owner.loadOlder('a', generation: first.generation);
    final scope = h.a.scopes.single;
    await scope.requested.future;
    h.owner.select('b');
    await h.b.deliver(chatBatch([_text('b', 1)]));
    h.owner.select('a');
    await h.a.deliver(chatBatch([_text('a', 10)]));
    final latest = h.owner.lease('a')!;
    expect(latest, isNot(same(first)));
    scope.reply.complete(
      ChatBatch(
        placement: ChatPlacement.prepend,
        entries: ([_text('a', 1)]).map(ItemChatEntry.new).toList(),
        before: null,
      ),
    );
    await oldPage;
    expect(h.owner.lease('a'), same(latest));
    expect(latest.controller.messages.single.id, 'a-10');
    await first.released;
    await h.owner.close();
  });

  test('new Set retires the old display and its query scopes', () async {
    final h = _Harness();
    await h.openA([_text('a', 1)]);
    final first = h.owner.lease('a')!;
    final scope = first.openDetailQueries()!;
    await h.a.deliver(chatBatch([_text('a', 7)]));
    expect(scope.isActive, isFalse);
    final next = h.owner.lease('a')!;
    expect(next.generation, greaterThan(first.generation));
    expect(next.controller.messages.single.id, 'a-7');
    expect(h.a.attaches, 1);
    expect(h.a.refreshes, 0);
    await first.released;
    await h.owner.close();
  });

  for (final returnToA in [false, true]) {
    test(
      'component await selection ${returnToA ? 'A-B-A' : 'A-B'} never publishes old Append state',
      () async {
        final h = _Harness();
        await h.openA([_text('a', 1)]);
        await h.owner.dispatch('a', const TimelineEnterHistory());
        final old = h.owner.lease('a')!..bind();
        var switched = false;
        final operations = old.controller.operationsStream.listen((_) {
          if (switched) return;
          switched = true;
          h.owner.select('b');
          if (returnToA) h.owner.select('a');
        });
        addTearDown(operations.cancel);
        await h.a.deliver(
          chatBatch([_text('a', 2)], placement: ChatPlacement.append),
        );
        expect(
          switched,
          isTrue,
          reason:
              'selection must run from the real controller operation stream',
        );
        expect(old.isRetired, isTrue);
        expect(
          old.isReleased,
          isFalse,
          reason: 'mounted subtree still owns the old controller',
        );
        expect(h.owner.source.value?.threadId, returnToA ? 'a' : 'b');
        expect(h.owner.source.value?.hasNewOutput, isFalse);
        final target = returnToA ? h.a : h.b;
        await target.deliver(chatBatch([_text(returnToA ? 'a' : 'b', 10)]));
        final next = h.owner.lease(returnToA ? 'a' : 'b')!;
        expect(next, isNot(same(old)));
        expect(next.controller.messages.single.id, returnToA ? 'a-10' : 'b-10');
        await old.unbind();
        expect(old.isReleased, isTrue);
        await h.owner.close();
      },
    );
  }

  for (final failOld in [false, true]) {
    test(
      'late old ${failOld ? 'error' : 'success'} and finally preserve new A loading state',
      () async {
        final h = _Harness();
        await h.openA([_text('a', 3)], hasOlder: true);
        final old = h.owner.lease('a')!;
        final oldLoad = h.owner.loadOlder('a', generation: old.generation);
        final oldScope = h.a.scopes.single;
        await oldScope.requested.future;
        h.owner.select('b');
        h.owner.select('a');
        await h.a.deliver(chatBatch([_text('a', 10)], before: 'new-before'));
        final next = h.owner.lease('a')!;
        final newLoad = h.owner.loadOlder('a', generation: next.generation);
        final newScope = h.a.scopes.last;
        await newScope.requested.future;
        if (failOld) {
          oldScope.reply.completeError(StateError('old failure'));
        } else {
          oldScope.reply.complete(
            chatBatch([_text('a', 1)], placement: ChatPlacement.prepend),
          );
        }
        await oldLoad;
        expect(h.owner.lease('a'), same(next));
        expect(next.controller.messages.single.id, 'a-10');
        expect(next.olderCursor, 'new-before');
        expect(h.owner.source.value?.olderError, isNull);
        expect(
          h.owner.source.value?.isLoadingOlder,
          isTrue,
          reason: 'old finally cannot clear the new request',
        );
        newScope.reply.complete(
          chatBatch([_text('a', 9)], placement: ChatPlacement.prepend),
        );
        await newLoad;
        expect(next.controller.messages.map((message) => message.id), [
          'a-9',
          'a-10',
        ]);
        expect(h.owner.source.value?.isLoadingOlder, isFalse);
        await old.released;
        await h.owner.close();
      },
    );
  }

  test('Append without an active Set is rejected', () async {
    final h = _Harness();
    h.owner.select('a');
    await expectLater(
      h.a.deliver(chatBatch([_text('a', 3)], placement: ChatPlacement.append)),
      throwsA(isA<ConversationContinuityError>()),
    );
    expect(h.owner.lease('a'), isNull);
    await h.owner.close();
  });

  test(
    'page failures preserve the display and retry the same atomic boundary',
    () async {
      final h = _Harness();
      await h.openA([_text('a', 3)], hasOlder: true);
      final lease = h.owner.lease('a')!;
      final loading = h.owner.loadOlder('a', generation: lease.generation);
      final scope = h.a.scopes.single;
      scope.reply.completeError(StateError('read failed'));
      await loading;
      expect(h.owner.source.value?.olderError, isA<StateError>());
      expect(lease.olderCursor, 'before-3');
      expect(lease.loadedCount, 1);
      scope.reply = Completer<ChatBatch>();
      final retry = h.owner.retryOlder('a', generation: lease.generation);
      scope.reply.complete(
        ChatBatch(
          placement: ChatPlacement.prepend,
          entries: ([_text('a', 2)]).map(ItemChatEntry.new).toList(),
          before: null,
        ),
      );
      await retry;
      expect(lease.loadedCount, 2);
      expect(h.owner.source.value?.olderError, isNull);
      expect(scope.boundaries, ['before-3', 'before-3']);
      await h.owner.close();
    },
  );

  test('close waits for accepted reads and real subtree unbind, retaining retry responsibility', () async {
    final h = _Harness();
    await h.openA([_text('a', 3)], hasOlder: true);
    final lease = h.owner.lease('a')!;
    lease.bind();
    final loading = h.owner.loadOlder('a', generation: lease.generation);
    final scope = h.a.scopes.single;
    await scope.requested.future;
    final closing = h.owner.close(
      deadline: DateTime.now().add(const Duration(milliseconds: 15)),
    );
    expect(h.owner.source.value, isNull);
    expect(h.owner.close(), same(closing));
    final report = await closing;
    expect(report.complete, isFalse);
    expect(lease.isReleased, isFalse);
    expect(scope.isActive, isFalse);
    scope.reply.complete(
      ChatBatch(
        placement: ChatPlacement.prepend,
        entries: const [],
        before: null,
      ),
    );
    await loading;
    await lease.unbind();
    expect(lease.isReleased, isTrue);
    expect((await h.owner.close()).complete, isTrue);
  });

  test(
    'failed native reader close keeps the lease until a successful retry',
    () async {
      final h = _Harness();
      await h.openA([_text('a', 1)]);
      final lease = h.owner.lease('a')!;
      final scope = lease.openDetailQueries()! as _Scope;
      scope.failClose = true;
      final report = await h.owner.close(
        deadline: DateTime.now().add(const Duration(milliseconds: 15)),
      );
      expect(report.complete, isFalse);
      expect(lease.queryCleanupError, isNotNull);
      expect(lease.isReleased, isFalse);
      scope.failClose = false;
      expect((await h.owner.close()).complete, isTrue);
      expect(lease.isReleased, isTrue);
    },
  );
}

TimelineItem _text(String thread, int seq) =>
    chatMessage('$thread-$seq', body: 'body-$seq', completionSeq: seq);

final class _Harness {
  _Harness({bool viewport = true}) {
    repository.sessions['a'] = _Session('a', a);
    repository.sessions['b'] = _Session('b', b);
    owner = TimelineSessionOwner(client: _Client(repository));
    if (viewport) owner.updateReadDemand(chatDemand);
  }
  final a = _Content('a');
  final b = _Content('b');
  final repository = _Repository();
  late final TimelineSessionOwner owner;
  Future<void> openA(List<TimelineItem> items, {bool hasOlder = false}) async {
    owner.select('a');
    await a.deliver(chatBatch(items, before: hasOlder ? 'before-3' : null));
  }
}

final class _Client extends Fake implements AnyworkClient {
  _Client(this.conversations);
  @override
  final ConversationRepository conversations;
}

final class _Repository extends Fake implements ConversationRepository {
  final sessions = <String, ConversationSession>{};
  @override
  ConversationSession? existingSession(String threadId) => sessions[threadId];
}

final class _Session extends Fake implements ConversationSession {
  _Session(this.threadId, this.content);
  @override
  final String threadId;
  @override
  final ConversationContent content;
}

final class _Content extends Fake implements ConversationContent {
  _Content(this.threadId) : state = LatestValue(ChatReady(threadId, true));
  @override
  final String threadId;
  @override
  final LatestValue<ChatUiState<bool>> state;
  ConversationBatchConsumer? consumer;
  void Function()? onAttach;
  void Function()? onDetach;
  int attaches = 0;
  int refreshes = 0;
  final demands = <ReadDemand>[];
  final scopes = <_Scope>[];
  final payloads = <String, List<int>>{};
  @override
  Observation attachConsumer(
    ConversationBatchConsumer value, {
    required ReadDemand demand,
  }) {
    if (consumer != null) throw StateError('duplicate consumer');
    attaches++;
    demands.add(demand);
    consumer = value;
    onAttach?.call();
    return _Observation(() {
      if (identical(consumer, value)) consumer = null;
      onDetach?.call();
    });
  }

  Future<void> deliver(ChatBatch batch) => consumer!.applyBatch(batch);
  @override
  void refresh() => refreshes++;
  @override
  ConversationQueryScope openScope({required int generation}) {
    final scope = _Scope(threadId, generation, consumer!)..payloads = payloads;
    scopes.add(scope);
    return scope;
  }
}

final class _Observation implements Observation {
  _Observation(this.onCancel);
  final void Function() onCancel;
  @override
  bool isCancelled = false;
  @override
  bool isPaused = false;
  @override
  void pause() => isPaused = true;
  @override
  void resume() => isPaused = false;
  @override
  void cancel() {
    if (isCancelled) return;
    isCancelled = true;
    onCancel();
  }
}

final class _Scope extends Fake implements ConversationQueryScope {
  _Scope(this.threadId, this.generation, this.consumer);
  final ConversationBatchConsumer consumer;
  @override
  final String threadId;
  @override
  final int generation;
  @override
  bool isActive = true;
  bool failClose = false;
  bool closed = false;
  int closeCalls = 0;
  final bodyRequests = <Completer<ContentWindow>>[];
  Map<String, List<int>> payloads = const {};
  @override
  Future<ContentWindow> readContent({
    required ContentRef reference,
    required ContentRange range,
  }) {
    if (reference.target case ItemPayloadTarget(:final itemId)
        when payloads.containsKey(itemId)) {
      final bytes = payloads[itemId]!;
      return Future.value(
        ContentWindow(
          offset: range.offset,
          bytes: bytes.skip(range.offset).take(range.maxBytes).toList(),
          generation: 'frozen',
          availableThrough: bytes.length,
          sealed: true,
        ),
      );
    }
    final request = Completer<ContentWindow>();
    bodyRequests.add(request);
    _reading = request.future.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    return request.future;
  }

  final requested = Completer<void>();
  Completer<ChatBatch> reply = Completer<ChatBatch>();
  Future<void>? _reading;
  final boundaries = <String?>[];
  @override
  Future<ChatBatch> loadOlder({
    required String before,
    required ReadDemand demand,
  }) {
    boundaries.add(before);
    if (!requested.isCompleted) requested.complete();
    // Match the SDK boundary: resolve only after the captured consumer admits
    // the batch. Retired scopes never redirect a page into a later consumer.
    final result = reply.future.then((batch) async {
      if (isActive) await consumer.applyBatch(batch);
      return batch;
    });
    _reading = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }

  @override
  void retire() => isActive = false;
  @override
  Future<CloseReport> close({DateTime? deadline}) async {
    closeCalls++;
    retire();
    await _reading;
    if (failClose) throw StateError('native close failed');
    closed = true;
    return CloseReport();
  }
}
