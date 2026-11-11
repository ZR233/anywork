import 'package:anywork_client/accounts.dart';
import 'package:anywork_client/accounts_ports.dart';
import 'package:anywork_client/studio_client.dart';
import 'package:test/test.dart';

import 'support/accounts_test_runtime.dart';

final class _Transport extends AccountsTestTransport {
  @override
  Future<AccountCatalogView> loadAccountCatalog() async =>
      const AccountCatalogView.empty();
}

const _capabilities = AccountCapabilities(
  setDefault: false,
  edit: true,
  remove: true,
  queryUsage: false,
  syncModels: false,
  editModels: false,
  acpAuth: true,
);

AccountSummary _acp(String id, bool enabled) => AccountSummary(
  identity: AcpAccountIdentity(id),
  name: id,
  isDefault: false,
  acpEnabled: enabled,
  acpConnectionRevision: 7,
  capabilities: _capabilities,
);

void main() {
  test(
    'summaries retain enabled values and diagnostics through unrelated updates',
    () async {
      final runtime = AccountsTestRuntime(_Transport());
      addTearDown(runtime.close);
      final diagnostics = [
        const AcpDefinitionDiagnosticView(
          fileName: 'bad.toml',
          message: 'ACP定义无法加载，请检查文件格式和必填字段。',
        ),
      ];
      final summaries = [
        _acp('enabled', true),
        _acp('disabled', false),
        const AccountSummary(
          identity: NativeAccountIdentity('native'),
          name: 'Native',
          isDefault: false,
          capabilities: AccountCapabilities(
            setDefault: true,
            edit: true,
            remove: true,
            queryUsage: false,
            syncModels: false,
            editModels: true,
            acpAuth: false,
          ),
        ),
      ];
      final frame = AccountSummariesFrame(
        testStamp('settings', 1),
        summaries,
        acpDiagnostics: diagnostics,
      );
      diagnostics.clear();
      summaries.clear();
      runtime.domains.acceptFrame(frame);
      final state = runtime.domains.accounts.state.value;
      expect(state.accounts.map((account) => account.acpEnabled), [
        true,
        false,
        null,
      ]);
      expect(state.accounts.take(2).map((account) => account.credentialReady), [
        null,
        null,
      ]);
      expect(state.acpDiagnostics.single.fileName, 'bad.toml');
      expect(state.acpDiagnostics.single.message, 'ACP定义无法加载，请检查文件格式和必填字段。');
      expect(() => state.acpDiagnostics.clear(), throwsUnsupportedError);
      expect(() => frame.acpDiagnostics.clear(), throwsUnsupportedError);
      expect(runtime.domains.acp.auth.value.loaded, isFalse);

      await runtime.domains.accounts.loadTemplates();
      expect(
        runtime.domains.accounts.state.value.acpDiagnostics.single.fileName,
        'bad.toml',
      );
      runtime.domains.adoptOwnerEpoch('next-owner');
      final stale = runtime.domains.accounts.state.value;
      expect(stale.stale, isTrue);
      expect(stale.acpDiagnostics.single.fileName, 'bad.toml');

      runtime.domains.acceptFrame(
        AccountSummariesFrame(testStamp('settings', 1, epoch: 'next-owner'), [
          _acp('disabled', true),
        ]),
      );
      final replaced = runtime.domains.accounts.state.value;
      expect(replaced.loaded, isTrue);
      expect(replaced.accounts.single.acpEnabled, isTrue);
      expect(replaced.acpDiagnostics, isEmpty);
    },
  );

  test('observation failure preserves the last diagnostic snapshot', () async {
    final transport = _Transport();
    final runtime = AccountsTestRuntime(transport);
    addTearDown(runtime.close);
    transport.baselines[const AccountSummariesTarget()] = AccountSummariesFrame(
      testStamp('settings', 1),
      [_acp('enabled', true)],
      acpDiagnostics: const [
        AcpDefinitionDiagnosticView(
          fileName: 'bad.toml',
          message: 'safe message',
        ),
      ],
    );
    final state = runtime.domains.accounts.state;
    final loaded = state.waitFor((value) => value.loaded);
    final demand = runtime.domains.accounts.observeSummaries();
    addTearDown(demand.release);
    await loaded;
    final failure = state.waitFor((value) => value.failure != null);
    final observation = await transport.attachedAccount(
      const AccountSummariesTarget(),
    );
    observation.fail(
      const StudioFailure(
        code: StudioFailureCode.unavailable,
        message: 'observation ended',
        retryable: true,
        correlationId: 'service-directory-test',
      ),
    );
    final failed = await failure;
    expect(failed.acpDiagnostics.single.fileName, 'bad.toml');
    expect(failed.accounts.single.acpEnabled, isTrue);
  });
}
