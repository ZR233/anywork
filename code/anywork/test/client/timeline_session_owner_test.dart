import 'dart:async';

import 'package:anywork/src/domain/models/timeline_commands.dart';
import 'package:anywork/src/presentation/view_models/timeline_session_owner.dart';
import 'package:anywork_client/studio_client.dart';
import 'package:flutter_chat_core/flutter_chat_core.dart';
import 'package:flutter_test/flutter_test.dart';

// These tests exercise the presentation owner with the real Flyer controller.
// SDK transport/ACK and native-reader lifecycles have their own integration tests;
// the doubles here only expose explicit completion and page handoff barriers.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

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
        await h.b.deliver(
          ConversationBaselineFrame(_baseline('b', [_text('b', 1)])),
        );
        expect(h.owner.lease('b')!.items.single.id, 'b-1');
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
      await h.a.deliver(
        ConversationBaselineFrame(_baseline('a', [_text('a', 1)])),
      );
      expect(h.owner.lease('a')!.items.single.id, 'a-1');
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
    await h.b.deliver(
      ConversationBaselineFrame(_baseline('b', [_text('b', 1)])),
    );
    expect(h.owner.lease('b')!.items.single.id, 'b-1');
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

  test(
    'unknown seal time is still a completed atom and establishes its cursor',
    () async {
      final h = _Harness();
      h.owner.select('a');
      final atom = _text('a', 1);
      await h.a.deliver(ConversationBaselineFrame(_baseline('a', [atom])));
      final lease = h.owner.lease('a')!;
      expect(lease.items.single, same(atom));
      expect(lease.completedCursor?.appendSeq, 1);
      expect(lease.controller.messages, hasLength(1));
      expect(h.a.attaches, 1);
      expect(h.a.refreshes, 0);
      expect((await h.owner.close()).complete, isTrue);
    },
  );

  test(
    'reading and return-to-latest preserve the consumer and loaded window',
    () async {
      final h = _Harness();
      await h.openA([_text('a', 1)]);
      final lease = h.owner.lease('a')!;
      await h.owner.dispatch('a', const TimelineEnterHistory());
      await h.a.deliver(
        ConversationCompletedBatchFrame(_batch('a', [_text('a', 2)])),
      );
      expect(h.owner.lease('a'), same(lease));
      expect(lease.loadedCount, 2);
      expect(lease.completedCursor?.appendSeq, 2);
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
      expect(lease.completedCursor?.appendSeq, 1);
      await observed.cancel();
      await h.owner.close();
    },
  );

  test('pending older read does not hold completion acceptance or require a ready feed', () async {
    final h = _Harness();
    await h.openA([_thinking('a', 3)], hasOlder: true);
    final lease = h.owner.lease('a')!;
    h.a.state.publish(const ChatFailed('a', error: 'offline'));
    final loading = h.owner.loadOlder('a', generation: lease.generation);
    final scope = h.a.scopes.single;
    await scope.requested.future;
    await h.a.deliver(
      ConversationCompletedBatchFrame(_batch('a', [_thinking('a', 4)])),
    );
    expect(lease.loadedCount, 2);
    expect(lease.completedCursor?.appendSeq, 4);
    scope.reply.complete(
      ConversationPage(
        threadId: 'a',
        timelineEpoch: 'epoch',
        items: [_thinking('a', 1), _thinking('a', 2)],
        before: const ConversationQueryCursor('before-1'),
        hasOlder: true,
      ),
    );
    await loading;
    expect(lease.loadedCount, 4);
    expect(lease.controller.messages, hasLength(1));
    expect(lease.presentationFor('a-1')?.anchorItemId, 'a-3');
    expect(lease.completedCursor?.appendSeq, 4);
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
    await h.b.deliver(
      ConversationBaselineFrame(_baseline('b', [_text('b', 1)])),
    );
    h.owner.select('a');
    await h.a.deliver(
      ConversationBaselineFrame(_baseline('a', [_text('a', 10)])),
    );
    final latest = h.owner.lease('a')!;
    expect(latest, isNot(same(first)));
    scope.reply.complete(
      ConversationPage(
        threadId: 'a',
        timelineEpoch: 'epoch',
        items: [_text('a', 1)],
        before: null,
        hasOlder: false,
      ),
    );
    await oldPage;
    expect(h.owner.lease('a'), same(latest));
    expect(latest.items.single.id, 'a-10');
    expect(latest.completedCursor?.appendSeq, 10);
    await first.released;
    await h.owner.close();
  });

  test(
    'epoch reset retires only the old presentation and its query scopes',
    () async {
      final h = _Harness();
      await h.openA([_text('a', 1)]);
      final first = h.owner.lease('a')!;
      final scope = first.openDetailQueries()!;
      await h.a.deliver(
        ConversationResetFrame(
          _baseline('a', [_text('a', 7)], epoch: 'next-epoch'),
        ),
      );
      expect(scope.isActive, isFalse);
      final next = h.owner.lease('a')!;
      expect(next.timelineEpoch, 'next-epoch');
      expect(next.completedCursor?.appendSeq, 7);
      expect(next.items.single.id, 'a-7');
      expect(h.a.attaches, 1);
      expect(h.a.refreshes, 0);
      await first.released;
      await h.owner.close();
    },
  );

  test(
    'a discontinuous completion is rejected without advancing the cursor',
    () async {
      final h = _Harness();
      await h.openA([_text('a', 1)]);
      final lease = h.owner.lease('a')!;
      await expectLater(
        h.a.deliver(
          ConversationCompletedBatchFrame(_batch('a', [_text('a', 3)])),
        ),
        throwsA(isA<ConversationContinuityError>()),
      );
      expect(lease.completedCursor?.appendSeq, 1);
      expect(lease.loadedCount, 1);
      await h.owner.close();
    },
  );

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
      scope.reply = Completer<ConversationPage>();
      final retry = h.owner.retryOlder('a', generation: lease.generation);
      scope.reply.complete(
        ConversationPage(
          threadId: 'a',
          timelineEpoch: 'epoch',
          items: [_text('a', 2)],
          before: null,
          hasOlder: false,
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
      ConversationPage(
        threadId: 'a',
        timelineEpoch: 'epoch',
        items: [],
        before: null,
        hasOlder: false,
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

ConversationItem _text(String thread, int seq) => ConversationItem(
  header: ConversationItemHeader(
    id: '$thread-$seq',
    threadId: thread,
    turnId: 'turn',
    appendSeq: seq,
  ),
  descriptor: ConversationTextDescriptor(
    channel: ThreadTextChannel.finalAnswer,
    attachments: const [],
    outcome: _completed(),
  ),
  source: const ConversationContentSource(),
  fields: [
    ConversationFieldPreview(
      field: const ThreadTextFieldView(),
      text: 'body-$seq',
      totalBytes: 'body-$seq'.length,
    ),
  ],
);

ConversationItem _thinking(String thread, int seq) => ConversationItem(
  header: ConversationItemHeader(
    id: '$thread-$seq',
    threadId: thread,
    turnId: 'turn',
    appendSeq: seq,
  ),
  descriptor: ConversationThinkingDescriptor(outcome: _completed()),
  source: const ConversationContentSource(),
  fields: const [],
);

ConversationContentCompleted _completed() => ConversationContentCompleted(
  CompletedThreadContentView(DateTime.utc(2026)),
);

ConversationBaseline _baseline(
  String thread,
  List<ConversationItem> items, {
  String epoch = 'epoch',
  bool hasOlder = false,
}) => ConversationBaseline(
  subscriptionId: 'subscription',
  timelineEpoch: epoch,
  items: items,
  before: hasOlder
      ? ConversationQueryCursor('before-${items.first.header.appendSeq}')
      : null,
  hasOlder: hasOlder,
  completedCursor: ConversationCompletionCursor(
    timelineEpoch: epoch,
    appendSeq: items.isEmpty ? 0 : items.last.header.appendSeq,
  ),
);

ConversationBatch _batch(String thread, List<ConversationItem> items) =>
    ConversationBatch(
      subscriptionId: 'subscription',
      timelineEpoch: 'epoch',
      fromSeq: items.first.header.appendSeq - 1,
      throughSeq: items.last.header.appendSeq,
      items: items,
    );

final class _Harness {
  _Harness() {
    repository.sessions['a'] = _Session('a', a);
    repository.sessions['b'] = _Session('b', b);
    owner = TimelineSessionOwner(client: _Client(repository));
  }
  final a = _Content('a');
  final b = _Content('b');
  final repository = _Repository();
  late final TimelineSessionOwner owner;
  Future<void> openA(
    List<ConversationItem> items, {
    bool hasOlder = false,
  }) async {
    owner.select('a');
    await a.deliver(
      ConversationBaselineFrame(_baseline('a', items, hasOlder: hasOlder)),
    );
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
  ConversationCompletionConsumer? consumer;
  void Function()? onAttach;
  void Function()? onDetach;
  int attaches = 0;
  int refreshes = 0;
  final scopes = <_Scope>[];
  @override
  Observation attachConsumer(ConversationCompletionConsumer value) {
    if (consumer != null) throw StateError('duplicate consumer');
    attaches++;
    consumer = value;
    onAttach?.call();
    return _Observation(() {
      if (identical(consumer, value)) consumer = null;
      onDetach?.call();
    });
  }

  Future<void> deliver(ConversationContentFrame frame) =>
      consumer!.accept(frame);
  @override
  void refresh() => refreshes++;
  @override
  ConversationQueryScope openScope({
    required String timelineEpoch,
    required int generation,
  }) {
    final scope = _Scope(threadId, timelineEpoch, generation);
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
  _Scope(this.threadId, this.timelineEpoch, this.generation);
  @override
  final String threadId;
  @override
  final String timelineEpoch;
  @override
  final int generation;
  @override
  bool isActive = true;
  bool failClose = false;
  final requested = Completer<void>();
  Completer<ConversationPage> reply = Completer<ConversationPage>();
  Future<void>? _reading;
  final boundaries = <String?>[];
  @override
  Future<ConversationPage> page({ConversationQueryCursor? before, int? limit}) {
    boundaries.add(before?.token);
    if (!requested.isCompleted) requested.complete();
    final result = reply.future;
    _reading = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }

  @override
  void retire() => isActive = false;
  @override
  Future<CloseReport> close({DateTime? deadline}) async {
    retire();
    await _reading;
    if (failClose) throw StateError('native close failed');
    return CloseReport();
  }
}
