import 'package:anywork/src/app/theme/studio_semantic_colors.dart';
import 'package:anywork/src/l10n/app_localizations.dart';
import 'package:anywork/src/features/settings/accounts/state/account_presentations.dart';
import 'package:anywork/src/features/settings/accounts/widgets/account_usage_metrics.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('renders all ACP quota groups without inventing unknown values', (
    tester,
  ) async {
    const presentation = AcpUsagePresentation(
      queried: true,
      updatedLabel: 'checked recently',
      groups: [
        AccountQuotaGroupPresentation(
          name: 'Gemini',
          quotas: [
            AccountQuotaPresentation(
              label: 'Fast',
              remaining: '37%',
              remainingFraction: .37,
              resetLabel: 'resets soon',
            ),
            AccountQuotaPresentation(label: 'Pro', remaining: 'unknown'),
          ],
        ),
        AccountQuotaGroupPresentation(
          name: 'Claude',
          quotas: [
            AccountQuotaPresentation(label: 'Requests', remaining: '12'),
          ],
        ),
        AccountQuotaGroupPresentation(
          name: 'Other model family',
          emptyLabel: 'no active limits',
        ),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: ThemeData(
          extensions: const [
            StudioSemanticColors(
              eyeAccent: Colors.blue,
              activeIndicator: Colors.green,
              success: Colors.green,
              successContainer: Colors.green,
              warning: Colors.orange,
              warningContainer: Colors.orange,
            ),
          ],
        ),
        home: const Scaffold(body: AcpUsageMetrics(value: presentation)),
      ),
    );

    expect(find.text('Gemini'), findsOneWidget);
    expect(find.text('Claude'), findsOneWidget);
    expect(find.text('Fast'), findsOneWidget);
    expect(find.text('Pro'), findsOneWidget);
    expect(find.text('Requests'), findsOneWidget);
    expect(find.text('Other model family'), findsOneWidget);
    expect(find.text('no active limits'), findsOneWidget);
    final l10n = AppLocalizations.of(
      tester.element(find.byType(AcpUsageMetrics)),
    );
    expect(find.text('${l10n.accountsRemaining} 37%'), findsOneWidget);
    expect(find.text('${l10n.accountsRemaining} 12'), findsOneWidget);
    expect(find.text('${l10n.accountsRemaining} unknown'), findsOneWidget);
    expect(
      find.text(l10n.settingsUsageUpdated('checked recently')),
      findsOneWidget,
    );
    expect(find.text(l10n.settingsUsageReset('resets soon')), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
  });

  testWidgets('distinguishes unqueried and failed observations', (
    tester,
  ) async {
    Future<void> pump(AcpUsagePresentation usage) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: AcpUsageMetrics(value: usage)),
        ),
      );
    }

    await pump(
      const AcpUsagePresentation(status: 'state not queried', queried: false),
    );
    expect(find.text('state not queried'), findsOneWidget);

    await pump(
      const AcpUsagePresentation(status: 'invalid response', queried: true),
    );
    expect(find.text('invalid response'), findsOneWidget);
    expect(find.text('state not queried'), findsNothing);
  });
}
