import 'package:anywork/src/features/settings/accounts/accounts_views.dart';
import 'package:anywork/src/features/settings/accounts/connectors/accounts_connector.dart';
import 'package:anywork/src/features/settings/accounts/view_models/account_card_view_model.dart';
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
            vmSummary(
              const AcpAccountIdentity('gamma'),
              name: 'Gamma',
              queryUsage: true,
            ),
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

  testWidgets(
    'accounts list filters by category and dispatches inline managed upgrade/cancel actions',
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
      tester.view.physicalSize = const Size(1200, 960);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      const release145 = AcpInstallReleaseView(
        version: '1.4.5',
        target: 'linux-x86_64',
        archiveUrl: 'https://dl.google.com/agy-extensions/releases/1.4.5.zip',
      );
      const release152 = AcpInstallReleaseView(
        version: '1.5.2',
        target: 'linux-x86_64',
        archiveUrl: 'https://dl.google.com/agy-extensions/releases/1.5.2.zip',
      );
      const installed145 = AcpInstalledServerView(
        installationId: 'id-145',
        release: release145,
        program: '/managed/145/agy_acp_server.par',
        readyAt: 10,
      );
      const installed152 = AcpInstalledServerView(
        installationId: 'id-152',
        release: release152,
        program: '/managed/152/agy_acp_server.par',
        readyAt: 20,
      );

      h.accounts.state.publish(
        AccountsState(
          stamp: vmStamp,
          templates: h.accounts.state.value.templates,
          accounts: [
            vmSummary(const NativeAccountIdentity('alpha'), name: 'Alpha'),
            vmSummary(
              const AcpAccountIdentity('gamma'),
              name: 'Gamma',
              queryUsage: true,
              acpTemplate: AcpProviderView.antigravity,
            ),
          ],
        ),
      );
      h.acp.install.publish(
        AccountResource(
          stamp: vmStamp,
          value: const AcpInstallSnapshotView(
            revision: 1,
            updatedAt: 10,
            installations: [
              AcpInstallEntryView(
                provider: AcpProviderView.antigravity,
                state: AcpInstallReadyState(
                  operationId: 'prep-145',
                  server: installed145,
                ),
                installed: installed145,
                update: AcpInstallUpdateAvailableState(
                  checkedAt: 10,
                  latest: release152,
                ),
              ),
            ],
          ),
        ),
      );
      h.acp.auth.publish(
        AccountResource(
          stamp: vmStamp,
          value: const AcpAuthSnapshotView(
            revision: 1,
            updatedAt: 10,
            accounts: [
              AcpAuthAccountView(
                connection: AcpConnectionReadyState(),
                accountId: 'gamma',
                connectionRevision: 1,
                state: AcpVerifiedState(
                  checkedAt: 10,
                  server: AcpServerInfoView(
                    name: 'agy_acp_server',
                    version: '1.4.5',
                  ),
                ),
              ),
            ],
          ),
        ),
      );

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: h.container,
          child: MaterialApp(
            locale: const Locale('en'),
            theme: pureStudioTheme(locale: const Locale('en')),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: const Scaffold(body: AccountsConnector(visible: true)),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(AccountListItem), findsNWidgets(2));
      expect(
        find.byKey(ValueKey(AccountViewKeyValues.rowUpgrade('acp', 'gamma'))),
        findsOneWidget,
      );

      // Filter to Native only, then back to ACP.
      await tester.tap(
        find.byKey(ValueKey(AccountViewKeyValues.categoryChip('native'))),
      );
      await tester.pumpAndSettle();
      expect(find.byType(AccountListItem), findsOneWidget);
      expect(find.text('Alpha'), findsOneWidget);
      expect(find.text('Gamma'), findsNothing);

      await tester.tap(
        find.byKey(ValueKey(AccountViewKeyValues.categoryChip('acp'))),
      );
      await tester.pumpAndSettle();
      expect(find.byType(AccountListItem), findsOneWidget);
      expect(find.text('Gamma'), findsOneWidget);

      // Trigger inline upgrade button.
      await tester.tap(
        find.byKey(ValueKey(AccountViewKeyValues.rowUpgrade('acp', 'gamma'))),
      );
      await tester.pump();
      expect(h.acp.starts, hasLength(1));

      // Upgrading progress shows cancel button; tapping it invokes cancelPreparation.
      h.acp.install.publish(
        AccountResource(
          stamp: vmStamp,
          value: const AcpInstallSnapshotView(
            revision: 2,
            updatedAt: 12,
            installations: [
              AcpInstallEntryView(
                provider: AcpProviderView.antigravity,
                state: AcpDownloadingState(
                  operationId: 'up-152',
                  release: release152,
                  progress: AcpInstallProgressView(
                    completedBytes: 2048,
                    totalBytes: 4096,
                    bytesPerSecond: 1024,
                  ),
                ),
                installed: installed145,
                update: AcpInstallUpdateAvailableState(
                  checkedAt: 10,
                  latest: release152,
                ),
              ),
            ],
          ),
        ),
      );
      await tester.pump();
      final cancelFinder = find.byKey(
        ValueKey(AccountViewKeyValues.rowCancelUpgrade('acp', 'gamma')),
      );
      expect(cancelFinder, findsOneWidget);
      await tester.tap(cancelFinder);
      await tester.pump();
      expect(h.acp.cancels, hasLength(1));
      h.acp.cancels.single.complete(h.acp.install.value.value!);
      h.acp.starts.single.complete(h.acp.install.value.value!);
      await tester.pumpAndSettle();

      // Pending switch state renders active-session hint.
      h.acp.install.publish(
        AccountResource(
          stamp: vmStamp,
          value: const AcpInstallSnapshotView(
            revision: 3,
            updatedAt: 15,
            installations: [
              AcpInstallEntryView(
                provider: AcpProviderView.antigravity,
                state: AcpInstallReadyState(
                  operationId: 'up-152',
                  server: installed152,
                ),
                installed: installed152,
                update: AcpInstallUpdateUpToDateState(
                  checkedAt: 15,
                  latestVersion: '1.5.2',
                ),
              ),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.text(AppLocalizationsEn().acpUpgradePendingSwitch('1.5.2')),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'AcpAccountPanel keeps single unique keys when AcpManagedVersionCard is shown',
    (tester) async {
      final actions = <AcpAccountAction>[];
      Widget panelFor(
        AcpCardUpgradePresentation upgrade,
        List<AcpAccountAction> availableActions,
      ) => MaterialApp(
        locale: const Locale('en'),
        theme: pureStudioTheme(locale: const Locale('en')),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: SingleChildScrollView(
            child: AcpAccountPanel(
              value: AcpAccountPresentation(
                phase: AcpPresentationPhase.connected,
                status: 'Connected',
                primaryAction: availableActions.firstOrNull,
                availableActions: availableActions,
                upgrade: upgrade,
              ),
              onAction: actions.add,
              onLoginMethodChanged: (_) {},
            ),
          ),
        ),
      );

      await tester.pumpWidget(
        panelFor(
          const AcpCardUpgradePresentation(
            phase: AcpUpgradePhase.updateAvailable,
            installedVersion: '1.4.5',
            runningVersion: '1.4.5',
            latestVersion: '1.5.2',
            canUpgrade: true,
            canCheck: true,
          ),
          const [
            AcpAccountAction.upgrade,
            AcpAccountAction.checkUpdate,
            AcpAccountAction.check,
          ],
        ),
      );
      expect(
        find.byKey(ValueKey(AccountViewKeyValues.acpAction('upgrade'))),
        findsOneWidget,
      );
      expect(
        find.byKey(ValueKey(AccountViewKeyValues.acpAction('checkUpdate'))),
        findsOneWidget,
      );

      await tester.pumpWidget(
        panelFor(
          const AcpCardUpgradePresentation(
            phase: AcpUpgradePhase.incompatibleMajor,
            installedVersion: '1.5.2',
            runningVersion: '1.5.2',
            latestVersion: '2.0.0',
            canCheck: true,
          ),
          const [AcpAccountAction.checkUpdate, AcpAccountAction.check],
        ),
      );
      expect(
        find.byKey(ValueKey(AccountViewKeyValues.acpAction('checkUpdate'))),
        findsOneWidget,
      );

      await tester.pumpWidget(
        panelFor(
          const AcpCardUpgradePresentation(
            phase: AcpUpgradePhase.upgrading,
            installedVersion: '1.4.5',
            runningVersion: '1.4.5',
            latestVersion: '1.5.2',
            canCancel: true,
          ),
          const [AcpAccountAction.cancelPreparation, AcpAccountAction.check],
        ),
      );
      expect(
        find.byKey(
          ValueKey(AccountViewKeyValues.acpAction('cancelPreparation')),
        ),
        findsOneWidget,
      );
    },
  );
}
