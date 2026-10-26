import 'package:anywork_client/resources.dart';

import '../../../rust/api/studio/types/chat.dart' as native;
import 'adapter_failure.dart';
import 'shutdown_issue_converters.dart';

FeedCloseReport feedCloseReportFromBridge(native.BridgeFeedCloseReport value) {
  if (value.feedId.isEmpty) throw adapterProtocol('feed-close-identity');
  return FeedCloseReport(
    feedId: value.feedId,
    outcome: switch (value.outcome) {
      native.BridgeFeedCloseOutcome_Clean() => const FeedCloseOutcome.clean(),
      native.BridgeFeedCloseOutcome_Unresolved(:final issues) =>
        issues.isEmpty
            ? throw adapterProtocol('feed-close-issues')
            : FeedCloseOutcome.unresolved(
                issues: List.unmodifiable([
                  for (final issue in issues)
                    FeedCloseIssue(
                      diagnostic: shutdownIssueFromBridge(issue.diagnostic),
                      recovery: switch (issue.recovery) {
                        native.BridgeCleanupRecovery.awaitCompletion =>
                          CleanupRecovery.awaitCompletion,
                        native.BridgeCleanupRecovery.retryClose =>
                          CleanupRecovery.retryClose,
                        native.BridgeCleanupRecovery.terminal =>
                          CleanupRecovery.terminal,
                      },
                    ),
                ]),
              ),
    },
  );
}
