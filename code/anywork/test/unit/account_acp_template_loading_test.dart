import 'dart:async';

import 'package:anywork/src/features/settings/accounts/state/account_presentations.dart';
import 'package:anywork/src/features/settings/accounts/state/account_view_state.dart';
import 'package:anywork/src/features/settings/accounts/view_models/account_projection.dart';
import 'package:anywork/src/features/settings/accounts/view_models/acp_account_view_model.dart';
import 'package:anywork/src/presentation/providers/account_domains.dart';
import 'package:anywork_client/accounts_ports.dart';
import 'package:anywork_client/lifecycle.dart';
import 'package:anywork_client/studio_client.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../anywork_client/test/support/accounts_test_runtime.dart';
import '../support/observed.dart';

const _failure = StudioFailure(
  code: StudioFailureCode.unavailable,
  message: 'Catalog temporarily unavailable',
  retryable: true,
  correlationId: 'catalog-query',
);
const _template = AcpAccountTemplateView(
  provider: AcpProviderView.antigravity,
  displayName: 'Antigravity',
  description: 'Synthetic directory response',
  iconKey: 'antigravity',
  supportedVersion: '1.4.5',
  installUrl: 'https://example.invalid/guide',
);
const _key = AccountAcpKey(
  target: AccountDisplayKey(kind: AccountKind.acp, id: 'template-loading'),
  templateId: 'antigravity',
  connectionRevision: 0,
  editorId: 'template-loading-editor',
  creating: true,
);

void main() {
  test('a synchronous catalog port failure settles through the real ACP service and retry succeeds', () async {
    final port = _CatalogTransport();
    final runtime = AccountsTestRuntime(port);
    runtime.seed(SettingsStateSnapshot(revision: 1));
    final container = ProviderContainer(
      overrides: [
        accountsRepositoryProvider.overrideWithValue(runtime.domains.accounts),
        acpServiceProvider.overrideWithValue(runtime.domains.acp),
      ],
    );
    final provider = acpAccountViewModelProvider(_key);
    final subscription = container.listen(provider, (_, _) {});
    addTearDown(() async {
      if (!port.success.isCompleted) {
        port.success.complete(
          const AcpAccountCatalogView(templates: [_template]),
        );
      }
      subscription.close();
      container.dispose();
      final report = await runtime.close();
      expect(report.unresolved, isEmpty);
      final transportReport = await port.lifecycleScope.close(
        budget: ClientCloseBudget(const Duration(seconds: 1)),
      );
      expect(transportReport.unresolved, isEmpty);
    });

    final owner = container.read(provider.notifier);
    // Join the initial attempt so the production service's Future error is
    // observed before checking the VM's settled failure and retry behavior.
    await owner.retry();
    await Future.wait([
      untilObserved(
        runtime.domains.acp.auth,
        (value) => value.loaded && !value.stale,
      ),
      untilObserved(
        runtime.domains.acp.install,
        (value) => value.loaded && !value.stale,
      ),
    ]);
    owner.setStrings(const AccountStrings({'failed': 'Unexpected error'}));
    var panel = container.read(provider).requireValue.panel;
    expect(port.calls, 1);
    expect(panel.error, _failure.message);
    expect(panel.availableActions, contains(AcpAccountAction.retry));
    expect(runtime.domains.acp.templates.value.templates, isEmpty);

    port.fail = false;
    final first = owner.retry();
    final second = owner.retry();
    expect(port.calls, 2);
    port.success.complete(const AcpAccountCatalogView(templates: [_template]));
    await Future.wait([first, second]);
    panel = container.read(provider).requireValue.panel;
    expect(port.calls, 2);
    expect(panel.error, isNull);
    expect(panel.availableActions, isNot(contains(AcpAccountAction.retry)));
    expect(panel.availableActions, contains(AcpAccountAction.openGuide));
    expect(
      runtime.domains.acp.templates.value.templates.single,
      same(_template),
    );
    expect(
      owner.documentationUrl(AcpAccountAction.openGuide),
      _template.installUrl,
    );
  });
}

// Only the external port is scripted. CommandLane, AcpServiceImpl, observations
// and the presentation VM execute their production paths.
class _CatalogTransport extends AccountsTestTransport {
  _CatalogTransport() {
    baselines[const AcpAuthTarget()] = AcpAuthFrame(
      testStamp('acp-auth', 1),
      const AcpAuthSnapshotView.empty(),
    );
    baselines[const AcpInstallTarget()] = AcpInstallFrame(
      testStamp('acp-install', 1),
      const AcpInstallSnapshotView.empty(),
    );
  }

  bool fail = true;
  int calls = 0;
  final success = Completer<AcpAccountCatalogView>();

  @override
  Future<AcpAccountCatalogView> loadAcpAccountCatalog() {
    calls++;
    if (fail) throw _failure;
    return success.future;
  }
}
