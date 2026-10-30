import 'package:anywork_client/models.dart';
import 'package:flutter/material.dart';

import '../../l10n/studio_l10n.dart';
import 'status_detail_panel.dart';
import 'usage_diagnostic_labels.dart';

/// Displays canonical diagnostic facts, not reconstructed provider or accounting state.
class UsageDiagnosticsDetails extends StatelessWidget {
  const UsageDiagnosticsDetails({required this.diagnostics, super.key});

  final ThreadUsageDiagnostics diagnostics;

  @override
  Widget build(BuildContext context) {
    final latest = diagnostics.latestCall;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        StatusDetailPanel(
          title: context.l10n.usageCumulativeTitle,
          children: [
            StatusDetailRow(
              label: context.l10n.usageIncompleteCalls,
              value: '${diagnostics.incompleteCalls}',
            ),
            StatusDetailRow(
              label: context.l10n.usageMissingCalls,
              value: '${diagnostics.missingCalls}',
            ),
            StatusDetailRow(
              label: context.l10n.usagePartialCalls,
              value: '${diagnostics.partialCalls}',
            ),
            StatusDetailRow(
              label: context.l10n.usageInvalidCalls,
              value: '${diagnostics.invalidCalls}',
            ),
            StatusDetailRow(
              label: context.l10n.usageOverflowCalls,
              value: '${diagnostics.overflowCalls}',
            ),
            Text(context.l10n.usageCumulativeNote),
            if (diagnostics.legacyUnknown)
              Text(context.l10n.usageHistoryUnknown),
            if (diagnostics.countsOverflowed)
              Text(context.l10n.usageCountsOverflowed),
            for (final count in diagnostics.byOutcome)
              StatusDetailRow(
                label: usageOutcomeLabel(context, count.outcome),
                value:
                    '${count.calls} · '
                    '${context.l10n.usageIncompleteCalls}: ${count.incompleteCalls}',
                valueMaxLines: 3,
              ),
            for (final count in diagnostics.byPurpose)
              StatusDetailRow(
                label:
                    '${context.l10n.usagePurpose}: '
                    '${count.purpose ?? context.l10n.usageUnknown}',
                value:
                    '${count.calls} · '
                    '${context.l10n.usageIncompleteCalls}: ${count.incompleteCalls}',
                valueMaxLines: 3,
              ),
            StatusDetailRow(
              label: context.l10n.usageOtherPurposeCalls,
              value: '${diagnostics.otherPurposeCalls}',
            ),
            for (final count in diagnostics.byIssue)
              StatusDetailRow(
                label:
                    '${usageCounterLabel(context, count.issue.field)} · '
                    '${usageGapReasonLabel(context, count.issue.reason)}',
                value: '${count.calls}',
              ),
          ],
        ),
        const StatusDetailDivider(),
        StatusDetailPanel(
          title: context.l10n.usageLatestTitle,
          children: [
            if (latest == null)
              Text(context.l10n.usageUnknown)
            else
              _UsageCallDetails(
                key: ValueKey(('latest', latest.threadId, latest.callId)),
                call: latest,
              ),
          ],
        ),
        const StatusDetailDivider(),
        StatusDetailPanel(
          title: context.l10n.usageRecentGapsTitle,
          children: [
            Text(context.l10n.usageRecentGaps),
            for (final call in diagnostics.recentGaps)
              Padding(
                key: ValueKey(('gap', call.threadId, call.callId)),
                padding: const EdgeInsets.only(bottom: 8),
                child: _UsageCallDetails(call: call),
              ),
          ],
        ),
      ],
    );
  }
}

class _UsageCallDetails extends StatelessWidget {
  const _UsageCallDetails({required this.call, super.key});

  final UsageCallSnapshot call;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '${usageOutcomeLabel(context, call.outcome)} · '
          '${usageReportStatusLabel(context, call.status)}',
        ),
        Text(
          '${context.l10n.usagePurpose}: '
          '${call.purpose ?? context.l10n.usageUnknown}',
        ),
        SelectableText(
          '${context.l10n.usageThreadId}: ${call.threadId}\n'
          '${context.l10n.usageCallId}: ${call.callId}',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        StatusDetailRow(
          label: context.l10n.statusInputTokensLabel,
          value: call.usage.inputTokens == null
              ? context.l10n.usageUnknown
              : formatTokenCount(call.usage.inputTokens),
        ),
        StatusDetailRow(
          label: context.l10n.statusOutputTokensLabel,
          value: call.usage.outputTokens == null
              ? context.l10n.usageUnknown
              : formatTokenCount(call.usage.outputTokens),
        ),
        for (final issue in call.issues)
          Text(
            '${usageCounterLabel(context, issue.field)}: '
            '${usageGapReasonLabel(context, issue.reason)}',
          ),
        if (call.outcome == UsageTerminalStatus.cancelled)
          Text(context.l10n.usageCancelledNote),
      ],
    );
  }
}
