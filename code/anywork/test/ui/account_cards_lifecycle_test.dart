import 'package:anywork/src/features/settings/accounts/connectors/accounts_connector.dart';
import 'package:anywork/src/features/settings/accounts/state/account_presentations.dart';
import 'package:anywork/src/features/settings/accounts/view_models/account_card_view_model.dart';
import 'package:anywork/src/features/settings/accounts/widgets/account_list_item.dart';
import 'package:anywork/src/app/theme/material3_theme.dart';
import 'package:anywork/src/l10n/app_localizations.dart';
import 'package:anywork/src/l10n/app_localizations_en.dart';
import 'package:anywork_client/accounts.dart';
import 'package:anywork_client/acp.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../unit/accounts_view_models_test.dart';

void main() {
  testWidgets(
    'production list retains hidden card VMs across search and rebuild',
    (tester) async {
      final h = AccountsVmHarness();
      h.acp.holdUsageRefreshRequests = true;
      addTearDown(() {
        h.dispose();
        for (final request in h.acp.usageRefreshRequests) {
          if (!request.completion.isCompleted) {
            request.completion.complete(AcpUsageRefreshDisposition.cancelled);
          }
        }
      });
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      h.accounts.state.publish(
        AccountsState(
          stamp: vmStamp,
          templates: h.accounts.state.value.templates,
          accounts: [
            vmSummary(const NativeAccountIdentity('alpha'), name: 'Alpha'),
            vmSummary(const NativeAccountIdentity('beta'), name: 'Beta'),
            vmSummary(const AcpAccountIdentity('gamma'), name: 'Gamma'),
          ],
        ),
      );
      Widget app({bool visible = true}) => UncontrolledProviderScope(
        container: h.container,
        child: MaterialApp(
          locale: const Locale('en'),
          theme: pureStudioTheme(locale: const Locale('en')),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(body: AccountsConnector(visible: visible)),
        ),
      );

      await tester.pumpWidget(app());
      await tester.pumpAndSettle();
      expect(find.byType(AccountListItem), findsNWidgets(3));
      expect(h.acp.usageRefreshRequests, hasLength(1));
      final initialAcp = h.acp.usageRefreshRequests.single;
      expect(h.usage.refreshes.map((identity) => identity.accountId), [
        'alpha',
        'beta',
      ]);
      const beta = AccountDisplayKey(kind: AccountKind.native, id: 'beta');
      final betaBefore = h.container
          .read(accountCardViewModelProvider(beta))
          .requireValue;
      final refreshesBeforeSearch = h.usage.refreshes.length;
      final acpRequestsBeforeSearch = h.acp.usageRefreshRequests.length;
      await tester.enterText(find.byType(TextField), 'Alpha');
      await tester.pumpAndSettle();
      expect(find.byType(AccountListItem), findsOneWidget);
      expect(find.text('Beta'), findsNothing);
      expect(
        h.container.read(accountCardViewModelProvider(beta)).requireValue,
        betaBefore,
      );
      await tester.pumpWidget(app());
      await tester.pumpAndSettle();
      expect(
        h.container.read(accountCardViewModelProvider(beta)).requireValue,
        betaBefore,
      );
      expect(h.usage.refreshes, hasLength(refreshesBeforeSearch));
      expect(h.acp.usageRefreshRequests, hasLength(acpRequestsBeforeSearch));
      expect(h.usage.refreshes, hasLength(2));
      expect(h.acp.usageRefreshRequests, hasLength(1));
      expect(initialAcp.pendingCancels, 0);
      await tester.tap(find.text(AppLocalizationsEn().settingsRefreshUsage));
      await tester.pumpAndSettle();
      expect(h.usage.refreshes.map((identity) => identity.accountId), [
        'alpha',
        'beta',
        'alpha',
        'beta',
      ]);
      expect(h.acp.usageRefreshRequests, hasLength(2));
      final explicitAcp = h.acp.usageRefreshRequests.last;
      explicitAcp.completion.complete(AcpUsageRefreshDisposition.joined);
      await tester.pumpAndSettle();
      expect(h.acp.usageQueries, isEmpty);
      await tester.enterText(find.byType(TextField), '');
      await tester.pumpAndSettle();
      expect(find.byType(AccountListItem), findsNWidgets(3));
      expect(h.usage.demands, hasLength(2));
      await tester.pumpWidget(app(visible: false));
      await tester.pumpAndSettle();
      expect(h.usage.demands.every((demand) => demand.releases == 1), isTrue);
      expect(initialAcp.pendingCancels, 1);
      expect(explicitAcp.pendingCancels, 0);
      initialAcp.completion.complete(AcpUsageRefreshDisposition.cancelled);
      await tester.pumpWidget(app());
      await tester.pumpAndSettle();
      expect(h.usage.demands, hasLength(4));
      expect(h.usage.refreshes, hasLength(6));
      expect(h.acp.usageRefreshRequests, hasLength(3));
      final returnedAcp = h.acp.usageRefreshRequests.last;
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      expect(returnedAcp.pendingCancels, 1);
      returnedAcp.completion.complete(AcpUsageRefreshDisposition.cancelled);
    },
  );
}
