import 'dart:async';

import 'package:anywork_client/resources.dart';

/// An already-admitted presentation task. A deadline never cancels its actual
/// completion, replaces it with a successful Future, or loses its failure.
final class PresentationWork {
  PresentationWork({
    required this.owner,
    required this.attempt,
    required Future<void> completion,
  }) {
    completion.then<void>(
      (_) {
        settled = true;
        _completion.complete();
      },
      onError: (Object error, StackTrace stack) {
        settled = true;
        cause = error;
        trace = stack;
        issue = presentationIssue(
          'taskFailed',
          CleanupRecovery.terminal,
          error is StudioFailure ? error : null,
        );
        _completion.complete();
      },
    );
  }

  final String owner;
  final int attempt;
  final Completer<void> _completion = Completer<void>();
  bool settled = false;
  Object? cause;
  StackTrace? trace;
  FeedCloseIssue? issue;

  Future<void> get done => _completion.future;

  UnresolvedResource? get unresolved {
    final failure = issue;
    if (settled && failure == null) return null;
    return UnresolvedResource(
      owner: owner,
      attemptId: AttemptId(attempt),
      issues: [
        if (failure != null)
          failure
        else
          presentationIssue('pending', CleanupRecovery.awaitCompletion),
      ],
    );
  }
}

FeedCloseIssue presentationIssue(
  String code,
  CleanupRecovery recovery, [
  StudioFailure? failure,
]) => FeedCloseIssue(
  diagnostic: StudioShutdownIssue(
    stage: 'timeline-presentation',
    code: failure?.code.name ?? code,
    message: failure?.message ?? 'Timeline presentation has not been released',
    retryable: failure?.retryable ?? recovery != CleanupRecovery.terminal,
    correlationId: failure?.correlationId ?? 'timeline-$code',
  ),
  recovery: recovery,
);

Future<void> observePresentationCompletion(
  Iterable<Future<void>> work,
  DateTime? deadline,
) async {
  final joined = Future.wait(work);
  if (deadline == null) {
    await joined;
    return;
  }
  final remaining = deadline.difference(DateTime.now());
  if (remaining <= Duration.zero) return;
  try {
    await joined.timeout(remaining);
  } on TimeoutException {
    // The original pending owners remain registered; timeout is not a join.
  }
}
