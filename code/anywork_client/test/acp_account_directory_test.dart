import 'package:anywork_client/studio_client.dart';
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

AccountSettingsView _nativeAccount(String id) =>
    _nativeCatalog.template('openai-compatible')!.createAccount(id, const [
      AccountModelView(
        modelId: 'gpt',
        displayName: 'GPT',
        reasoningEfforts: ['low', 'high'],
      ),
    ]);

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
  test('templates and entries aggregate both branches without guessing', () {
    final directory = AccountDirectoryView.from(
      nativeAccounts: [_nativeAccount('native-1')],
      acpAccounts: [_acpAccount('acp-1')],
      nativeCatalog: _nativeCatalog,
      acpCatalog: _acpCatalog,
      auth: _auth(
        accounts: [
          const AcpAuthAccountView(
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

    expect(directory.entries.map((entry) => entry.id), ['native-1', 'acp-1']);
    expect(directory.templates.map((choice) => choice.displayName), [
      'OpenAI API 兼容',
      'Antigravity',
    ]);
    expect(directory.templates.first.isAcp, isFalse);
    expect(directory.templates.last.isAcp, isTrue);
    // ACP 模板的协议身份来自 backend catalog，不从显示名推断。
    expect(directory.templates.last.acpProvider, AcpProviderView.antigravity);
    // 固定受管版本来自后端模板，不是客户端可编辑/可选择的字段。
    expect(directory.acpEntries.single.template?.supportedVersion, '1.4.1');
    expect(directory.acpEntries.single.template, _acpTemplate);
    expect(directory.acpEntries.single.auth, isA<AcpVerifiedState>());
    expect(directory.nativeEntries.single.account.id, 'native-1');
    expect(directory.authRevision, 1);
  });

  test(
    'an account without an observation entry is unchecked, never verified',
    () {
      final directory = AccountDirectoryView.from(
        acpAccounts: [_acpAccount('acp-1')],
        acpCatalog: _acpCatalog,
        auth: _auth(),
      );

      expect(directory.acpEntries.single.auth, isA<AcpUncheckedState>());
      expect(
        const AcpAuthSnapshotView.empty().stateOf(
          'acp-1',
          connectionRevision: 3,
        ),
        isA<AcpUncheckedState>(),
      );
    },
  );

  test('suggested ids stay stable and skip both account kinds', () {
    final directory = AccountDirectoryView.from(
      nativeAccounts: [_nativeAccount('antigravity')],
      acpAccounts: [_acpAccount('antigravity-2')],
    );

    expect(directory.hasId('antigravity'), isTrue);
    expect(directory.suggestId('antigravity'), 'antigravity-3');
    expect(directory.suggestId('fresh'), 'fresh');
  });

  test('an observation from an older connection identity is not reused', () {
    // 旧 connectionRevision（甚至删除后重建的同 ID 账号）的观察不得套用到新配置。
    final auth = _auth(
      accounts: [
        const AcpAuthAccountView(
          accountId: 'acp-1',
          connectionRevision: 2,
          state: AcpVerifiedState(
            checkedAt: 90,
            server: AcpServerInfoView(name: 'antigravity', version: '1.2.3'),
          ),
        ),
      ],
    );
    final directory = AccountDirectoryView.from(
      acpAccounts: [_acpAccount('acp-1', connectionRevision: 3)],
      acpCatalog: _acpCatalog,
      auth: auth,
    );

    expect(directory.acpEntries.single.auth, isA<AcpUncheckedState>());
    expect(auth.account('acp-1', connectionRevision: 2), isNotNull);
    expect(auth.account('acp-1', connectionRevision: 3), isNull);
  });

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
