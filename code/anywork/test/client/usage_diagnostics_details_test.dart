import 'package:anywork/src/app/theme/material3_theme.dart';
import 'package:anywork/src/features/status/usage_diagnostics_details.dart';
import 'package:anywork/src/l10n/app_localizations.dart';
import 'package:anywork_client/models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'latest complete call does not erase a cumulative cancellation gap',
    (tester) async {
      final cancelled = _call(
        'cancelled-call',
        UsageTerminalStatus.cancelled,
        UsageReportStatus.missing,
        null,
      );
      final succeeded = _call(
        'latest-success',
        UsageTerminalStatus.succeeded,
        UsageReportStatus.reported,
        0,
      );
      final diagnostics = ThreadUsageDiagnostics(
        incompleteCalls: 1,
        missingCalls: 1,
        partialCalls: 0,
        invalidCalls: 0,
        overflowCalls: 0,
        byOutcome: const [
          UsageOutcomeCountSnapshot(
            outcome: UsageTerminalStatus.succeeded,
            calls: 2,
            incompleteCalls: 0,
          ),
          UsageOutcomeCountSnapshot(
            outcome: UsageTerminalStatus.cancelled,
            calls: 1,
            incompleteCalls: 1,
          ),
        ],
        byPurpose: const [
          UsagePurposeCountSnapshot(
            purpose: 'primary',
            calls: 3,
            incompleteCalls: 1,
          ),
        ],
        byIssue: const [
          UsageIssueCountSnapshot(
            issue: UsageGapIssue(
              field: UsageCounterField.output,
              reason: UsageGapReason.unreported,
            ),
            calls: 1,
          ),
        ],
        otherPurposeCalls: 0,
        recentGaps: [cancelled],
        latestCall: succeeded,
        legacyUnknown: true,
        countsOverflowed: false,
      );
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(320, 1200);
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('en'),
          theme: pureStudioTheme(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: UsageDiagnosticsDetails(diagnostics: diagnostics),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      final latest = find.byKey(
        const ValueKey(('latest', 'thread-observed', 'latest-success')),
      );
      final gap = find.byKey(
        const ValueKey(('gap', 'thread-observed', 'cancelled-call')),
      );
      expect(
        find.descendant(
          of: latest,
          matching: find.text('Succeeded · Usage complete'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: gap,
          matching: find.text('Cancelled · Usage not retained at completion'),
        ),
        findsOneWidget,
      );
      final identity = tester.widget<SelectableText>(
        find.descendant(of: latest, matching: find.byType(SelectableText)),
      );
      expect(identity.data, 'Thread: thread-observed\nCall: latest-success');
      expect(
        find.text('Recent gaps (at most 8, not the full history)'),
        findsOneWidget,
      );
      expect(
        find.textContaining(
          'Later complete calls do not erase cumulative gaps',
        ),
        findsOneWidget,
      );
      expect(
        find.textContaining(
          'this does not establish that the provider did not send it',
        ),
        findsOneWidget,
      );
      expect(
        find.textContaining(
          'Call counts, usage or purpose sources in older history cannot be proven',
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );
}

UsageCallSnapshot _call(
  String callId,
  UsageTerminalStatus outcome,
  UsageReportStatus status,
  int? output,
) => UsageCallSnapshot(
  threadId: 'thread-observed',
  callId: callId,
  turnId: 'turn-observed',
  effectSequence: 3,
  observedAt: 1700000000,
  purpose: 'primary',
  outcome: outcome,
  status: status,
  usage: UsageReport(
    inputTokens: output == null ? null : 10,
    outputTokens: output,
    cacheReadTokens: null,
    cacheWriteTokens: null,
    reasoningTokens: null,
    totalTokens: output == null ? null : 10,
  ),
  issues: output == null
      ? const [
          UsageGapIssue(
            field: UsageCounterField.output,
            reason: UsageGapReason.unreported,
          ),
        ]
      : const [],
);
