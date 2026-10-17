import 'dart:async';

import 'package:anywork/src/app/app_graph.dart';
import 'package:anywork_client/studio_client.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/recording_demo_transport.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'concurrent queries cannot publish a candidate before its initial Reset',
    () async {
      final transport = RecordingDemoTransport();
      final initialEntered = Completer<void>();
      final releaseInitial = Completer<void>();
      transport.chatWindowFactory = (threadId, inner) async =>
          _HeldInitialWindow(
            threadId: threadId,
            inner: inner,
            entered: initialEntered,
            release: releaseInitial,
          );
      final graph = AppGraph(
        transport: transport,
        clientId: 'initial-readiness',
      );
      addTearDown(() async {
        if (!releaseInitial.isCompleted) releaseInitial.complete();
        await graph.close(deadline: _deadline());
      });
      await graph.client.bootstrap();
      await graph.client.directoryCommands.selectThread('thread-main');
      final session = graph.client.session('thread-main');
      await initialEntered.future;
      final first = session.chatView();
      final second = session.chatView();
      expect(session.state.hasSnapshot, isTrue);
      expect(session.state.hasChatWindow, isFalse);
      expect(session.state.chatVersion, isNull);
      expect(transport.windows, hasLength(1));
      expect(transport.windows.single.nextCalls, 0);

      releaseInitial.complete();
      final views = await Future.wait([first, second]);
      await transport.windows.single.nextEntered.future;

      expect(views.every((view) => view != null), isTrue);
      expect(session.state.hasChatWindow, isTrue);
      expect(session.state.items, isNotEmpty);
      expect(transport.windows, hasLength(1));
      expect(transport.windows.single.initialCalls, 1);
      expect(transport.windows.single.nextCalls, 1);
      // The returned facades can differ, but both belong to the same ready attempt.
      expect(
        (await views.first!.load(TimelineDirection.older)).disposition,
        StudioChatDisposition.noChange,
      );
    },
  );

  test(
    'history operation exclusivity and results belong to the current attempt',
    () async {
      final transport = RecordingDemoTransport();
      final graph = AppGraph(
        transport: transport,
        clientId: 'history-operation',
      );
      addTearDown(() => graph.close(deadline: _deadline()));
      await graph.client.bootstrap();
      await graph.client.directoryCommands.selectThread('thread-main');
      final session = graph.client.session('thread-main');
      await session.source.waitFor((s) => s.hasChatWindow);
      final version = session.state.chatVersion!;
      final first = session.beginHistoryOp(TimelineDirection.older)!;
      expect(session.beginHistoryOp(TimelineDirection.older), isNull);
      session.finishHistoryLoad();
      final second = session.beginHistoryOp(TimelineDirection.newer)!;
      session.observeHistoryOp(
        first,
        StudioChatReceipt(
          operationId: first,
          disposition: StudioChatDisposition.noChange,
          version: version,
          retained: true,
        ),
      );
      expect(session.state.history.isLoading, isTrue);
      expect(session.historyOperation.value!.token, second);

      session.observeHistoryOp(
        second,
        StudioChatReceipt(
          operationId: second,
          disposition: StudioChatDisposition.applied,
          version: version,
          retained: true,
        ),
      );
      expect(session.state.history.isLoading, isFalse);
      expect(
        session.historyOperation.value!.outcome,
        HistoryOperationOutcome.observed,
      );
      expect(
        session.historyOperation.value!.receipt!.disposition,
        StudioChatDisposition.applied,
      );

      final pending = session.beginHistoryOp(TimelineDirection.older)!;
      session.observeHistoryOp(
        pending,
        StudioChatReceipt(
          operationId: pending,
          disposition: StudioChatDisposition.applied,
          version: version + 5,
          retained: true,
        ),
      );
      expect(
        session.historyOperation.value!.outcome,
        HistoryOperationOutcome.awaitingObservation,
      );
      await graph.client.directoryCommands.selectThread('thread-alt');
      expect(session.state.history.isLoading, isFalse);
      expect(session.historyOperation.value!.token, pending);
      expect(
        session.historyOperation.value!.outcome,
        HistoryOperationOutcome.retired,
      );
    },
  );
}

class _HeldInitialWindow extends RecordingChatWindow {
  _HeldInitialWindow({
    required super.threadId,
    required super.inner,
    required this.entered,
    required this.release,
  });
  final Completer<void> entered;
  final Completer<void> release;

  @override
  Future<StudioChatSnapshot> initial() async {
    entered.complete();
    await release.future;
    return super.initial();
  }
}

DateTime _deadline() => DateTime.now().add(const Duration(seconds: 5));
