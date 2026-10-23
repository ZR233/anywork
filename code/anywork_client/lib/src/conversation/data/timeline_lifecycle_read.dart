import '../../../resources.dart';
import '../domain/conversation_timeline.dart';
import 'connection_owner.dart' show conversationCloseReport, observeConversationCompletion;

typedef TimelineAttemptLifecycleSnapshot = ({
  AttemptId attemptId, bool retired, Future<CloseReport>? join,
  bool Function() joined, CloseReport Function() report,
});
typedef TimelineLifecycleSnapshot = ({
  AttemptId? activeAttemptId, List<TimelineAttemptLifecycleSnapshot> attempts,
});

/// No owner/handle is exposed and none of these callbacks can start cleanup.
final class ConversationTimelineLifecycle implements TimelineLifecycleRead {
  ConversationTimelineLifecycle({required String threadId, required int Function() count,
    required TimelineLifecycleSnapshot Function() snapshot})
      : _threadId = threadId, _count = count, _snapshot = snapshot;
  final String _threadId;
  final int Function() _count;
  final TimelineLifecycleSnapshot Function() _snapshot;

  @override
  int get ownedAttemptCount => _count();

  @override
  Future<CloseReport> observeRetired({required DateTime deadline}) async {
    // Freeze concrete attempts and already-installed joins before the first await.
    final snapshot = _snapshot();
    final joins = [for (final attempt in snapshot.attempts)
      if (attempt.retired && attempt.join != null) attempt.join!];
    await observeConversationCompletion(Future.wait(joins).then<void>((_) {}), deadline);
    // Later work on this same Timeline is not awaited by this frozen read, but
    // it must still prevent a Clean result. Never look up a same-ID replacement.
    final current = _snapshot();
    final attempts = [...snapshot.attempts, for (final attempt in current.attempts)
      if (!snapshot.attempts.any((original) => original.attemptId == attempt.attemptId)) attempt];
    final unresolved = <UnresolvedResource>[];
    if ((current.activeAttemptId ?? snapshot.activeAttemptId) case final active?) {
      unresolved.add(_pending(active, 'demandActive', 'The original Timeline demand is not retired.'));
    }
    for (final attempt in attempts) {
      unresolved.addAll(attempt.report().unresolved);
      if (!attempt.retired) {
        unresolved.add(_pending(attempt.attemptId, 'notRetired', 'The original attempt was not retired at observation.'));
      } else if (attempt.join == null) {
        unresolved.add(UnresolvedResource(owner: 'timeline:$_threadId', attemptId: attempt.attemptId,
          issues: [const FeedCloseIssue(diagnostic: StudioShutdownIssue(stage: 'timelineLifecycle',
            code: 'joinNotRegistered', message: 'The retired attempt has no registered join completion.',
            retryable: false, correlationId: 'timeline-lifecycle'), recovery: CleanupRecovery.terminal)]));
      } else if (!attempt.joined()) {
        unresolved.add(_pending(attempt.attemptId, 'joinPending', 'The original retired join is still in flight.'));
      }
    }
    return conversationCloseReport(unresolved);
  }

  UnresolvedResource _pending(AttemptId attempt, String code, String message) => UnresolvedResource(
    owner: 'timeline:$_threadId', attemptId: attempt,
    issues: [FeedCloseIssue(diagnostic: StudioShutdownIssue(stage: 'timelineLifecycle',
      code: code, message: message, retryable: true, correlationId: 'timeline-lifecycle'),
      recovery: CleanupRecovery.awaitCompletion)]);
}
