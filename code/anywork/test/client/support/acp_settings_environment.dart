import 'package:anywork/src/app/app_bindings.dart';
import 'package:anywork/src/app/theme/material3_theme.dart';
import 'package:anywork/src/features/settings/accounts/connectors/accounts_connector.dart';
import 'package:anywork/src/features/settings/accounts/connectors/acp_account_details_connector.dart';
import 'package:anywork/src/features/settings/accounts/connectors/acp_account_editor_connector.dart';
import 'package:anywork/src/features/settings/accounts/state/acp_account_target.dart';
import 'package:anywork/src/features/settings/accounts/view_models/accounts_view_model.dart';
import 'package:anywork/src/features/settings/accounts/view_models/acp_account_auth_view_model.dart';
import 'package:anywork/src/features/settings/accounts/view_models/acp_account_editor_view_model.dart';
import 'package:anywork/src/features/settings/state/settings_navigation_state.dart';
import 'package:anywork/src/features/settings/view_models/settings_navigation_view_model.dart';
import 'package:anywork/src/l10n/app_localizations.dart';
import 'package:anywork_client/acp_ports.dart';
import 'package:anywork_client/configuration_ports.dart';
import 'package:anywork_client/operations_ports.dart';
import 'package:anywork_client/resources_ports.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../../anywork_client/test/support/acp_port_fixture.dart';
import 'pump_client_future.dart';
import 'settings_accounts_fixture.dart';

const acpSettingsTemplate = AcpAccountTemplate(
  provider: AcpProvider.antigravity,
  displayName: 'Antigravity',
  description: 'Managed ACP server',
  iconKey: 'antigravity',
  supportedVersion: '1.4.1',
  installUrl: 'https://example.invalid/install',
  termsUrl: 'https://example.invalid/terms',
  automaticInstall: AcpInstallAvailability.available(target: 'linux-x86_64'),
);

AcpAccountSettings acpSettingsAccount(String id, {int revision = 1}) =>
    AcpAccountSettings(
      accountId: id,
      name: id.toUpperCase(),
      provider: AcpProvider.antigravity,
      connectionRevision: revision,
    );

AcpInstalledServer acpSettingsServer() => AcpInstalledServer(
  installationId: 'installation-1',
  release: acpRelease(),
  program: '/managed/agy-acp-server',
  readyAt: 100,
  reused: false,
);

/// Same real configuration/model/usage assembly as settings_acp_accounts_test,
/// plus the SDK's scripted native ACP port. No form, notice, admission, claim,
/// canonical projection or command settlement is implemented here.
final class AcpSettingsEnvironment {
  AcpSettingsEnvironment._(this.settings, this.acp) {
    container = ProviderContainer(
      retry: (_, _) => null,
      overrides: [
        configurationRepositoryProvider.overrideWithValue(
          settings.configuration,
        ),
        modelsRepositoryProvider.overrideWithValue(settings.models),
        accountUsageRepositoryProvider.overrideWithValue(settings.usage),
        acpAuthRepositoryProvider.overrideWithValue(acp.auth),
        acpInstallRepositoryProvider.overrideWithValue(acp.install),
      ],
    );
  }

  static Future<AcpSettingsEnvironment> open(
    WidgetTester tester, {
    List<AcpAccountSettings> accounts = const [],
    ResourceBudget? acpBudget,
  }) async {
    final settings = SettingsAccountsFixture(accountCount: 0);
    settings.configurationPort.declareAcpMaterial(
      revision: 1,
      delegateBase: true,
      rows: [
        for (final account in accounts)
          AcpAccountConfigurationRead(
            accountId: ReadText.inline(text: account.accountId),
            name: ReadText.inline(text: account.name),
            provider: account.provider,
            connectionRevision: account.connectionRevision,
          ),
      ],
    );
    await pumpClientFuture(
      tester,
      settings.establish(),
      'ACP Settings real repositories',
    );
    final environment = AcpSettingsEnvironment._(
      settings,
      AcpPortFixture(budget: acpBudget),
    );
    await tester.binding.setSurfaceSize(const Size(1280, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    addTearDown(() => environment.close(tester));
    return environment;
  }

  final SettingsAccountsFixture settings;
  final AcpPortFixture acp;
  late final ProviderContainer container;
  bool _closed = false;

  // Unknown is protected original evidence, not a cleanup success. A test that
  // deliberately loses a reply declares its exact original unresolved owner.
  final expectedUnresolvedInstallOperations = <OperationId>[];
  final expectedUnresolvedAuthOperations = <OperationId>[];

  Widget _harness(Widget child) => UncontrolledProviderScope(
    container: container,
    child: MaterialApp(
      theme: pureStudioTheme(),
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: child),
    ),
  );

  Future<void> mountEditor(
    WidgetTester tester,
    AcpAccountEditorTarget target,
  ) async {
    await tester.pumpWidget(
      _harness(
        AcpAccountEditorConnector(
          target: target,
          visible: true,
          onCancel: () {},
          onOpenUrl: (_) {},
          onSaved: (_, _, _) =>
              fail('Preparation cannot save or authenticate an account'),
        ),
      ),
    );
    await pumpClientFuture(
      tester,
      container.read(acpAccountEditorViewModelProvider(target).future),
      'real ACP editor VM',
    );
    await tester.pump();
  }

  Future<void> mountDetails(
    WidgetTester tester,
    AcpAccountSettings account,
  ) async {
    await tester.pumpWidget(
      _harness(
        AcpAccountDetailsConnector(
          account: account,
          template: acpSettingsTemplate,
          visible: true,
          onBack: () {},
          onEdit: () {},
          onRemove: () async {},
        ),
      ),
    );
    await pumpClientFuture(
      tester,
      container.read(
        acpAccountAuthViewModelProvider(
          AcpAccountTarget(
            accountId: account.accountId,
            connectionRevision: account.connectionRevision,
            provider: account.provider,
          ),
        ).future,
      ),
      'real ACP auth VM',
    );
    await tester.pump();
  }

  Future<ScriptedAcpInstallFeed> installBaseline(
    WidgetTester tester,
    AcpInstallState state,
  ) async {
    final feed = await pumpClientFuture(
      tester,
      acp.port.installFeedOpened(0),
      'visible ACP install feed',
    );
    await pumpClientFuture(
      tester,
      feed.publishBaseline(acpInstallSnapshot(revision: 1, state: state)),
      'ACP install baseline ACK',
    );
    await tester.pump();
    return feed;
  }

  Future<ScriptedAcpAuthFeed> authBaseline(
    WidgetTester tester,
    AcpAuthSnapshot snapshot,
  ) async {
    final feed = await pumpClientFuture(
      tester,
      acp.port.authFeedOpened(0),
      'visible ACP auth feed',
    );
    await pumpClientFuture(
      tester,
      feed.publishBaseline(snapshot),
      'ACP auth baseline ACK',
    );
    await tester.pump();
    return feed;
  }

  Future<ScriptedAcpAuthFeed> mountAccounts(
    WidgetTester tester,
    AcpAuthSnapshot snapshot,
  ) async {
    await pumpClientFuture(
      tester,
      container.read(settingsNavigationViewModelProvider.future),
      'Settings navigation',
    );
    container
        .read(settingsNavigationViewModelProvider.notifier)
        .enter(SettingsTab.accounts);
    await tester.pumpWidget(_harness(const AccountsConnector()));
    final ready = container.read(accountsViewModelProvider.future);
    final page = await pumpClientFuture(
      tester,
      settings.configurationPort.acpPage(0),
      'ACP account directory page',
    );
    page.complete();
    await pumpClientUntil(
      tester,
      () => acp.port.catalogReads.isNotEmpty,
      'native ACP template read',
    );
    acp.port.answerCatalogRead(
      0,
      const AcpAccountCatalog(templates: [acpSettingsTemplate]),
    );
    await pumpClientFuture(tester, ready, 'real Accounts VM');
    return authBaseline(tester, snapshot);
  }

  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(_harness(const SizedBox.shrink()));
    await pumpClientFuture(
      tester,
      container.pump(),
      'ACP page provider disposal',
    );
  }

  Future<void> close(WidgetTester tester) async {
    if (_closed) return;
    _closed = true;
    await unmount(tester);
    container.dispose();
    const failure = StudioFailure(
      code: StudioFailureCode.cancelled,
      message: 'ACP test native boundary closed',
      retryable: false,
      correlationId: 'acp-test-close',
    );
    const refused = CommandDispatchFailure.rejected(failure: failure);
    for (final call in [
      ...acp.port.installStarts,
      ...acp.port.installCancels,
    ]) {
      if (!call.reply.isCompleted) call.reject(refused);
    }
    for (final call in [...acp.port.authStarts, ...acp.port.authCancels]) {
      if (!call.reply.isCompleted) call.reject(refused);
    }
    for (final reply in [
      ...acp.port.authReads,
      ...acp.port.installReads,
      ...acp.port.catalogReads,
    ]) {
      if (!reply.isCompleted) reply.completeError(failure);
    }
    expect(
      (await pumpClientFuture(
        tester,
        settings.close(),
        'Settings owner joins',
      )).unresolved,
      isEmpty,
    );
    final auth = await pumpClientFuture(
      tester,
      acp.auth.close(),
      'ACP auth owner joins',
    );
    final install = await pumpClientFuture(
      tester,
      acp.install.close(),
      'ACP install owner joins',
    );
    expect(auth.unresolved.map((owner) => owner.owner).toList(), [
      for (final id in expectedUnresolvedAuthOperations)
        'acp:action:${id.value}',
    ]);
    expect(install.unresolved.map((owner) => owner.owner).toList(), [
      for (final id in expectedUnresolvedInstallOperations)
        'acp:action:${id.value}',
    ]);
    for (final owner in [...auth.unresolved, ...install.unresolved]) {
      expect(owner.issues.single.recovery, CleanupRecovery.terminal);
    }
    for (final feed in [
      ...acp.port.authFeeds.map((feed) => feed.feed.closeCalls),
      ...acp.port.installFeeds.map((feed) => feed.feed.closeCalls),
    ]) {
      expect(
        feed,
        greaterThan(0),
        reason: 'Application cleanup joins the original native feed',
      );
    }
    expect(settings.budget.usage, isEmpty);
    if (expectedUnresolvedAuthOperations.isEmpty &&
        expectedUnresolvedInstallOperations.isEmpty) {
      expect(acp.budget.usage, isEmpty);
    } else {
      expect(
        acp.budget.usage,
        isNotEmpty,
        reason: 'Unknown evidence must not be relabeled Clean',
      );
    }
    acp.operations.seal();
  }
}
