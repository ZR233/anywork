import 'dart:async';

import '../../../resources_ports.dart';
import '../domain/conversation_timeline.dart';
import '../domain/timeline_models.dart';
import 'connection_owner.dart';
import 'timeline_owner.dart';

/// A display-generation borrow of the original concrete Timeline attempt.
final class TimelineQueryScopeOwner implements StudioTimelineQueryScope {
  TimelineQueryScopeOwner(this.channel, this.attempt, this.generation)
    : _permit = channel.budget.acquire(
        ResourceKind.readModel,
        owner: 'timeline-query:${channel.threadId}:$generation',
      );
  final ConversationTimelineOwner channel;
  final TimelineAttempt attempt;
  final ResourcePermit _permit;
  final Set<Future<void>> _pending = {};
  bool _retired = false;
  @override
  final int generation;
  @override
  AttemptId get attemptId => attempt.owner.attemptId;
  @override
  String get threadId => channel.threadId;
  @override
  int get pendingQueries => _pending.length;
  @override
  bool get isActive => !_retired && channel.isCurrent(attempt);

  @override
  Future<StudioTimelinePage> page({String? before, int? limit}) {
    if (!isActive) return Future.error(conversationCancelled);
    final count = limit ?? timelinePageDefaultLimit;
    if (count < 1 || count > timelinePageMaxLimit)
      return Future.error(_argument);
    return _run(
      () => attempt.owner.call((c) => c.page(before: before, limit: count)),
    );
  }

  @override
  Future<StudioTimelineDetailChunk> readDetail({
    required String itemId,
    required StudioTimelineDetailQuery query,
  }) {
    if (!isActive) return Future.error(conversationCancelled);
    final size = query.maxBytes;
    if (size != null &&
        (size < timelineDetailMinBytes || size > timelineDetailMaxBytes)) {
      return Future.error(_argument);
    }
    return _run(
      () => attempt.owner.call((c) async {
        final chunk = await c.readDetail(itemId: itemId, query: query);
        if (chunk.itemId != itemId ||
            chunk.field != query.field ||
            chunk.revision != query.revision) {
          throw const StudioFailure(
            code: StudioFailureCode.protocol,
            message: 'The Timeline detail belongs to another item revision.',
            retryable: false,
            correlationId: 'timeline-query-identity',
          );
        }
        return chunk;
      }),
    );
  }

  Future<T> _run<T>(Future<T> Function() query) {
    final result = Completer<T>();
    final settled = Completer<void>();
    _pending.add(settled.future);
    unawaited(
      Future<T>.sync(query).then(
        (value) {
          if (isActive) {
            result.complete(value);
          } else {
            result.completeError(conversationCancelled);
          }
          _pending.remove(settled.future);
          settled.complete();
          _releaseIfDone();
        },
        onError: (Object error, StackTrace stack) {
          // Keep the original object for diagnostics: a typed failure keeps its
          // projection and anything else stays itself. `call` already mapped an
          // unknown adapter error into the synthesized internal failure, so the
          // original identity is taken from that owner's last cause instead of
          // hand-synthesizing a second failure.
          final cause = error is StudioFailure
              ? attempt.owner.takeDiagnosticCause(error)
              : null;
          result.completeError(
            conversationDiagnosticError(cause ?? error),
            stack,
          );
          _pending.remove(settled.future);
          settled.complete();
          _releaseIfDone();
        },
      ),
    );
    return result.future;
  }

  @override
  void retire() {
    _retired = true;
    _releaseIfDone();
  }

  void _releaseIfDone() {
    if (_retired && _pending.isEmpty) {
      _permit.release();
      attempt.scopes.remove(this);
    }
  }

  @override
  Future<CloseReport> close({DateTime? deadline}) async {
    retire();
    await observeConversationCompletion(
      Future.wait(List.of(_pending)).then<void>((_) {}),
      deadline,
    );
    _releaseIfDone();
    if (_pending.isEmpty) return CloseReport(unresolved: []);
    return CloseReport(
      unresolved: [
        UnresolvedResource(
          owner: 'timeline-query:$threadId:$generation',
          attemptId: attemptId,
          issues: [
            const FeedCloseIssue(
              diagnostic: StudioShutdownIssue(
                stage: 'timelineQuery',
                code: 'queryPending',
                message: 'The original Timeline query is still in flight.',
                retryable: true,
                correlationId: 'timeline-query',
              ),
              recovery: CleanupRecovery.awaitCompletion,
            ),
          ],
        ),
      ],
    );
  }

  static const _argument = StudioFailure(
    code: StudioFailureCode.invalidArgument,
    message:
        'Timeline page or detail arguments are outside the documented bounds.',
    retryable: false,
    correlationId: 'timeline-query-argument',
  );
}
