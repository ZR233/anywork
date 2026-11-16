import '../support/test_app_lifecycle.dart';

import 'dart:async';

import 'package:anywork/src/app/app_graph.dart';
import 'package:anywork/src/domain/models/timeline_commands.dart';
import 'package:anywork/src/features/conversation/timeline/state/chat_item_presentation.dart';
import 'package:anywork/src/features/conversation/timeline/state/timeline_display_diagnostics.dart';
import 'package:anywork/src/features/conversation/timeline/state/timeline_image_resources.dart';
import 'package:anywork/src/features/conversation/timeline/view_models/timeline_member_controller.dart';
import 'package:anywork/src/presentation/view_models/timeline_session_owner.dart';
import 'package:anywork_client/studio_client.dart';
import 'package:flutter_chat_core/flutter_chat_core.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/chat_fixtures.dart';
import '../support/display_fixtures.dart';
import '../support/mapped_conversation_feed.dart';
import '../support/recording_demo_transport.dart' show timelineReady;
import '../support/test_statistics_feed.dart';
import '../support/unused_account_ports.dart';
import '../../../anywork_client/test/support/directory_feed.dart';
import '../../../anywork_client/test/support/product_topic_owner.dart';

// The real SDK and presentation owner admit batches into the real component.
// The transport supplies only explicit facts and I/O barriers.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('current renderer borrows coexist, unregister independently and retire together', () async {
    final h = _Harness([chatMessage('main')]);
    await h.open();
    final lease = h.lease..bind();
    final work = _CurrentDisplay();
    final output = _CurrentDisplay();
    final unregisterWork = lease.registerCurrentDisplay(work);
    final unregisterOutput = lease.registerCurrentDisplay(output);
    expect(lease.isMounted, isTrue);
    expect(lease.currentDisplays, unorderedEquals([work, output]));
    unregisterOutput();
    expect(lease.currentDisplays, [work]);
    final unregisterOutputAgain = lease.registerCurrentDisplay(output);
    unregisterWork();
    expect(lease.currentDisplays, [output]);
    unregisterWork();
    expect(lease.currentDisplays, [output]);
    lease.registerCurrentDisplay(work);
    output.isCurrent = false;
    expect(lease.currentDisplays, [work]);
    output.isCurrent = true;
    expect(lease.currentDisplays, unorderedEquals([work, output]));
    expect(h.transport.opens, 1, reason: 'borrowing never opens a feed');
    final retiring = lease.retire();
    expect(lease.isRetired, isTrue);
    expect(lease.currentDisplays, isEmpty);
    lease.registerCurrentDisplay(_CurrentDisplay());
    expect(lease.currentDisplays, isEmpty);
    unregisterOutputAgain();
    expect(lease.currentDisplays, isEmpty);
    // Resource registration does not take over renderer teardown.
    expect(work.isCurrent, isTrue);
    expect(output.isCurrent, isTrue);
    await lease.unbind();
    await retiring;
  });

  test('Children close failure releases its display and other side without retiring Main', () async {
    final transport = _ScopedTransport();
    final client = testAnyworkClient(transport: transport, clientId: 'scopes');
    final owner = TimelineSessionOwner(client: client)
      ..updateReadDemand(chatDemand);
    client.conversations.setVisibleThread('thread');
    owner.select('thread');
    await transport.main.accepted(1);
    final mainLease = owner.lease('thread')!;
    final mainCurrent = mainLease.live.value;
    expect(mainCurrent, isNotNull);
    final children = await client.conversations.openRecords(
      threadId: 'thread',
      scope: const ChatScope.conversation(parentId: 'parent'),
      demand: chatDemand,
    );
    final controller = InMemoryChatController();
    final images = TimelineImageResources(threadId: 'thread');
    final adapter = TimelineMemberController(controller);
    final consumer = children.attachConsumer(adapter, demand: chatDemand);
    addTearDown(() async {
      final budget = testCloseBudget();
      transport.childReader.failClose = false;
      consumer.cancel();
      await children.close(budget: budget);
      expect(
        (await client.conversations.retryCleanup(budget: budget)).complete,
        isTrue,
      );
      adapter.dispose();
      images.release();
      controller.dispose();
      expect((await owner.close(budget: budget)).complete, isTrue);
      await client.close(budget: budget);
      final cleaned = await client.retryCleanup(budget: budget);
      expect(
        cleaned.complete,
        isTrue,
        reason: describeTestCloseReport(cleaned),
      );
      await transport.closeFixtureRoot(budget);
    });
    await children.ready;
    await transport.child.accepted(1);
    expect(controller.messages.single.id, 'child');
    expect(mainLease.live.value, same(mainCurrent));
    expect(children.activity.value, isNull);
    expect(
      transport.scopes.last,
      isA<ChatScope>().having((scope) => scope.parentId, 'parentId', 'parent'),
    );
    transport.childReader.failClose = true;
    consumer.cancel();
    final report = await children.close(
      budget: ClientCloseBudget(const Duration(milliseconds: 30)),
    );
    expect(report.complete, isFalse);
    expect(
      transport.child.closed,
      isTrue,
      reason: 'feed cancellation still happens when read close fails',
    );
    expect(transport.child.closeCalls, greaterThanOrEqualTo(1));
    expect(transport.childReader.closeCalls, greaterThanOrEqualTo(1));
    expect(transport.main.closed, isFalse);
    expect(owner.lease('thread'), same(mainLease));
    transport.main.emitTimeline(
      _mainBatch([
        chatMessage('main-next', completionSeq: 2),
      ], placement: ChatPlacement.append),
    );
    await transport.main.accepted(2);
    expect(mainLease.controller.messages.map((message) => message.id), [
      'main',
      'main-next',
    ]);
    transport.childReader.failClose = false;
    expect(
      (await client.conversations.retryCleanup(budget: testCloseBudget()))
          .complete,
      isTrue,
    );
    expect(transport.childReader.closeCalls, greaterThanOrEqualTo(2));
  });

  test(
    'Set owns one controller collection and an opaque older boundary',
    () async {
      final h = _Harness([
        chatMessage('a', completionSeq: 10),
        chatMessage('b', completionSeq: 11),
      ], before: 'opaque:before');
      await h.open();
      final lease = h.lease;
      expect(lease.controller, isA<InMemoryChatController>());
      expect(lease.controller.messages.map((message) => message.id), [
        'a',
        'b',
      ]);
      expect(lease.controller.messages.first.createdAt, isNull);
      expect(lease.loadedCount, 2);
      expect(lease.olderCursor, 'opaque:before');
      expect(lease.hasOlder, isTrue);
      expect(h.transport.opens, 1);
    },
  );

  test('older read is admitted once before return and preserves existing Message identity', () async {
    final h = _Harness([
      chatMessage('c', completionSeq: 1000),
    ], before: 'opaque:before');
    await h.open();
    final lease = h.lease;
    final message = lease.controller.messages.single;
    final operations = <ChatOperation>[];
    final observed = lease.controller.operationsStream.listen(operations.add);
    addTearDown(observed.cancel);
    final loading = h.owner.loadOlder('thread', generation: lease.generation);
    await h.transport.reader.entered.future;
    h.transport.reader.reply.complete(
      _mainBatch([
        chatMessage('a', completionSeq: 10),
        chatMessage('b', completionSeq: 11),
      ], placement: ChatPlacement.prepend),
    );
    await loading;
    await Future<void>.delayed(Duration.zero);
    expect(lease.controller.messages.map((message) => message.id), [
      'a',
      'b',
      'c',
    ]);
    expect(lease.controller.messages.last, same(message));
    expect(
      operations,
      hasLength(1),
      reason: 'loadOlder must not perform a second insert',
    );
    expect(lease.hasOlder, isFalse);
    expect(h.transport.reader.boundaries, ['opaque:before']);
    expect(h.transport.reader.demands, [chatDemand]);
    expect(
      h.transport.opens,
      1,
      reason: 'queries retain the original feed reader',
    );
  });

  test(
    'history mode accepts Append without replacing display or old messages',
    () async {
      final h = _Harness([chatMessage('a')], before: 'older');
      await h.open();
      final lease = h.lease;
      final first = lease.controller.messages.single;
      await h.owner.dispatch('thread', const TimelineEnterHistory());
      await h.append([chatMessage('b', completionSeq: 2)]);
      expect(h.lease, same(lease));
      expect(lease.controller.messages.first, same(first));
      expect(lease.loadedCount, 2);
      expect(
        lease.olderCursor,
        'older',
        reason: 'Append never advances before',
      );
      expect(h.owner.source.value?.hasNewOutput, isTrue);
      await h.owner.returnToLive('thread');
      expect(h.lease, same(lease));
      expect(h.owner.source.value?.hasNewOutput, isFalse);
      expect(h.transport.opens, 1);
    },
  );

  test(
    'mounted lease retains controller ownership until unbind and close retry',
    () async {
      final h = _Harness([chatMessage('a')]);
      h.owner.noteVisibleSelection('thread');
      await h.open();
      final lease = h.lease..bind();
      final controller = lease.controller;
      expect(h.owner.visibleLayoutSnapshot!.firstContentLayout, isNull);
      h.owner.recordContentLayout(lease, 'a', h.owner.monotonicMicros);
      final visible = h.owner.visibleLayoutSnapshot!;
      expect(visible.threadId, 'thread');
      expect(visible.selectionId, lease.selectionId);
      expect(visible.generation, lease.generation);
      expect(visible.firstContentLayout, same(lease.firstContentLayout));
      expect(visible.firstContentLayout, isNotNull);
      expect(h.owner.visibleLayoutSnapshot, visible);
      expect(h.transport.opens, 1);
      expect(h.transport.reader.boundaries, isEmpty);
      expect(h.transport.reader.demands, isEmpty);
      h.client.conversations.setVisibleThread(null);
      final closing = h.owner.close(budget: ClientCloseBudget(Duration.zero));
      expect(h.owner.visibleLayoutSnapshot, isNull);
      expect(h.owner.close(budget: testCloseBudget()), same(closing));
      final mountedReport = await closing;
      expect(mountedReport.complete, isFalse);
      expect(
        mountedReport.unresolved.any(
          (resource) =>
              resource.resourceId == lease.resourceId &&
              resource.owner == 'timeline-display:thread',
        ),
        isTrue,
        reason: describeTestCloseReport(mountedReport),
      );
      expect(lease.isRetired, isTrue);
      expect(lease.isReleased, isFalse);
      expect(lease.controller, same(controller));
      expect(h.owner.lease('thread'), isNull);
      h.owner.recordContentLayout(lease, 'a', h.owner.monotonicMicros);
      expect(h.owner.visibleLayoutSnapshot, isNull);
      expect(lease.firstContentLayout, same(visible.firstContentLayout));
      await lease.unbind();
      expect(lease.isReleased, isTrue);
      expect(lease.loadedCount, 0);
      expect(() => lease.controller, throwsStateError);
      expect((await h.owner.close(budget: testCloseBudget())).complete, isTrue);
      expect(h.owner.visibleLayoutSnapshot, isNull);
    },
  );

  for (final reentryStage in ['retire', 'close']) {
    test(
      'query $reentryStage reentry shares one cleanup through a pending failure',
      () async {
        final h = _Harness([chatMessage('main')]);
        await h.open();
        final lease = h.lease..bind();
        final scope = lease.openDetailQueries()! as ConversationReadScope;
        final error = StateError('original reentrant member failure');
        final stack = StackTrace.current;
        final gate = Completer<void>();
        final member = _CleanupMembers(error, stack, null, stack)
          ..closeGate = gate;
        h.transport.reader.displayMembers = member;
        await scope.openDisplayMembers(
          reference: const DisplayBlockRef(
            databaseId: 'reentry-database',
            blockId: 'work',
          ),
          window: const LatestDisplayMembers(),
          demand: chatDemand,
        );
        final memberId = scope.cleanupReport.unresolved.single.resourceId;
        addTearDown(() async {
          member
            ..onRequestClose = null
            ..onClose = null
            ..recover();
          await scope.close();
          await scope.close();
          await lease.closeDetailQueries(scope);
          final retired = lease.retire();
          await lease.unbind();
          await retired;
        });
        Future<Object?> capture(Future<void> closing) => closing.then<Object?>(
          (_) => null,
          onError: (Object error, StackTrace _) => error,
        );
        final outcomes = <Future<Object?>>[];
        var reentered = false;
        void reenter() {
          if (reentered) return;
          reentered = true;
          outcomes.add(capture(lease.closeDetailQueries(scope)));
        }

        if (reentryStage == 'retire') {
          member.onRequestClose = reenter;
        } else {
          member.onClose = reenter;
        }
        outcomes.add(capture(lease.closeDetailQueries(scope)));
        outcomes.add(capture(lease.closeDetailQueries(scope)));
        expect(reentered, isTrue);
        expect(member.closeCalls, 1);
        expect(member.requestCalls, 2);

        final closing = h.owner.close(budget: ClientCloseBudget(Duration.zero));
        expect(h.owner.close(budget: testCloseBudget()), same(closing));
        final pending = await closing;
        final pendingMember = pending.unresolved.singleWhere(
          (resource) => resource.resourceId == memberId,
        );
        expect(pendingMember.stages.single.pending, isTrue);
        expect(pendingMember.stages.single.error, isNull);
        expect(lease.isReleased, isFalse);
        expect(member.closeCalls, 1);
        expect(member.requestCalls, 2);

        gate.complete();
        final failures = await Future.wait(outcomes);
        expect(failures, hasLength(3));
        for (final failure in failures) {
          expect(failure, isA<CloseReport>());
          _expectCleanupFailure(
            failure! as CloseReport,
            memberId,
            error,
            stack,
            ClientClosePhase.close,
          );
        }
        expect(member.closeCalls, 1);
        member.recover();
        await lease.closeDetailQueries(scope);
        expect(member.closeCalls, 2);
        expect(scope.cleanupReport.complete, isTrue);
        expect(lease.queryCleanupError, isNull);
        expect(
          lease.isReleased,
          isFalse,
          reason: 'successful cleanup cannot replace widget unbind',
        );
        await lease.unbind();
        expect(
          (await h.owner.close(budget: testCloseBudget())).complete,
          isTrue,
        );
        expect(lease.isReleased, isTrue);
      },
    );
  }

  test('native GUI reader close failure stays with its original UI owner after display release', () async {
    final h = _Harness([
      chatMessage('c', completionSeq: 1000),
    ], before: 'older');
    await h.open();
    final lease = h.lease;
    final scope = lease.openDetailQueries()!;
    final original = h.transport.reader;
    final error = StateError('original reader close failure');
    final stack = StackTrace.current;
    original.onClose = (attempt) {
      if (attempt == 1) Error.throwWithStackTrace(error, stack);
      return Future.value();
    };
    h.client.conversations.setVisibleThread(null);
    final failedReader = await h.owner.close(budget: testCloseBudget());
    expect(failedReader.complete, isFalse);
    final readerId = failedReader.unresolved.single.resourceId;
    _expectCleanupFailure(
      failedReader,
      readerId,
      error,
      stack,
      ClientClosePhase.close,
    );
    expect(
      original.closeCalls,
      1,
      reason: 'ordinary join cannot retry a failure it just observed',
    );
    expect(scope.isActive, isFalse);
    expect(lease.isReleased, isTrue);
    final observedAgain = await h.owner.close(budget: testCloseBudget());
    _expectCleanupFailure(
      observedAgain,
      readerId,
      error,
      stack,
      ClientClosePhase.close,
    );
    expect(
      original.closeCalls,
      1,
      reason: 'reobserving the failed attempt is not management retry',
    );
    final report = await h.client.close(
      budget: ClientCloseBudget(const Duration(milliseconds: 30)),
    );
    expect(report.complete, isTrue, reason: describeTestCloseReport(report));
    expect(original.closeCalls, 1);
    expect(
      (await h.owner.retryCleanup(budget: testCloseBudget())).complete,
      isTrue,
    );
    expect(original.closeCalls, 2);
    expect((await h.owner.close(budget: testCloseBudget())).complete, isTrue);
    expect(
      (await h.owner.retryCleanup(budget: testCloseBudget())).complete,
      isTrue,
    );
    expect(
      original.closeCalls,
      2,
      reason: 'a successful original reader is not closed again',
    );
    expect(h.transport.reader, same(original));
    expect(h.transport.opens, 1);
  });

  test(
    'reader retains earlier cleanup failures until a real retry ACK',
    () async {
      final h = _Harness([chatMessage('main')]);
      await h.open();
      final original = h.transport.reader;
      final failures = [
        StateError('first original close'),
        StateError('failed management retry'),
      ];
      final stacks = [StackTrace.current, StackTrace.current];
      original.onClose = (attempt) {
        if (attempt <= failures.length) {
          Error.throwWithStackTrace(failures[attempt - 1], stacks[attempt - 1]);
        }
        return Future.value();
      };
      final first = await h.owner.close(budget: testCloseBudget());
      final identity = first.unresolved.single.resourceId;
      expect(original.closeCalls, 1);
      final retry = await h.owner.retryCleanup(budget: testCloseBudget());
      final observed = await h.owner.close(budget: testCloseBudget());
      for (final report in [retry, observed]) {
        final resource = report.unresolved.single;
        expect(resource.resourceId, identity);
        expect(resource.reason, same(failures.first));
        expect(resource.stages, hasLength(2));
        for (var index = 0; index < failures.length; index++) {
          final stage = resource.stages.singleWhere(
            (stage) => identical(stage.error, failures[index]),
          );
          expect(stage.phase, ClientClosePhase.close);
          expect(stage.stackTrace, same(stacks[index]));
          expect(stage.pending, isFalse);
        }
      }
      expect(original.closeCalls, 2);
      expect(
        (await h.owner.retryCleanup(budget: testCloseBudget())).complete,
        isTrue,
      );
      expect((await h.owner.close(budget: testCloseBudget())).complete, isTrue);
      expect(original.closeCalls, 3);
      expect(h.transport.opens, 1);
    },
  );

  for (final lateFailure in [false, true]) {
    test(
      'reader pending close survives timeout and reentry before late ${lateFailure ? 'failure' : 'ACK'}',
      () async {
        final h = _Harness([chatMessage('main')]);
        await h.open();
        final lease = h.lease..bind();
        final controller = lease.controller;
        final original = h.transport.reader;
        final firstGate = Completer<void>();
        final retryGate = Completer<void>();
        final error = StateError('late original reader failure');
        final stack = StackTrace.current;
        Future<CloseReport>? requestClose;
        Future<CloseReport>? requestRetry;
        Future<CloseReport>? nativeClose;
        Future<CloseReport>? nativeRetry;
        Future<CloseReport>? retryReentry;
        addTearDown(() async {
          original
            ..onRequestClose = null
            ..onClose = null;
          if (!firstGate.isCompleted) firstGate.complete();
          if (!retryGate.isCompleted) retryGate.complete();
          final retired = lease.retire();
          await lease.unbind();
          await retired;
        });
        expect(
          (await h.owner.retryCleanup(budget: testCloseBudget())).complete,
          isTrue,
        );
        expect(lease.isRetired, isFalse);
        expect(
          original.closeCalls,
          0,
          reason: 'retry does not start business retirement',
        );
        original.onRequestClose = () {
          requestClose ??= h.owner.close(
            budget: ClientCloseBudget(Duration.zero),
          );
          requestRetry ??= h.owner.retryCleanup(
            budget: ClientCloseBudget(Duration.zero),
          );
        };
        original.onClose = (attempt) async {
          if (attempt == 1) {
            nativeClose = h.owner.close(
              budget: ClientCloseBudget(Duration.zero),
            );
            nativeRetry = h.owner.retryCleanup(
              budget: ClientCloseBudget(Duration.zero),
            );
            await firstGate.future;
            if (lateFailure) Error.throwWithStackTrace(error, stack);
          } else {
            retryReentry = h.owner.retryCleanup(
              budget: ClientCloseBudget(Duration.zero),
            );
            await retryGate.future;
          }
        };
        final closing = h.owner.close(budget: ClientCloseBudget(Duration.zero));
        expect(requestClose, same(closing));
        expect(h.owner.close(budget: testCloseBudget()), same(closing));
        await original.closeStarted(1);
        expect(nativeClose, same(closing));
        expect(nativeRetry, same(requestRetry));
        final pending = await closing;
        expect((await requestRetry!).complete, isFalse);
        final readerId = pending.unresolved
            .singleWhere(
              (resource) => resource.owner == 'timeline-reader:thread',
            )
            .resourceId;
        final pendingReader = pending.unresolved.singleWhere(
          (resource) => resource.resourceId == readerId,
        );
        expect(pendingReader.stages.single.pending, isTrue);
        expect(pendingReader.stages.single.error, isNull);
        expect(
          (await h.owner.close(budget: ClientCloseBudget(Duration.zero)))
              .complete,
          isFalse,
        );
        expect(
          (await h.owner.retryCleanup(budget: ClientCloseBudget(Duration.zero)))
              .complete,
          isFalse,
        );
        expect(original.closeCalls, 1);
        expect(lease.isReleased, isFalse);
        expect(lease.controller, same(controller));
        await lease.unbind();
        expect(lease.isReleased, isTrue);
        firstGate.complete();
        final late = await h.owner.close(budget: testCloseBudget());
        expect(original.closeCalls, 1);
        if (lateFailure) {
          _expectCleanupFailure(
            late,
            readerId,
            error,
            stack,
            ClientClosePhase.close,
          );
          final retry = h.owner.retryCleanup(
            budget: ClientCloseBudget(Duration.zero),
          );
          expect(h.owner.retryCleanup(budget: testCloseBudget()), same(retry));
          await original.closeStarted(2);
          expect(retryReentry, same(retry));
          final stillPending = await retry;
          _expectCleanupFailure(
            stillPending,
            readerId,
            error,
            stack,
            ClientClosePhase.close,
          );
          expect(stillPending.unresolved.single.stages.single.pending, isTrue);
          final observed = await h.owner.close(
            budget: ClientCloseBudget(Duration.zero),
          );
          _expectCleanupFailure(
            observed,
            readerId,
            error,
            stack,
            ClientClosePhase.close,
          );
          final joining = h.owner.retryCleanup(budget: testCloseBudget());
          expect(
            h.owner.retryCleanup(budget: testCloseBudget()),
            same(joining),
          );
          expect(original.closeCalls, 2);
          retryGate.complete();
          expect((await joining).complete, isTrue);
        } else {
          expect(late.complete, isTrue);
        }
        expect(
          (await h.owner.close(budget: testCloseBudget())).complete,
          isTrue,
        );
        expect(
          (await h.owner.retryCleanup(budget: testCloseBudget())).complete,
          isTrue,
        );
        expect(original.closeCalls, lateFailure ? 2 : 1);
        expect(h.transport.opens, 1);
        expect(h.transport.reader, same(original));
      },
    );
  }

  test(
    'retirement fences new queries and joins an already accepted older read',
    () async {
      final h = _Harness(
        [chatMessage('c', completionSeq: 1000)],
        before: 'older',
        withAppGraph: true,
      );
      await h.open();
      final lease = h.lease;
      final loading = h.owner.loadOlder('thread', generation: lease.generation);
      await h.transport.reader.entered.future;
      final scope = lease.queries! as ConversationReadScope;
      final queryId = scope.cleanupReport.unresolved.single.resourceId;
      expect(queryId, isNot(lease.resourceId));
      h.client.conversations.setVisibleThread(null);
      final pendingRead = await h.owner.close(
        budget: ClientCloseBudget(Duration.zero),
      );
      expect(pendingRead.complete, isFalse);
      expect(
        pendingRead.unresolved.map((resource) => resource.resourceId),
        containsAll([lease.resourceId, queryId]),
        reason: describeTestCloseReport(pendingRead),
      );
      final appReport = await h.graph!.close(
        budget: ClientCloseBudget(Duration.zero),
      );
      for (final report in [pendingRead, appReport]) {
        for (final id in [queryId, lease.resourceId]) {
          final resource = report.unresolved.singleWhere(
            (resource) => resource.resourceId == id,
          );
          expect(
            resource.stages.any(
              (stage) =>
                  stage.phase == ClientClosePhase.consumer && stage.pending,
            ),
            isTrue,
          );
        }
      }
      expect(lease.queries, isNull);
      expect(lease.openDetailQueries(), isNull);
      expect(lease.isReleased, isFalse);
      h.transport.reader.reply.complete(
        _mainBatch([chatMessage('late')], placement: ChatPlacement.prepend),
      );
      await loading;
      expect((await h.owner.close(budget: testCloseBudget())).complete, isTrue);
      expect(scope.cleanupReport.complete, isTrue);
      expect(lease.isReleased, isTrue);
      expect(h.transport.reader.boundaries, ['older']);
    },
  );

  test('query watch and member failures retain identity and stacks through Timeline and AppGraph', () async {
    final h = _Harness([chatMessage('main')], withAppGraph: true);
    await h.open();
    final lease = h.lease;
    final watchScope = lease.openDetailQueries()! as ConversationReadScope;
    final memberScope = lease.openDetailQueries()! as ConversationReadScope;
    final watchError = StateError('original query watch join');
    final watchStack = StackTrace.current;
    final memberError = StateError('original member join');
    final memberStack = StackTrace.current;
    final requestError = StateError('original member stop request');
    final requestStack = StackTrace.current;
    final watch = _CleanupWatch(watchError, watchStack);
    final member = _CleanupMembers(
      memberError,
      memberStack,
      requestError,
      requestStack,
    );
    h.transport.reader
      ..contentWatch = watch
      ..displayMembers = member;
    final subscription = watchScope
        .watchContent(
          reference: const ContentRef(
            databaseId: 'query-database',
            target: ItemPayloadTarget(itemId: 'body'),
          ),
          range: const ContentRange(offset: 0, maxBytes: 256),
        )
        .listen((_) {});
    addTearDown(() async {
      watch.recover();
      member.recover();
      // Join the old failed attempt before explicitly retrying its same handles.
      await watchScope.close();
      await memberScope.close();
      await watchScope.close();
      await memberScope.close();
      expect((await h.owner.close(budget: testCloseBudget())).complete, isTrue);
      await subscription.cancel();
      await watch.dispose();
    });
    await memberScope.openDisplayMembers(
      reference: const DisplayBlockRef(
        databaseId: 'query-database',
        blockId: 'work',
      ),
      window: const LatestDisplayMembers(),
      demand: chatDemand,
    );
    final watchId = watchScope.cleanupReport.unresolved.single.resourceId;
    final memberId = memberScope.cleanupReport.unresolved.single.resourceId;
    expect({watchId, memberId, lease.resourceId}, hasLength(3));

    watchScope.retire();
    await watch.joinStarted.future;
    await expectLater(watch.joining, throwsA(same(watchError)));
    final beforeSnapshot = (
      watch.closeCalls,
      watch.requestCalls,
      member.closeCalls,
    );
    final snapshot = watchScope.cleanupReport;
    expect(watchScope.cleanupReport.unresolved.single.resourceId, watchId);
    expect((
      watch.closeCalls,
      watch.requestCalls,
      member.closeCalls,
    ), beforeSnapshot);
    _expectCleanupFailure(
      snapshot,
      watchId,
      watchError,
      watchStack,
      ClientClosePhase.close,
    );
    expect(
      snapshot.unresolved.single.stages
          .singleWhere((stage) => stage.phase == ClientClosePhase.consumer)
          .pending,
      isTrue,
      reason: 'native join failure cannot hide the unfinished local consumer',
    );

    h.client.conversations.setVisibleThread(null);
    final timelineReport = await h.owner.close(
      budget: ClientCloseBudget(Duration.zero),
    );
    final appReport = await h.graph!.close(
      budget: ClientCloseBudget(Duration.zero),
    );
    for (final report in [timelineReport, appReport]) {
      _expectCleanupFailure(
        report,
        watchId,
        watchError,
        watchStack,
        ClientClosePhase.close,
      );
      _expectCleanupFailure(
        report,
        memberId,
        memberError,
        memberStack,
        ClientClosePhase.close,
      );
      _expectCleanupFailure(
        report,
        memberId,
        requestError,
        requestStack,
        ClientClosePhase.closeRequest,
      );
      final display = report.unresolved.singleWhere(
        (resource) => resource.resourceId == lease.resourceId,
      );
      expect(display.stages.single.pending, isTrue);
      expect(display.stages.single.error, isNull);
    }
    expect(lease.isReleased, isFalse);
    expect(h.transport.reader.watchOpens, 1);
    expect(h.transport.reader.memberOpens, 1);

    watch.cancelGate.complete();
    await expectLater(
      lease.closeDetailQueries(watchScope),
      throwsA(isA<CloseReport>()),
    );
    watch.recover();
    final memberOnly = await h.owner.retryCleanup(
      budget: ClientCloseBudget(Duration.zero),
    );
    expect(
      memberOnly.unresolved.map((resource) => resource.resourceId),
      isNot(contains(watchId)),
    );
    _expectCleanupFailure(
      memberOnly,
      memberId,
      memberError,
      memberStack,
      ClientClosePhase.close,
    );
    expect(lease.isReleased, isFalse);
    expect(lease.queryCleanupError, isNotNull);
    expect(watch.closeCalls, 2);

    member.recover();
    expect(
      (await h.owner.retryCleanup(budget: testCloseBudget())).complete,
      isTrue,
    );
    await lease.released;
    expect(watchScope.cleanupReport.complete, isTrue);
    expect(memberScope.cleanupReport.complete, isTrue);
    expect(lease.queryCleanupError, isNull);
    expect((await h.owner.close(budget: testCloseBudget())).complete, isTrue);
    expect(lease.isReleased, isTrue);
    expect(h.transport.reader.watchOpens, 1);
    expect(h.transport.reader.memberOpens, 1);
  });

  test('live query snapshot removes a resolved watch while a sibling member retries', () async {
    final h = _Harness([chatMessage('main')]);
    await h.open();
    final lease = h.lease;
    final scope = lease.openDetailQueries()! as ConversationReadScope;
    final watch = _CleanupWatch(
      StateError('old watch failure'),
      StackTrace.current,
    )..cancelGate.complete();
    final memberError = StateError('old member failure');
    final member = _CleanupMembers(
      memberError,
      StackTrace.current,
      null,
      StackTrace.current,
    );
    h.transport.reader
      ..contentWatch = watch
      ..displayMembers = member;
    final subscription = scope
        .watchContent(
          reference: const ContentRef(
            databaseId: 'query-database',
            target: ItemPayloadTarget(itemId: 'body'),
          ),
          range: const ContentRange(offset: 0, maxBytes: 256),
        )
        .listen((_) {});
    final watchId = scope.cleanupReport.unresolved.single.resourceId;
    await scope.openDisplayMembers(
      reference: const DisplayBlockRef(
        databaseId: 'query-database',
        blockId: 'work',
      ),
      window: const LatestDisplayMembers(),
      demand: chatDemand,
    );
    final memberId = scope.cleanupReport.unresolved
        .singleWhere((resource) => resource.resourceId != watchId)
        .resourceId;
    addTearDown(() async {
      watch.recover();
      member.recover();
      await scope.close();
      await scope.close();
      expect((await h.owner.close(budget: testCloseBudget())).complete, isTrue);
      await subscription.cancel();
      await watch.dispose();
    });
    await expectLater(
      lease.closeDetailQueries(scope),
      throwsA(isA<CloseReport>()),
    );
    watch.recover();
    member.recover();
    final memberGate = member.closeGate = Completer<void>();
    final retry = lease.closeDetailQueries(scope);
    await subscription.cancel();
    expect(scope.cleanupReport.unresolved.single.resourceId, memberId);
    expect(scope.cleanupReport.unresolved.single.stages.single.pending, isTrue);
    expect(
      scope.cleanupReport.unresolved.single.stages.single.error,
      same(memberError),
    );

    h.client.conversations.setVisibleThread(null);
    final report = await h.owner.close(
      budget: ClientCloseBudget(Duration.zero),
    );
    expect(
      report.unresolved.map((resource) => resource.resourceId),
      isNot(contains(watchId)),
    );
    final pendingMember = report.unresolved.singleWhere(
      (resource) => resource.resourceId == memberId,
    );
    expect(pendingMember.stages.single.pending, isTrue);
    expect(pendingMember.stages.single.error, same(memberError));
    expect(lease.isReleased, isFalse);
    memberGate.complete();
    await retry;
    expect((await h.owner.close(budget: testCloseBudget())).complete, isTrue);
    expect(scope.cleanupReport.complete, isTrue);
    expect(lease.queryCleanupError, isNull);
    expect(lease.isReleased, isTrue);
  });

  test('new Set changes chat identity and releases borrowed image only after unbind', () async {
    final h = _Harness([chatMessage('image-atom')]);
    await h.open();
    final old = h.lease..bind();
    // A mounted attachment connector declares references on the lease; merely
    // loading a message no longer creates a second attachment/item mirror.
    old.imageResources.retainItem('image-atom', const [
      ThreadAttachmentView(
        id: 'image',
        modality: AttachmentModalityView.image,
        mediaType: 'image/png',
        byteSize: 8,
      ),
    ]);
    final resource = old.imageResources.borrow('image');
    final oldKey = old.chatKey;
    h.transport.initial = _mainBatch([chatMessage('reset')]);
    h.owner.refresh('thread');
    await timelineReady(h.owner, 'thread');
    await h.transport.feed.accepted(1);
    final next = h.lease;
    expect(next.chatKey, isNot(oldKey));
    expect(next.scrollController.keepScrollOffset, isFalse);
    expect(next.controller.messages.single.id, 'reset');
    expect(old.isRetired, isTrue);
    expect(old.isReleased, isFalse);
    expect(
      () => resource.retry(() async => throw StateError('must not read')),
      throwsStateError,
    );
    await old.unbind();
    expect(old.isReleased, isTrue);
    expect(h.transport.opens, 2);
  });

  test('Append preserves parsed card and body references without a second collection', () async {
    final h = _Harness([chatMessage('body', body: 'unchanged')]);
    await h.open();
    final original = h.lease.controller.messages.single;
    final card =
        original.metadata![chatItemPresentationKey] as ChatItemPresentation;
    final body = card.body('body');
    await h.append([chatMessage('next', completionSeq: 2)]);
    expect(h.lease.controller.messages.first, same(original));
    expect(
      h.lease.controller.messages.first.metadata![chatItemPresentationKey],
      same(card),
    );
    expect(card.body('body'), same(body));
    expect(card.inlineText('body'), 'unchanged');
  });
}

final class _CurrentDisplay implements TimelineCurrentDisplay {
  @override
  bool isCurrent = true;
  @override
  String? get turnId => 'turn';
  @override
  String? get activityId => 'activity';
  @override
  bool get expanded => false;
  @override
  Iterable<TimelineCurrentCollectionDisplay> get collections => const [];
  @override
  Iterable<TimelineCurrentWindowDisplay> get windows => const [];
}

void _expectCleanupFailure(
  CloseReport report,
  ClientResourceId id,
  Object error,
  StackTrace stack,
  ClientClosePhase phase,
) {
  final resource = report.unresolved.singleWhere(
    (resource) => resource.resourceId == id,
  );
  final stage = resource.stages.singleWhere((stage) => stage.phase == phase);
  expect(stage.error, same(error), reason: describeTestCloseReport(report));
  expect(stage.stackTrace, same(stack));
  if (phase == ClientClosePhase.close) expect(resource.reason, same(error));
}

final class _GraphAccountPorts extends UnusedAccountPorts {}

final class _Harness {
  _Harness(
    List<CompletedEntry> messages, {
    String? before,
    bool withAppGraph = false,
  }) : transport = _LeaseTransport(_mainBatch(messages, before: before)) {
    if (withAppGraph) {
      final accounts = _GraphAccountPorts();
      graph = testAppGraph(
        transport: transport,
        statisticsFeed: const TestStatisticsFeedPort(),
        clientId: 'lease',
        accountFeed: accounts,
        accountConfiguration: accounts,
        accountModels: accounts,
        accountUsage: accounts,
        acpPort: accounts,
      );
      client = graph!.client;
      owner = graph!.timeline;
    } else {
      graph = null;
      client = testAnyworkClient(transport: transport, clientId: 'lease');
      owner = TimelineSessionOwner(client: client);
    }
    owner.updateReadDemand(chatDemand);
    addTearDown(() async {
      final budget = testCloseBudget();
      transport.reader
        ..failClose = false
        ..onRequestClose = null
        ..onClose = null;
      if (!transport.reader.reply.isCompleted) {
        transport.reader.reply.complete(
          _mainBatch([], placement: ChatPlacement.prepend),
        );
      }
      client.conversations.setVisibleThread(null);
      final current = owner.lease('thread');
      if (current?.isMounted ?? false) await current!.unbind();
      final ownerReport = await owner.close(budget: budget);
      if (!ownerReport.complete) {
        expect((await owner.retryCleanup(budget: budget)).complete, isTrue);
      }
      await graph?.close(budget: budget);
      final report = await client.close(budget: budget);
      if (!report.complete) {
        final cleaned = await client.retryCleanup(budget: budget);
        expect(
          cleaned.complete,
          isTrue,
          reason: describeTestCloseReport(cleaned),
        );
      }
      await transport.closeFixtureRoot(budget);
    });
  }
  final _LeaseTransport transport;
  late final AppGraph? graph;
  late final AnyworkClient client;
  late final TimelineSessionOwner owner;
  TimelineDisplayLease get lease => owner.lease('thread')!;
  Future<void> open() async {
    client.conversations.setVisibleThread('thread');
    owner.select('thread');
    await transport.feed.accepted(1);
  }

  Future<void> append(List<CompletedEntry> messages) async {
    final response = transport.feed.deliveredFrames + 1;
    transport.feed.emitTimeline(
      _mainBatch(messages, placement: ChatPlacement.append),
    );
    await transport.feed.accepted(response);
  }
}

abstract class _TimelineTransport extends StudioTransport
    with DirectoryFeedFixture
    implements TimelineTransport, TestLifecycleOwner {
  _TimelineTransport(String owner) : lifecycleRoot = ClientScope(owner: owner);
  @override
  final ClientScope lifecycleRoot;
  late final _transportScope = lifecycleRoot.child('transport');
  @override
  ClientScope get lifecycleScope => _transportScope;

  final _topics = <TestProductTopicObservation>[];
  @override
  Future<ProductTopicObservation> openProductTopic(
    ProductTopic topic, {
    required ClientResourceId resourceId,
  }) async {
    final observation = await openTestProductTopic(
      _transportScope,
      resourceId,
      StreamController<ProductTopicFrame>(),
    );
    _topics.add(observation);
    return observation;
  }

  Future<void> closeFixtureRoot(ClientCloseBudget budget) async {
    final report = await lifecycleRoot.close(budget: budget);
    expect(report.complete, isTrue, reason: describeTestCloseReport(report));
    expect(directoryCloseCalls, openedMetadataThreadIds.length);
    for (final observation in _topics) {
      expect(observation.source.closeRequested.isCompleted, isTrue);
      expect(observation.source.closeAcknowledged.isCompleted, isTrue);
      expect(observation.source.controller.isClosed, isTrue);
    }
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError(
    'Unexpected timeline port: ${invocation.memberName}',
  );
}

final class _LeaseTransport extends _TimelineTransport {
  _LeaseTransport(this.initial) : super('timeline-lease-test') {
    _createFeed();
  }
  ViewUpdate initial;
  void _createFeed() {
    feed = ScriptedTimelineReader(
      queries: _TimelineQueries(reader, 'lease'),
      initial: () => initial,
    );
  }

  late ScriptedTimelineReader feed;
  _Reader reader = _Reader();
  int opens = 0;

  /// The independent state subscription carries only state facts; each attempt
  /// owns its own single-consumer feed.
  @override
  Future<ConversationStateFeed> openConversationStateFeed(
    String threadId,
  ) async => ScriptedConversationStateFeed(
    threadId: 'thread',
    subscriptionId: 'lease-state',
    initialState: () => ThreadSnapshotFrame(
      workspace: chatWorkspace('thread'),
      completedHistoryVersion: completedHistoryVersion,
      schemaVersion: threadSchemaVersion,
    ),
  );

  @override
  Future<TimelineReader> openTimelineReader(
    String threadId, {
    required int presentationVersion,
    required int readerProtocolVersion,
    required ReadDemand demand,
  }) async {
    if (opens > 0) {
      reader = _Reader();
      _createFeed();
    }
    opens++;
    return feed;
  }
}

final class _Reader extends Fake implements ConversationReader {
  @override
  String get threadId => 'thread';
  final reply = Completer<ViewUpdate>();
  final entered = Completer<void>();
  final boundaries = <String>[];
  final demands = <ReadDemand>[];
  bool failClose = false;
  int closeCalls = 0;
  void Function()? onRequestClose;
  Future<void> Function(int attempt)? onClose;
  final Map<int, Completer<void>> _closeEntries = {};

  Future<void> closeStarted(int attempt) => closeCalls >= attempt
      ? Future.value()
      : (_closeEntries[attempt] ??= Completer<void>()).future;
  ConversationContentWatch? contentWatch;
  DisplayMembers? displayMembers;
  int watchOpens = 0;
  int memberOpens = 0;

  @override
  ConversationContentWatch watchContent({
    required ContentRef reference,
    required ContentRange range,
  }) {
    watchOpens++;
    return contentWatch!;
  }

  Future<TimelinePage> loadTimelineOlder({
    required String before,
    required ReadDemand demand,
  }) {
    boundaries.add(before);
    demands.add(demand);
    if (!entered.isCompleted) entered.complete();
    return reply.future.then(historyFixturePage);
  }

  @override
  void requestClose() => onRequestClose?.call();
  @override
  Future<void> close() async {
    closeCalls++;
    _closeEntries.remove(closeCalls)?.complete();
    final callback = onClose;
    if (callback != null) {
      await callback(closeCalls);
      return;
    }
    if (failClose) throw StateError('reader close failed');
  }
}

final class _CleanupWatch implements ConversationContentWatch {
  _CleanupWatch(this.failure, this.stack) {
    _windows = StreamController<ContentWindow>(
      sync: true,
      onCancel: () => cancelGate.future,
    );
  }
  Object? failure;
  final StackTrace stack;
  late final StreamController<ContentWindow> _windows;
  final cancelGate = Completer<void>();
  final joinStarted = Completer<void>();
  Future<void>? joining;
  int requestCalls = 0;
  int closeCalls = 0;
  @override
  Stream<ContentWindow> get windows => _windows.stream;
  @override
  void requestClose() => requestCalls++;
  @override
  Future<void> close() => joining = _join();
  Future<void> _join() async {
    closeCalls++;
    if (!joinStarted.isCompleted) joinStarted.complete();
    if (failure case final error?) Error.throwWithStackTrace(error, stack);
  }

  void recover() {
    failure = null;
    if (!cancelGate.isCompleted) cancelGate.complete();
  }

  Future<void> dispose() => _windows.close();
}

final class _CleanupMembers extends Fake implements DisplayMembers {
  _CleanupMembers(
    this.failure,
    this.stack,
    this.requestFailure,
    this.requestStack,
  );
  Object? failure;
  final StackTrace stack;
  Object? requestFailure;
  final StackTrace requestStack;
  int closeCalls = 0;
  int requestCalls = 0;
  Completer<void>? closeGate;
  void Function()? onRequestClose;
  void Function()? onClose;
  @override
  void requestClose() {
    requestCalls++;
    onRequestClose?.call();
    if (requestFailure case final error?) {
      Error.throwWithStackTrace(error, requestStack);
    }
  }

  @override
  Future<void> close() async {
    closeCalls++;
    onClose?.call();
    await closeGate?.future;
    if (failure case final error?) Error.throwWithStackTrace(error, stack);
  }

  void recover() {
    failure = null;
    requestFailure = null;
    if (closeGate case final gate? when !gate.isCompleted) gate.complete();
  }
}

final class _ScopedTransport extends _TimelineTransport {
  _ScopedTransport() : super('timeline-scoped-test');
  final mainReader = _Reader();
  final childReader = _Reader();
  late final main = ScriptedTimelineReader(
    queries: _TimelineQueries(mainReader, 'main'),
    initial: () => _mainBatch([chatMessage('main')]),
  );
  late final child = ScriptedConversationFeed(
    threadId: 'thread',
    subscriptionId: 'child',
    reader: childReader,
    initial: () => ChatBatch(
      placement: ChatPlacement.set,
      entries: [chatMessage('child')],
      throughSeq: 1,
    ),
  );
  final scopes = <ChatScope>[];

  /// Main owns the independent state subscription; Children stay content-only.
  @override
  Future<ConversationStateFeed> openConversationStateFeed(
    String threadId,
  ) async => ScriptedConversationStateFeed(
    threadId: 'thread',
    subscriptionId: 'main-state',
    initialState: () => ThreadSnapshotFrame(
      workspace: chatWorkspace('thread'),
      completedHistoryVersion: completedHistoryVersion,
      schemaVersion: threadSchemaVersion,
    ),
  );

  @override
  Future<TimelineReader> openTimelineReader(
    String threadId, {
    required int presentationVersion,
    required int readerProtocolVersion,
    required ReadDemand demand,
  }) async => main;
  @override
  Future<ConversationFeed> openConversationFeed(
    String threadId, {
    required ChatScope scope,
    required ReadDemand demand,
  }) async {
    scopes.add(scope);
    expect(scope, isA<ChatScope>());
    return child;
  }
}

ViewUpdate _mainBatch(
  List<CompletedEntry> entries, {
  ChatPlacement placement = ChatPlacement.set,
  String? before,
}) {
  final through = entries.lastOrNull?.completionSeq ?? 0;
  return displayBatch(
    [for (final entry in entries) displaySingle(entry)],
    placement: placement,
    before: before,
    from: placement == ChatPlacement.append
        ? entries.first.completionSeq - 1
        : null,
    through: through,
    live: placement == ChatPlacement.set
        ? TailSnapshot(
            currentWorkId: null,
            revision: 1,
            layoutRevision: 1,
            readyFrontier: through,
            executionPresent: false,
            blocks: const [],
          )
        : null,
  );
}

final class _TimelineQueries extends Fake implements TimelineReader {
  _TimelineQueries(this.reader, this.subscriptionId);
  @override
  OpenTimeline get metadata => OpenTimeline(
    readerId: subscriptionId,
    presentationVersion: 6,
    readerProtocolVersion: 1,
    initialCursor: ViewCursor('$subscriptionId-C0'),
  );
  @override
  final _Reader reader;
  String get threadId => 'thread';
  final String subscriptionId;
  @override
  Future<TimelinePage> loadTimelineOlder({
    required String before,
    required ReadDemand demand,
  }) => reader.loadTimelineOlder(before: before, demand: demand);
  @override
  Future<DisplayMembers> openDisplayMembers({
    required DisplayBlockRef reference,
    required DisplayMemberWindow window,
    required ReadDemand demand,
  }) async {
    reader.memberOpens++;
    return reader.displayMembers!;
  }

  @override
  void requestClose() => reader.requestClose();
  @override
  Future<void> close() => reader.close();
}
