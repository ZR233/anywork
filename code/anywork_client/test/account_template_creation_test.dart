import 'dart:async';

import 'package:anywork_client/accounts.dart';
import 'package:anywork_client/model_directory.dart';
import 'package:anywork_client/studio_client.dart';
import 'package:test/test.dart';

import 'support/accounts_test_runtime.dart';

const _catalog = AccountCatalogView(
  schemaVersion: 19,
  revision: 'catalog-r1',
  templates: [
    AccountTemplateView(
      id: 'open-ai',
      displayName: 'OpenAI',
      description: 'Provider template',
      baseUrl: 'https://api.openai.example/v1',
      credentialLabel: 'API Key',
      credentialEnv: 'OPENAI_API_KEY',
      modelCatalogId: 'open-ai',
      protocol: 'open_ai',
      suggestedModelId: 'gpt-5.6',
      defaultBillingKind: BillingKind.metered,
      supportsModelDiscovery: true,
      supportsUsageQuery: null,
    ),
    AccountTemplateView(
      id: 'openai-compatible',
      displayName: 'Custom compatible API',
      description: 'Custom endpoint',
      baseUrl: 'http://localhost:11434/v1',
      credentialLabel: 'API Key (optional)',
      credentialEnv: '',
      modelCatalogId: 'openai-compatible',
      protocol: 'open_ai_compatible',
      suggestedModelId: '',
      defaultBillingKind: BillingKind.unknown,
      supportsModelDiscovery: false,
      supportsUsageQuery: null,
    ),
  ],
  modelCatalogs: {
    'open-ai': [
      AccountModelView(
        modelId: 'gpt-5.6',
        displayName: 'GPT-5.6',
        reasoningEfforts: ['low', 'high'],
      ),
    ],
    'openai-compatible': [],
  },
);
const _identity = NativeAccountIdentity('account-1');
AccountSettingsView _account({
  String? template = 'open-ai',
  String name = 'OpenAI',
  String protocol = 'open_ai',
  String url = 'https://api.openai.example/v1',
  bool token = false,
}) => AccountSettingsView(
  id: 'account-1',
  name: name,
  templateId: template,
  protocol: protocol,
  baseUrl: url,
  hasBearerToken: token,
  defaultModelId: '',
  models: const [],
  status: 'ready',
  usageLabel: '',
);
SettingsStateSnapshot _snapshot(
  int revision,
  Iterable<AccountSettingsView> accounts,
) => SettingsStateSnapshot(
  revision: revision,
  modelCatalogRevision: revision,
  accounts: accounts.toList(),
);

final class _Call {
  _Call(this.revision, this.operation, this.command);
  final int revision;
  final OperationId operation;
  final Object command;
  final result = Completer<SettingsCommandReply>();
  void complete(SettingsStateSnapshot value) => result.complete(
    accountReply(
      snapshot: value,
      receipt: StudioCommandReceipt(
        operationId: operation,
        disposition: CommitDisposition.applied,
        targets: [testStamp('settings', value.revision)],
        effect: EffectPoint.futureSession,
        effective: false,
        durable: true,
      ),
    ),
  );
}

final class _Transport extends AccountsTestTransport {
  final calls = StreamController<_Call>.broadcast();
  final templateEntered = Completer<void>();
  Completer<AccountCatalogView>? templateReply;
  int templateReads = 0;
  SettingsStateSnapshot current = _snapshot(1, const []);
  @override
  Future<AccountCatalogView> loadAccountCatalog() {
    templateReads++;
    if (!templateEntered.isCompleted) templateEntered.complete();
    return templateReply?.future ?? Future.value(_catalog);
  }

  @override
  Future<SettingsStateSnapshot> readSettingsState() async => current;
  @override
  Future<SettingsCommandReply> createAccount(
    int revision,
    CreateAccountCommand command, {
    required OperationId operationId,
  }) {
    final call = _Call(revision, operationId, command);
    calls.add(call);
    return call.result.future;
  }

  @override
  Future<SettingsCommandReply> patchAccount(
    int revision,
    PatchAccountCommand command, {
    required OperationId operationId,
  }) {
    final call = _Call(revision, operationId, command);
    calls.add(call);
    return call.result.future;
  }
}

AccountsTestRuntime _runtime(_Transport transport) {
  final runtime = AccountsTestRuntime(transport, clientId: 'templates');
  runtime.seed(transport.current);
  addTearDown(() async {
    await runtime.close();
    await transport.calls.close();
  });
  return runtime;
}

CreateAccountCommand _create(
  AccountTemplateView template, {
  AccountSecretCommand secret = const AccountSecretCommand.clear(),
  BillingKind? billing,
}) => CreateAccountCommand(
  identity: _identity,
  name: template.displayName,
  protocol: template.protocol,
  templateId: template.id,
  baseUrl: template.baseUrl,
  secret: secret,
  initialBillingKind: billing,
);
NativeAccountDetails _detail(AccountsTestRuntime runtime) =>
    runtime.domains.accounts.details(_identity).value.value!
        as NativeAccountDetails;

void main() {
  test('template loading is independently observed and creation preserves descriptor protocol and endpoint', () async {
    final transport = _Transport()
      ..templateReply = Completer<AccountCatalogView>();
    final runtime = _runtime(transport);
    expect(runtime.domains.accounts.state.value.loaded, isTrue);
    expect(
      runtime.domains.accounts.state.value.templates.revision,
      isEmpty,
      reason: 'Loaded summaries do not mean loaded templates',
    );
    final loading = runtime.domains.accounts.loadTemplates();
    final same = runtime.domains.accounts.loadTemplates();
    expect(identical(loading, same), isTrue);
    await transport.templateEntered.future;
    transport.templateReply!.complete(_catalog);
    await loading;
    final templates = runtime.domains.accounts.state.value.templates;
    expect(transport.templateReads, 1);
    expect(() => templates.templates.clear(), throwsUnsupportedError);
    final descriptor = templates.template('open-ai')!;
    final entered = transport.calls.stream.first;
    final creating = runtime.domains.accounts.create(_create(descriptor));
    final call = await entered;
    final sent = call.command as CreateAccountCommand;
    expect(sent.identity, _identity);
    expect(sent.name, 'OpenAI');
    expect(sent.templateId, 'open-ai');
    expect(sent.protocol, 'open_ai');
    expect(sent.baseUrl, 'https://api.openai.example/v1');
    expect(
      templates.modelsFor(descriptor.modelCatalogId).single.modelId,
      'gpt-5.6',
    );
    expect(descriptor.suggestedModelId, 'gpt-5.6');
    expect(descriptor.credentialEnv, 'OPENAI_API_KEY');
    expect(
      runtime.domains.accounts.state.value.accounts,
      isEmpty,
      reason:
          'A template is not a saved account or an optimistic model catalog',
    );
    call.complete(_snapshot(2, [_account()]));
    expect((await creating).observed, isTrue);
  });

  test('custom templates use their explicit protocol and do not copy template model defaults into declarations', () async {
    final transport = _Transport();
    final runtime = _runtime(transport);
    await runtime.domains.accounts.loadTemplates();
    final descriptor = runtime.domains.accounts.state.value.templates.template(
      'openai-compatible',
    )!;
    final entered = transport.calls.stream.first;
    final pending = runtime.domains.accounts.create(_create(descriptor));
    final call = await entered;
    final sent = call.command as CreateAccountCommand;
    expect(sent.protocol, 'open_ai_compatible');
    expect(sent.templateId, 'openai-compatible');
    expect(sent.customModels, isEmpty);
    expect(sent.initialBillingKind, isNull);
    expect(descriptor.suggestedModelId, isEmpty);
    expect(
      runtime.domains.accounts.state.value.templates.modelsFor(
        descriptor.modelCatalogId,
      ),
      isEmpty,
    );
    call.complete(
      _snapshot(2, [
        _account(
          template: descriptor.id,
          protocol: descriptor.protocol,
          url: descriptor.baseUrl,
        ),
      ]),
    );
    await pending;
    expect(_detail(runtime).protocol, 'open_ai_compatible');
  });

  test('create carries initial billing but ordinary edits preserve credentials and unrelated model intent', () async {
    final transport = _Transport();
    final runtime = _runtime(transport);
    var entered = transport.calls.stream.first;
    var pending = runtime.domains.accounts.create(
      _create(_catalog.template('open-ai')!, billing: BillingKind.noCharge),
    );
    var call = await entered;
    expect(
      (call.command as CreateAccountCommand).initialBillingKind,
      BillingKind.noCharge,
    );
    call.complete(_snapshot(2, [_account(token: true)]));
    await pending;
    entered = transport.calls.stream.first;
    pending = runtime.domains.accounts.patch(
      const PatchAccountCommand(
        identity: _identity,
        name: AccountTextPatch.set('Work'),
      ),
    );
    call = await entered;
    final sent = call.command as PatchAccountCommand;
    expect(sent.identity, _identity);
    expect((sent.name as AccountTextSet).value, 'Work');
    expect(sent.protocol, isA<AccountTextKeep>());
    expect(sent.templateId, isA<AccountTextKeep>());
    expect(sent.baseUrl, isA<AccountTextKeep>());
    expect(sent.customModels, isA<AccountModelsKeep>());
    expect(sent.secret.action, AccountSecretAction.preserve);
    call.complete(_snapshot(3, [_account(name: 'Work', token: true)]));
    await pending;
    expect(_detail(runtime).name, 'Work');
    expect(_detail(runtime).hasBearerToken, isTrue);
  });

  test('explicit replace and clear remain distinct; blank replacement is not silently changed into clear', () async {
    final transport = _Transport()
      ..current = _snapshot(1, [_account(token: true)]);
    final runtime = _runtime(transport);
    for (final secret in [
      const AccountSecretCommand.replace('  sk-new  '),
      const AccountSecretCommand.replace(''),
      const AccountSecretCommand.clear(),
    ]) {
      final entered = transport.calls.stream.first;
      final pending = runtime.domains.accounts.patch(
        PatchAccountCommand(identity: _identity, secret: secret),
      );
      final call = await entered;
      final sent = (call.command as PatchAccountCommand).secret;
      expect(sent.action, secret.action);
      expect(sent.value, secret.value);
      call.complete(
        _snapshot(call.revision + 1, [
          _account(token: secret.action != AccountSecretAction.clear),
        ]),
      );
      await pending;
      expect(
        _detail(runtime).hasBearerToken,
        secret.action != AccountSecretAction.clear,
      );
    }
  });

  test('CAS retry replays the same narrow rename without replacing changed endpoint or identity', () async {
    final transport = _Transport()..current = _snapshot(1, [_account()]);
    final runtime = _runtime(transport);
    final command = const PatchAccountCommand(
      identity: _identity,
      name: AccountTextPatch.set('Renamed'),
    );
    var entered = transport.calls.stream.first;
    final pending = runtime.domains.accounts.patch(command);
    final first = await entered;
    transport.current = _snapshot(2, [
      _account(
        template: 'openai-compatible',
        protocol: 'open_ai_compatible',
        url: 'https://concurrent.invalid/v1',
        token: true,
      ),
    ]);
    entered = transport.calls.stream.first;
    first.result.completeError(
      const StudioFailure(
        code: StudioFailureCode.staleRevision,
        message: 'Changed',
        retryable: true,
        correlationId: 'template-cas',
      ),
    );
    final retry = await entered;
    expect(retry.command, same(command));
    expect(retry.operation, first.operation);
    expect(retry.revision, 2);
    retry.complete(
      _snapshot(3, [
        transport.current.accounts.single.copyWith(name: 'Renamed'),
      ]),
    );
    await pending;
    final detail = _detail(runtime);
    expect(detail.identity, _identity);
    expect(detail.templateId, 'openai-compatible');
    expect(detail.protocol, 'open_ai_compatible');
    expect(detail.baseUrl, 'https://concurrent.invalid/v1');
    expect(detail.hasBearerToken, isTrue);
    expect(detail.name, 'Renamed');
  });

  test('catalog loading never rewrites a saved account with no template or its canonical models', () async {
    final transport = _Transport()
      ..current = _snapshot(1, [
        _account(
          template: null,
          name: 'Legacy endpoint',
          protocol: 'open_ai_compatible',
          url: 'https://legacy.example/v1',
        ),
      ]);
    final runtime = _runtime(transport);
    final detail = _detail(runtime);
    final models = runtime.domains.models.state.value;
    await runtime.domains.accounts.loadTemplates();
    expect(_detail(runtime), same(detail));
    expect(runtime.domains.models.state.value, same(models));
    expect(detail.templateId, isNull);
    expect(detail.protocol, 'open_ai_compatible');
    expect(detail.name, 'Legacy endpoint');
    expect(detail.baseUrl, 'https://legacy.example/v1');
  });

  test('unknown template remains unknown and a rejected create neither picks another template nor publishes success', () async {
    final transport = _Transport();
    final runtime = _runtime(transport);
    await runtime.domains.accounts.loadTemplates();
    expect(
      runtime.domains.accounts.state.value.templates.template('missing'),
      isNull,
    );
    final entered = transport.calls.stream.first;
    final pending = runtime.domains.accounts.create(
      CreateAccountCommand(
        identity: _identity,
        name: 'Missing',
        templateId: 'missing',
        protocol: 'open_ai_compatible',
        baseUrl: 'https://local.invalid',
        secret: const AccountSecretCommand.clear(),
      ),
    );
    final call = await entered;
    expect((call.command as CreateAccountCommand).templateId, 'missing');
    const error = StudioFailure(
      code: StudioFailureCode.invalidArgument,
      message: 'Unknown template',
      retryable: false,
      correlationId: 'template',
    );
    call.result.completeError(error);
    final rejected = await pending;
    expect(rejected.id, call.operation);
    expect(rejected.failurePhase, OperationPhase.rejected);
    expect(rejected.error, same(error));
    expect(rejected.receipt, isNull);
    expect(runtime.domains.accounts.state.value.accounts, isEmpty);
    expect(runtime.board.operations.last.phase, OperationPhase.rejected);
  });
}
