import 'dart:async';

import '../../../resources_ports.dart';
import 'connection_owner.dart';

/// The original UI context/Recovery workflow, separate from pure metadata reads.
/// The Session installs this task before permit notifications or adapter calls.
final class ConversationContextTask {
  ConversationContextTask({required this.threadId, required this.attemptId});
  final String threadId;
  final AttemptId attemptId;
  final Completer<void> _done = Completer();
  ResourcePermit? _permit;
  bool _started = false;
  bool get pending => !_done.isCompleted;
  Future<void> get result => _done.future;
  final List<({Object cause, StackTrace stack})> _causes = [];

  void start({
    required ResourceBudget budget,
    required Future<void> Function() action,
    required void Function(Object, StackTrace) onFailure,
  }) {
    if (_started) throw StateError('A UI context task cannot start twice');
    _started = true;
    void settle({Object? error, StackTrace? stack}) {
      if (error != null) _causes.add((cause: error, stack: stack!));
      try {
        if (error != null) onFailure(error, stack!);
      } catch (failure, failureStack) {
        _causes.add((cause: failure, stack: failureStack));
        error ??= failure;
        stack ??= failureStack;
      } finally {
        try {
          _permit?.release();
        } catch (failure, failureStack) {
          _causes.add((cause: failure, stack: failureStack));
          error ??= failure;
          stack ??= failureStack;
        }
      }
      if (error == null)
        _done.complete();
      else
        _done.completeError(conversationFailure(error), stack);
    }

    try {
      _permit = budget.acquire(
        ResourceKind.pendingOperation,
        owner: 'conversation-context:$threadId',
      );
      unawaited(
        Future<void>.sync(action).then(
          (_) => settle(),
          onError: (Object error, StackTrace stack) =>
              settle(error: error, stack: stack),
        ),
      );
    } catch (error, stack) {
      settle(error: error, stack: stack);
    }
  }

  Future<CloseReport> close({DateTime? deadline}) async {
    await observeConversationCompletion(
      result.then<void>((_) {}, onError: (Object _, StackTrace __) {}),
      deadline,
    );
    return CloseReport(
      unresolved: [
        if (pending)
          UnresolvedResource(
            owner: 'conversation-context:$threadId',
            attemptId: attemptId,
            issues: [
              const FeedCloseIssue(
                diagnostic: StudioShutdownIssue(
                  stage: 'conversationSession',
                  code: 'contextPending',
                  message:
                      'The original UI context workflow is still in flight.',
                  retryable: true,
                  correlationId: 'conversation-session',
                ),
                recovery: CleanupRecovery.awaitCompletion,
              ),
            ],
          ),
      ],
    );
  }
}
