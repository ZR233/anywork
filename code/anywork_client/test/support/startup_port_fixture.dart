import 'dart:async';

import 'package:anywork_client/resources_ports.dart';
import 'package:anywork_client/workspace_ports.dart';

import 'scripted_feed.dart';

/// Native startup attempt only. The production StartupRepository owns the
/// operation, progress processing, RuntimeReady result and all cleanup.
final class ScriptedStartupPort implements StartupPort {
  final progress = ScriptedFeed<StartupProgressFrame>(feedId: 'startup-progress-41',
    sequenceOf: (frame) => frame is DataStartupProgressFrame ? frame.deliverySequence : null,
    isTerminal: (frame) => frame is! DataStartupProgressFrame);
  final runtimeCalled = Completer<void>();
  final runtimeReply = Completer<RuntimeReady>();
  final attempts = <int>[];
  int initializeCalls = 0;
  int prepareCalls = 0;
  int progressCalls = 0;
  static const ready = RuntimeReady(revision: 7, readyAt: 70,
    details: RuntimeStartupReadRef(entry: 11, revision: 7));

  @override
  Future<void> initializeLibrary() async { initializeCalls++; }
  @override
  Future<int> prepareStartupAttempt() async { prepareCalls++; return 41; }
  @override
  Future<FeedConnection<StartupProgressFrame>> openStartupProgress(int attemptId) async {
    if (attemptId != 41) throw StateError('Unscripted Startup attempt');
    progressCalls++;
    return progress;
  }
  @override
  Future<RuntimeReady> startStudioRuntime(int attemptId) {
    attempts.add(attemptId);
    if (attemptId != 41) throw StateError('Unscripted Startup runtime');
    runtimeCalled.complete();
    return runtimeReply.future;
  }

  Future<void> completeReady() async {
    await runtimeCalled.future;
    await progress.listened.future;
    progress.emit(const StartupProgressFrame.data(deliverySequence: 1, stage: StartupStage.ready));
    await progress.acknowledged(1);
    progress.emit(const StartupProgressFrame.closed(reason: StartupCloseReason.completed));
    // Native ordered completion closes this stream; it does not mark the SDK
    // progress owner closing or provide its independent native close receipt.
    progress.requestClose();
    runtimeReply.complete(ready);
  }

  void releasePending() {
    progress.requestClose();
    if (runtimeCalled.isCompleted && !runtimeReply.isCompleted) runtimeReply.completeError(const StudioFailure(
      code: StudioFailureCode.cancelled, message: 'The scripted startup is closing.',
      retryable: false, correlationId: 'startup-test-close'));
    final receipt = progress.closeReceipt;
    if (receipt != null && !receipt.isCompleted) receipt.complete(
      FeedCloseReport(feedId: progress.feedId, outcome: const FeedCloseOutcome.clean()));
  }
  @override
  Never noSuchMethod(Invocation invocation) =>
    throw UnsupportedError('Unscripted Startup native capability: ${invocation.memberName}');
}
