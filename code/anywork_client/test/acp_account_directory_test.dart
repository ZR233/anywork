import 'package:anywork_client/studio_client.dart';
import 'package:anywork_client/accounts.dart';
import 'package:anywork_client/accounts_ports.dart';
import 'package:anywork_client/model_directory.dart';

import 'support/accounts_test_runtime.dart';

import 'package:test/test.dart';

const _nativeTemplate = AccountTemplateView(
  id: 'openai-compatible',
  displayName: 'OpenAI API 兼容',
  description: 'Custom compatible API',
  baseUrl: 'http://localhost:11434/v1',
  credentialLabel: 'API Key',
  credentialEnv: 'OPENAI_COMPATIBLE_KEY',
  modelCatalogId: 'openai-compatible',
  protocol: 'open_ai_compatible',
  suggestedModelId: 'gpt',
);

const _nativeCatalog = AccountCatalogView(
  schemaVersion: 1,
  revision: 'catalog-1',
  templates: [_nativeTemplate],
  modelCatalogs: {
    'openai-compatible': [
      AccountModelView(
        modelId: 'gpt',
        displayName: 'GPT',
        reasoningEfforts: ['low', 'high'],
      ),
    ],
  },
);

const _acpTemplate = AcpAccountTemplateView(
  provider: AcpProviderView.antigravity,
  displayName: 'Antigravity',
  description: 'Google Antigravity official ACP server',
  iconKey: 'antigravity',
  supportedVersion: '1.4.1',
  installUrl: 'https://example.invalid/antigravity',
);

const _acpCatalog = AcpAccountCatalogView(templates: [_acpTemplate]);

AccountSettingsView _nativeAccount(String id) => AccountSettingsView(
  id: id,
  name: 'Native',
  templateId: 'openai-compatible',
  protocol: 'open_ai_compatible',
  baseUrl: 'http://localhost:11434/v1',
  defaultModelId: 'gpt',
  models: _nativeCatalog.modelCatalogs['openai-compatible']!,
  status: 'ready',
  usageLabel: '',
);

final class _DirectoryTransport extends AccountsTestTransport {
  @override
  Future<AccountCatalogView> loadAccountCatalog() async => _nativeCatalog;
  @override
  Future<AcpAccountCatalogView> loadAcpAccountCatalog() async => _acpCatalog;
}

AccountsTestRuntime _runtime({
  List<AccountSettingsView> native = const [],
  List<AcpAccountSettingsView> acp = const [],
}) {
  final runtime = AccountsTestRuntime(_DirectoryTransport());
  runtime.seed(
    SettingsStateSnapshot(revision: 1, accounts: native, acpAccounts: acp),
  );
  addTearDown(runtime.close);
  return runtime;
}

void _apply(AccountsTestRuntime runtime, AcpAuthSnapshotView snapshot) =>
    runtime.domains.acceptFrame(
      AcpAuthFrame(testStamp('acp-auth', snapshot.revision), snapshot),
    );
AcpAuthStateView _stateOf(
  AccountsTestRuntime runtime,
  String id,
  int connection,
) => (runtime.domains.acp.auth.value.value ?? const AcpAuthSnapshotView.empty())
    .stateOf(id, connectionRevision: connection);

AcpAccountSettingsView _acpAccount(
  String id, {
  int connectionRevision = 3,
  AcpProviderView provider = AcpProviderView.antigravity,
}) => AcpAccountSettingsView(
  accountId: id,
  name: 'Antigravity',
  provider: provider,
  connectionRevision: connectionRevision,
);

AcpAuthSnapshotView _auth({
  int revision = 1,
  List<AcpAuthAccountView> accounts = const [],
}) =>
    AcpAuthSnapshotView(revision: revision, updatedAt: 100, accounts: accounts);

void main() {
  test('summaries retain both typed branches while templates and auth remain separately owned', () async {
    final runtime = _runtime(
      native: [_nativeAccount('native-1')],
      acp: [_acpAccount('acp-1')],
    );
    await runtime.domains.accounts.loadTemplates();
    await runtime.domains.acp.loadTemplates();
    _apply(
      runtime,
      _auth(
        accounts: const [
          AcpAuthAccountView(
            accountId: 'acp-1',
            connectionRevision: 3,
            state: AcpVerifiedState(
              checkedAt: 90,
              server: AcpServerInfoView(name: 'antigravity', version: '1.2.3'),
            ),
          ),
        ],
      ),
    );
    final accounts = runtime.domains.accounts.state.value;
    expect(accounts.accounts.map((entry) => entry.identity.accountId), [
      'native-1',
      'acp-1',
    ]);
    expect(accounts.accounts.first.identity, isA<NativeAccountIdentity>());
    expect(accounts.accounts.last.identity, isA<AcpAccountIdentity>());
    expect(accounts.templates.templates.single.displayName, 'OpenAI API 兼容');
    final template = runtime.domains.acp.templates.value.template(
      AcpProviderView.antigravity,
    )!;
    expect(template.displayName, 'Antigravity');
    expect(template.provider, AcpProviderView.antigravity);
    expect(template.supportedVersion, '1.4.1');
    expect(template, _acpTemplate);
    expect(_stateOf(runtime, 'acp-1', 3), isA<AcpVerifiedState>());
    expect(runtime.domains.acp.auth.value.stamp!.revision, 1);
    expect(
      (runtime.domains.accounts
                  .details(const NativeAccountIdentity('native-1'))
                  .value
                  .value!
              as NativeAccountDetails)
          .identity
          .accountId,
      'native-1',
    );
  });

  test('an account with no auth observation is unchecked, never verified', () {
    final runtime = _runtime(acp: [_acpAccount('acp-1')]);
    expect(runtime.domains.acp.auth.value.loaded, isFalse);
    expect(_stateOf(runtime, 'acp-1', 3), isA<AcpUncheckedState>());
    _apply(runtime, _auth());
    expect(runtime.domains.acp.auth.value.loaded, isTrue);
    expect(_stateOf(runtime, 'acp-1', 3), isA<AcpUncheckedState>());
    expect(
      const AcpAuthSnapshotView.empty().stateOf('acp-1', connectionRevision: 3),
      isA<AcpUncheckedState>(),
    );
  });

  test('same spelling is not a cross-kind identity collision or a native route candidate', () {
    final runtime = _runtime(
      native: [_nativeAccount('antigravity')],
      acp: [_acpAccount('antigravity')],
    );
    final accounts = runtime.domains.accounts.state.value;
    expect(accounts.accounts.map((value) => value.identity).toSet(), {
      const NativeAccountIdentity('antigravity'),
      const AcpAccountIdentity('antigravity'),
    });
    expect(
      accounts.account(const NativeAccountIdentity('antigravity'))!.name,
      'Native',
    );
    expect(
      accounts.account(const AcpAccountIdentity('antigravity'))!.name,
      'Antigravity',
    );
    expect(
      runtime.domains.accounts
          .details(const NativeAccountIdentity('antigravity'))
          .value
          .value,
      isA<NativeAccountDetails>(),
    );
    expect(
      runtime.domains.accounts
          .details(const AcpAccountIdentity('antigravity'))
          .value
          .value,
      isA<AcpAccountDetails>(),
    );
    expect(
      modelSelectionAccounts(
        accounts,
        runtime.domains.models.state.value,
      ).map((value) => value.id),
      ['antigravity'],
    );
  });

  test(
    'an auth observation from an older connection identity is not reused',
    () {
      final runtime = _runtime(
        acp: [_acpAccount('acp-1', connectionRevision: 3)],
      );
      final auth = _auth(
        accounts: const [
          AcpAuthAccountView(
            accountId: 'acp-1',
            connectionRevision: 2,
            state: AcpVerifiedState(
              checkedAt: 90,
              server: AcpServerInfoView(name: 'antigravity', version: '1.2.3'),
            ),
          ),
        ],
      );
      _apply(runtime, auth);
      expect(_stateOf(runtime, 'acp-1', 3), isA<AcpUncheckedState>());
      expect(
        runtime.domains.acp.auth.value.value!.account(
          'acp-1',
          connectionRevision: 2,
        ),
        isNotNull,
      );
      expect(
        runtime.domains.acp.auth.value.value!.account(
          'acp-1',
          connectionRevision: 3,
        ),
        isNull,
      );
    },
  );

  test(
    'closing is a busy nonterminal state that still carries its operation',
    () {
      const closing = AcpClosingState(operationId: 'op-close');
      expect(closing.isBusy, isTrue);
      expect(closing.isSettled, isFalse);
      expect(closing.operationId, 'op-close');
      expect(closing.failure, isNull);
      expect(const AcpCancelledState().isSettled, isTrue);
      expect(
        const AcpVerifiedState(checkedAt: 1, server: null).isSettled,
        isTrue,
      );
    },
  );

  test('unauthorized method kinds are neither agent nor terminal', () {
    const methods = [
      AcpAuthMethodView(
        id: 'agent',
        name: 'Browser',
        kind: AcpAuthMethodKindView.agent,
      ),
      AcpAuthMethodView(
        id: 'terminal',
        name: 'Terminal',
        kind: AcpAuthMethodKindView.terminal,
      ),
      AcpAuthMethodView(
        id: 'future',
        name: 'Future',
        kind: AcpAuthMethodKindView.unsupported,
      ),
    ];
    const required = AcpRequiredState(server: null, methods: methods);
    expect(required.agentMethods.map((method) => method.id), ['agent']);
    expect(required.hasNoMethods, isFalse);
    expect(required.terminalOnly, isFalse);
    expect(required.unsupportedOnly, isFalse);
    expect(methods.last.isAgent, isFalse);
    expect(methods.last.isTerminal, isFalse);
    expect(methods.last.isUnsupported, isTrue);

    const unsupportedOnly = AcpRequiredState(
      server: null,
      methods: [
        AcpAuthMethodView(
          id: 'future',
          name: 'Future',
          kind: AcpAuthMethodKindView.unsupported,
        ),
      ],
    );
    expect(unsupportedOnly.terminalOnly, isFalse);
    expect(unsupportedOnly.unsupportedOnly, isTrue);

    const empty = AcpRequiredState(server: null);
    expect(empty.hasNoMethods, isTrue);
    expect(empty.terminalOnly, isFalse);
    expect(empty.unsupportedOnly, isFalse);
  });

  test('unknown ACP provider wire values are not resolved silently', () {
    expect(
      AcpProviderView.fromWire('antigravity'),
      AcpProviderView.antigravity,
    );
    expect(AcpProviderView.fromWire('other'), isNull);
  });

  test('required state exposes only agent methods as login choices', () {
    const required = AcpRequiredState(
      server: AcpServerInfoView(name: 'antigravity', version: '1.2.3'),
      methods: [
        AcpAuthMethodView(
          id: 'oauth',
          name: 'Sign in with browser',
          kind: AcpAuthMethodKindView.agent,
        ),
        AcpAuthMethodView(
          id: 'terminal',
          name: 'Terminal login',
          kind: AcpAuthMethodKindView.terminal,
        ),
      ],
    );

    expect(required.agentMethods.map((method) => method.id), ['oauth']);
    expect(required.terminalOnly, isFalse);
    expect(required.isBusy, isFalse);

    const terminalOnly = AcpRequiredState(
      server: AcpServerInfoView(name: 'antigravity', version: '1.2.3'),
      methods: [
        AcpAuthMethodView(
          id: 'terminal',
          name: 'Terminal login',
          kind: AcpAuthMethodKindView.terminal,
        ),
      ],
    );
    expect(terminalOnly.agentMethods, isEmpty);
    expect(terminalOnly.terminalOnly, isTrue);
  });

  test('busy states expose the operation that cancel must hit', () {
    expect(const AcpCheckingState(operationId: 'op-1').isBusy, isTrue);
    expect(const AcpCheckingState(operationId: 'op-1').operationId, 'op-1');
    expect(
      const AcpAuthenticatingState(
        operationId: 'op-2',
        methodId: 'oauth',
      ).isBusy,
      isTrue,
    );
    expect(const AcpVerifyingState(operationId: 'op-3').operationId, 'op-3');
    expect(const AcpCancellingState(operationId: 'op-4').operationId, 'op-4');
    expect(const AcpCancelledState().isBusy, isFalse);
    expect(const AcpCancelledState().operationId, isNull);
  });
}
