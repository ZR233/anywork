import 'dart:async';
import 'dart:convert';

import 'package:anywork/src/infrastructure/frb/studio_api.dart'
    show DemoStudioTransport;
import 'package:anywork/src/presentation/view_models/timeline_session_owner.dart';
import 'package:anywork_client/studio_client.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/recording_demo_transport.dart';
import 'support/chat_fixtures.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('late A1 retirement cannot erase A2 unresolved close ownership', () async {
    final transport = _RetirementTransport();
    final releaseFirst = Completer<void>();
    final firstCreated = Completer<_SetAcknowledgedConnection>();
    final alternateCreated = Completer<_SetAcknowledgedConnection>();
    final secondCreated = Completer<_FailingCloseConnection>();
    var mainOpens = 0;
    transport.conversationFeedFactory = (threadId, inner) async {
      if (threadId != 'thread-main') {
        final alternate = _SetAcknowledgedConnection(inner: inner);
        alternateCreated.complete(alternate);
        return alternate;
      }
      mainOpens++;
      if (mainOpens == 1) {
        final first = _SetAcknowledgedConnection(inner: inner);
        firstCreated.complete(first);
        await releaseFirst.future;
        return first;
      }
      final second = _FailingCloseConnection(inner: inner)
        ..failure = StateError('A2 close acknowledgement failed');
      secondCreated.complete(second);
      return second;
    };
    // A1 opening, B retiring and A2 opening are independent live resources.
    final client = AnyworkClient(
      transport: transport,
      clientId: 'retirement-report',
      budget: ResourceBudget(
        capacities: {
          ResourceKind.chatHandle: 3,
          ResourceKind.pendingOperation: 64,
          ResourceKind.draft: 64,
          ResourceKind.attachment: 256,
          ResourceKind.observer: 1024,
          ResourceKind.readModel: 256,
        },
      ),
    );
    final timeline = TimelineSessionOwner(client: client)
      ..updateReadDemand(chatDemand);
    final displays = <TimelineDisplayLease>{};
    void diagnose(String stage, {CloseReport? report}) {
      printOnFailure(
        jsonEncode({
          'retirementStage': stage,
          'timelineView': timeline.source.value?.toString(),
          'unresolved': [
            for (final entry
                in report?.unresolved ?? client.unresolvedResources)
              {
                'owner': entry.owner,
                'attemptId': entry.attemptId.value,
                'reasonType': entry.reason.runtimeType.toString(),
                'reason': entry.reason.toString(),
              },
          ],
          'complete': report?.complete,
          'budget': [
            for (final usage in client.budget.usage)
              {
                'kind': usage.kind.name,
                'owner': usage.owner,
                'phase': usage.phase.name,
              },
          ],
          'displays': [
            for (final display in displays)
              {
                'threadId': display.threadId,
                'generation': display.generation,
                'retired': display.isRetired,
                'released': display.isReleased,
                'mounted': display.isMounted,
                'queryCleanupError': display.queryCleanupError?.toString(),
                'contentClosed': display.content.isClosed,
                'ownedAttempts': display.content.ownedAttemptCount,
              },
          ],
        }),
      );
    }

    final ownerObservation = timeline.source.watch((view) {
      final display = view == null ? null : timeline.lease(view.threadId);
      if (display != null) displays.add(display);
      diagnose('owner.publish');
    });
    addTearDown(() async {
      if (!releaseFirst.isCompleted) releaseFirst.complete();
      if (secondCreated.isCompleted) {
        (await secondCreated.future).failure = null;
      }
      await timeline.close(deadline: _deadline());
      await client.close(deadline: _deadline());
      await client.retryCleanup(deadline: _deadline());
      ownerObservation.cancel();
    });
    await client.bootstrap();
    await client.directoryCommands.selectThread('thread-main');
    client.conversations.setVisibleThread('thread-main');
    timeline.select('thread-main');
    final first = await firstCreated.future;
    final owner = client.conversations.existingSession('thread-main')!;
    final firstAttempt = owner.content.currentAttemptId!;
    await client.directoryCommands.selectThread('thread-alt');
    client.conversations.setVisibleThread('thread-alt');
    timeline.select('thread-alt');
    await client.conversations.existingSession('thread-alt')!.content.ready;
    await (await alternateCreated.future).firstSetAcknowledged.future;
    await client.directoryCommands.selectThread('thread-main');
    client.conversations.setVisibleThread('thread-main');
    timeline.select('thread-main');
    final second = await secondCreated.future;
    await owner.content.ready;
    await second.firstSetAcknowledged.future;
    final secondAttempt = owner.content.currentAttemptId!;
    diagnose('A2 opened');
    expect(secondAttempt, isNot(firstAttempt));

    // An expired deadline reports both the blocked A1 open and A2's real close
    // failure without waiting on wall-clock delays or abandoning either permit.
    client.conversations.setVisibleThread(null);
    timeline.select(null);
    final closing = client.close(deadline: DateTime.utc(2000));
    await second.closeFailed.future;
    final report = await closing;
    diagnose('initial close', report: report);
    expect(
      report.unresolved.any(
        (entry) =>
            entry.owner == 'conversation:thread-main' &&
            entry.attemptId == secondAttempt,
      ),
      isTrue,
    );
    expect(first.closeCalls, 0);

    releaseFirst.complete();
    await first.joined.future;
    // 撤销公开需求并汇合已退役的 A1；A2 的失败仍必须保留为未解决责任。
    final retired = await client.retryCleanup(deadline: _deadline());
    diagnose('A1 joined and A2 failure retained', report: retired);
    expect(retired.complete, isFalse);
    expect(first.initialCalls, 0);
    expect(client.budget.used(ResourceKind.chatHandle), 1);
    expect(
      client.unresolvedResources.any(
        (entry) =>
            entry.owner == 'conversation:thread-main' &&
            entry.attemptId == secondAttempt,
      ),
      isTrue,
      reason:
          'the old successful retirement must not replace A2 close evidence',
    );

    second.failure = null;
    final recovered = await client.retryCleanup(deadline: _deadline());
    diagnose('A2 failure cleared and cleanup retried', report: recovered);
    printOnFailure(
      jsonEncode({
        'firstAttempt': firstAttempt.value,
        'secondAttempt': secondAttempt.value,
        'mainOpens': mainOpens,
        'A1closeCalls': first.closeCalls,
        'A2closeCalls': second.closeCalls,
        'A2joined': second.joined.isCompleted,
        'chatHandles': client.budget.used(ResourceKind.chatHandle),
      }),
    );
    expect(recovered.complete, isTrue);
    expect(client.budget.used(ResourceKind.chatHandle), 0);
    expect(mainOpens, 2, reason: 'cleanup never reopens a timeline connection');
    // These are Client ownership contracts over Demo, not native FRB evidence.
  });

  test('cleanup retry leaves a healthy active timeline out of unresolved', () async {
    final transport = RecordingDemoTransport();
    final opened = Completer<_SetAcknowledgedConnection>();
    transport.conversationFeedFactory = (_, inner) async {
      final connection = _SetAcknowledgedConnection(inner: inner);
      opened.complete(connection);
      return connection;
    };
    final client = AnyworkClient(
      transport: transport,
      clientId: 'healthy-cleanup',
    );
    final timeline = TimelineSessionOwner(client: client)
      ..updateReadDemand(chatDemand);
    addTearDown(() async {
      await timeline.close(deadline: _deadline());
      await client.close(deadline: _deadline());
    });
    await client.bootstrap();
    await client.directoryCommands.selectThread('thread-main');
    client.conversations.setVisibleThread('thread-main');
    timeline.select('thread-main');
    final owner = client.conversations.existingSession('thread-main')!;
    await owner.content.ready;
    await (await opened.future).firstSetAcknowledged.future;
    final connection = transport.feeds.single;
    final attempt = owner.content.currentAttemptId;
    final display = timeline.lease('thread-main')!;

    final report = await client.retryCleanup(deadline: _deadline());

    expect(
      report.complete,
      isTrue,
      reason:
          '${report.unresolved.map((entry) => '${entry.owner}/${entry.attemptId}: ${entry.reason}').toList()}',
    );
    expect(client.unresolvedResources, isEmpty);
    expect(owner.content.currentAttemptId, attempt);
    // demo 在会话打开后仍会推进真实内容：cleanup 重试不得替换连接，
    // 因此比较订阅身份而不是某一帧对象。
    expect(timeline.lease('thread-main'), same(display));
    expect(connection.requestCloseCalls, 0);
    expect(connection.closeCalls, 0);
    expect(transport.feeds, hasLength(1));
    expect(
      client.budget.used(ResourceKind.chatHandle),
      1,
      reason: 'a healthy active view keeps its real owner permit',
    );
  });
}

/// Keep the failed acknowledgement on the original facade boundary, without an
/// extra RecordingDemoTransport stream whose onCancel owns another close.
final class _RetirementTransport extends DemoStudioTransport {
  @override
  Duration get shutdownPhaseDelay => Duration.zero;
}

/// Observe the real first Set and ACK; entering transport forwarding is not
/// component acceptance and does not establish the healthy/retiring cut.
final class _SetAcknowledgedConnection extends RecordingConversationFeed {
  _SetAcknowledgedConnection({required super.inner});

  int? _firstSetSequence;
  final firstSetAcknowledged = Completer<void>();

  @override
  Stream<ConversationFrame> get events => super.events.map((frame) {
    if (frame.event case ConversationChatEvent(
      batch: ChatBatch(placement: ChatPlacement.set),
    )) {
      _firstSetSequence ??= frame.deliverySequence;
    }
    return frame;
  });

  @override
  Future<void> acknowledge(int deliverySequence) async {
    await super.acknowledge(deliverySequence);
    final firstSet = _firstSetSequence;
    if (firstSet != null &&
        deliverySequence >= firstSet &&
        !firstSetAcknowledged.isCompleted) {
      firstSetAcknowledged.complete();
    }
  }
}

/// Inject only a failed facade close acknowledgement. Reusing Recording's
/// stream onCancel -> close here would also fail subscription cancellation,
/// whose cached failed Future cannot be retried by a later facade close.
final class _FailingCloseConnection implements ConversationFeed {
  _FailingCloseConnection({required this.inner});

  final ConversationFeed inner;
  Object? failure;
  int closeCalls = 0;
  int? _firstSetSequence;
  final firstSetAcknowledged = Completer<void>();
  final closeFailed = Completer<void>();
  final joined = Completer<void>();

  @override
  String get threadId => inner.threadId;

  @override
  String get subscriptionId => inner.subscriptionId;

  @override
  ConversationReader get reader => inner.reader;

  @override
  Stream<ConversationFrame> get events => inner.events.map((frame) {
    if (frame.event case ConversationChatEvent(
      batch: ChatBatch(placement: ChatPlacement.set),
    )) {
      _firstSetSequence ??= frame.deliverySequence;
    }
    return frame;
  });

  @override
  Future<void> acknowledge(int deliverySequence) async {
    await inner.acknowledge(deliverySequence);
    final firstSet = _firstSetSequence;
    if (firstSet != null &&
        deliverySequence >= firstSet &&
        !firstSetAcknowledged.isCompleted) {
      firstSetAcknowledged.complete();
    }
  }

  @override
  void requestClose() => inner.requestClose();

  @override
  Future<void> close() async {
    closeCalls++;
    await inner.close();
    if (failure case final error?) {
      if (!closeFailed.isCompleted) closeFailed.complete();
      throw error;
    }
    if (!joined.isCompleted) joined.complete();
  }
}

DateTime _deadline() => DateTime.now().add(const Duration(seconds: 5));
