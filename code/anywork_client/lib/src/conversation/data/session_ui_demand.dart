import '../../../resources.dart';
import 'connection_owner.dart';

/// Identity of one concrete UI selection demand. Operation execution is separate.
final class ConversationUiDemand {
  ConversationUiDemand(this.selectionGeneration, this.attemptId);
  final int selectionGeneration;
  final AttemptId attemptId;
  bool retired = false;
  bool retirementRequested = false;
  bool withdrawn = false;
  final List<FeedCloseIssue> _issues = [];
  final List<({Object cause, StackTrace stack})> _causes = [];

  void recordFailure(String stage, Object cause, StackTrace stack) {
    _causes.add((cause: cause, stack: stack));
    _issues.add(conversationIssue(stage, cause, CleanupRecovery.terminal));
  }

  CloseReport report(String threadId) => CloseReport(
    unresolved: [
      if (_issues.isNotEmpty)
        UnresolvedResource(
          owner: 'conversation-ui:$threadId',
          attemptId: attemptId,
          issues: _issues,
        ),
    ],
  );
}

Future<CloseReport> closeConversationUi({
  required String threadId,
  required ConversationUiDemand demand,
  required bool Function() isCurrent,
  required Future<CloseReport> Function() closeScopes,
  required List<Future<CloseReport> Function()> close,
}) async {
  final reports = await Future.wait([
    for (final action in close)
      Future<CloseReport>.sync(
        () => isCurrent() ? action() : CloseReport(unresolved: []),
      ).then(
        (report) => report,
        onError: (Object error, StackTrace stack) {
          demand.recordFailure('conversationUiClose', error, stack);
          return demand.report(threadId);
        },
      ),
    Future<CloseReport>.sync(closeScopes).then(
      (report) => report,
      onError: (Object error, StackTrace stack) {
        demand.recordFailure('conversationUiScopes', error, stack);
        return demand.report(threadId);
      },
    ),
  ]);
  return conversationCloseReport([
    ...demand.report(threadId).unresolved,
    for (final report in reports) ...report.unresolved,
  ]);
}
