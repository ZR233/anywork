import 'package:anywork_client/configuration_ports.dart';
import 'package:anywork_client/models.dart';
import 'package:anywork_client/operations_ports.dart';
import 'package:anywork_client/resources_ports.dart';
import 'package:test/test.dart';

import 'support/configuration_fixture.dart';
import 'support/configuration_command_fixture.dart';

/// 模板只负责创建默认值，不是已有账号或统计的身份来源。
///
/// 模板 → 草稿的字段映射现在由前端 `account_editor` 装配，客户端只拥有
/// descriptor 值本身与创建意图（`AccountEdit(create: true)`）的写入语义：
/// 协议必须来自 descriptor、创建必须显式给出模板/协议/名称/地址，凭据动作用
/// `AccountSecretUpdate` 三态表达，账号 ID 不随名称或模板切换改变。
const _capabilities = AccountServiceCapabilities(
  webSearch: WebSearchServiceCapabilities(
    hostedResponses: true,
    hostedDialect: 'responses',
    standalone: null,
  ),
  promptCacheDialect: 'openai',
  responsesProgrammaticToolCalling: true,
);

ModelDescriptor _descriptor(String modelId, String displayName) =>
    ModelDescriptor(
      modelId: modelId,
      enabled: true,
      typeSupport: const [],
      origin: ModelOrigin.bundled,
      displayName: displayName,
      description: null,
      contextWindow: 4096,
      maxContextWindow: 4096,
      context: const ModelContextResolution(
        unavailable: null,
        contextWindow: 4096,
        inputTokenLimit: 3072,
        autoCompactLimit: 2048,
        adjustment: null,
      ),
      maxOutputTokens: 1024,
      transport: ModelTransportDescriptor(
        protocol: 'openai',
        connectionModes: const [],
        defaultConnectionMode: 'http',
      ),
      capabilities: ModelCapabilities(
        input: const [],
        output: const [],
        streaming: true,
        temperature: false,
        reasoning: false,
        webSearch: false,
        functionCalling: false,
        parallelToolCalls: false,
        customTools: false,
        freeformTools: false,
        instructionSnapshotOverrides: false,
        nativeContextFamily: null,
      ),
      reasoning: null,
      pricing: null,
    );

AccountTemplatesValue _catalog() => AccountTemplatesValue(
  schemaVersion: 16,
  revision: 'catalog-r1',
  templates: [
    AccountTemplate(
      id: 'open-ai',
      displayName: 'OpenAI',
      description: 'OpenAI template',
      baseUrl: 'https://api.openai.example/v1',
      credential: const CredentialDescriptor(
        label: 'API Key',
        envVar: 'OPENAI_API_KEY',
      ),
      modelCatalogId: 'open-ai',
      protocol: 'open_ai',
      suggestedModelId: 'gpt-5.6',
      iconKey: 'open-ai',
      pricingEnabled: true,
      serviceCapabilities: _capabilities,
    ),
    AccountTemplate(
      id: 'openai-compatible',
      displayName: '自定义（OpenAI 兼容）',
      description: 'Custom compatible endpoint',
      baseUrl: 'http://localhost:11434/v1',
      credential: const CredentialDescriptor(
        label: 'API Key (optional)',
        envVar: null,
      ),
      modelCatalogId: 'openai-compatible',
      protocol: 'open_ai_compatible',
      suggestedModelId: '',
      iconKey: null,
      pricingEnabled: false,
      serviceCapabilities: _capabilities,
    ),
  ],
  modelCatalogs: {
    'open-ai': NamedModelCatalog(
      id: 'open-ai',
      models: [_descriptor('gpt-5.6', 'GPT-5.6')],
    ),
    'openai-compatible': NamedModelCatalog(
      id: 'openai-compatible',
      models: const [],
    ),
  },
);

AccountTemplate _template(AccountTemplatesValue catalog, String id) =>
    catalog.templates.singleWhere((AccountTemplate item) => item.id == id);

AccountConfiguration _legacyAccount() => AccountConfiguration(
  accountId: 'legacy',
  templateId: null,
  protocol: 'open_ai_compatible',
  name: 'Legacy endpoint',
  baseUrl: 'https://legacy.example/v1',
  hasBearerToken: false,
  bearerTokenEnv: null,
  pricingEnabled: true,
  billingKind: BillingKind.metered,
  billingKindOverride: null,
  disabledModels: const [],
  usageQueryRevision: 1,
  catalogId: 'openai-compatible',
  customModels: const [],
  modelConnectionModes: const [],
  modelAutoCompactLimits: const [],
);

AccountEdit _create({
  String accountId = 'account-1',
  String templateId = 'open-ai',
  String protocol = 'open_ai',
  String name = 'OpenAI',
  String baseUrl = 'https://api.openai.example/v1',
  bool pricingEnabled = true,
  AccountSecretUpdate secret = const AccountSecretUpdate.preserve(),
}) => AccountEdit(
  accountId: accountId,
  create: true,
  templateId: FieldEdit.set(templateId),
  protocol: FieldEdit.set(protocol),
  name: FieldEdit.set(name),
  baseUrl: FieldEdit.set(baseUrl),
  secret: secret,
  pricingEnabled: FieldEdit.set(pricingEnabled),
  rebuildModelConfiguration: false,
  customModels: const [],
  connections: const [],
  autoCompactLimits: const [],
);

const _nativeRefusal = StudioFailure(
  code: StudioFailureCode.invalidArgument,
  message: 'The scripted native boundary declined this prepared write',
  retryable: false,
  correlationId: 'configuration-native-refusal',
);

/// The real Repository must construct the complete native request before native
/// validation can accept or reject it; explicit rejection then proves there was
/// no optimistic canonical edit and no fabricated command receipt.
Future<void> _reject(
  RecordedConfigurationCall<UpdateAccountRequest> call,
  OperationTicket<Unit> ticket,
) async {
  await call.native.resultRead(0);
  call.native
      .resultAt(0)
      .reply
      .completeError(
        const CommandDispatchFailure.rejected(failure: _nativeRefusal),
      );
  final result = await ticket.result;
  expect(result, isA<RejectedCommandResult<Unit>>());
  final closing = await call.native.closed(0);
  expect(closing.retry, isFalse);
  expect(call.native.requestCloseCalls, 1);
  closing.reply.complete(
    FeedCloseReport(
      feedId: call.native.callId,
      outcome: const FeedCloseOutcome.clean(),
    ),
  );
}

Future<ConfigurationFixture> _fixture(AccountConfiguration account) async {
  final fixture = ConfigurationFixture();
  await fixture.establish(account);
  addTearDown(() async {
    final deadline = DateTime.now().add(const Duration(seconds: 3));
    final reports = await Future.wait([
      fixture.repository.close(deadline: deadline),
      fixture.models.close(deadline: deadline),
    ]);
    expect(reports.expand((CloseReport report) => report.unresolved), isEmpty);
    expect(fixture.budget.usage, isEmpty);
  });
  return fixture;
}

void main() {
  test('创建草稿的名称、协议与模型来自模板 descriptor', () {
    final catalog = _catalog();
    final template = _template(catalog, 'open-ai');
    // 默认名称取模板展示名，用户之后可以改名。
    expect(template.displayName, 'OpenAI');
    expect(template.id, 'open-ai');
    // 协议只来自 descriptor，不按模板 ID、显示名或 URL 推断。
    expect(template.protocol, 'open_ai');
    expect(template.baseUrl, 'https://api.openai.example/v1');
    expect(template.credential.envVar, 'OPENAI_API_KEY');
    expect(template.suggestedModelId, 'gpt-5.6');
    // 可选模型来自 descriptor 声明的 modelCatalogId，不按模板 ID 拼装。
    final models = catalog.modelCatalogs[template.modelCatalogId]!.models;
    expect(models.map((ModelDescriptor model) => model.modelId), ['gpt-5.6']);
  });

  test('自定义模板同样由 descriptor 提供协议，不硬编码空模板分支', () {
    final catalog = _catalog();
    final template = _template(catalog, 'openai-compatible');
    expect(template.id, 'openai-compatible');
    expect(template.protocol, 'open_ai_compatible');
    expect(template.pricingEnabled, isFalse);
    expect(catalog.modelCatalogs[template.modelCatalogId]!.models, isEmpty);
    expect(template.suggestedModelId, isEmpty);
  });

  test('保存意图携带稳定 ID、模板与协议，且没有账号默认模型字段', () async {
    final fixture = await _fixture(_legacyAccount());
    final ticket = fixture.repository.saveAccount(_create());
    final call = await fixture.port.saved(0);
    final update = call.request.account;
    expect(update.accountId, 'account-1');
    expect(update.name, 'OpenAI');
    expect(update.templateId, 'open-ai');
    expect(update.protocol, 'open_ai');
    expect(update.baseUrl, 'https://api.openai.example/v1');
    expect(update.secret, isA<PreserveAccountSecret>());
    // 创建意图只带自定义模型声明，不存在“账号默认模型”字段。
    expect(update.customModels, isEmpty);
    await _reject(call, ticket);
    // 原生明确拒绝后不得留下乐观账号。
    expect(
      () => fixture.repository.loadAccount('account-1'),
      throwsA(isA<StudioFailure>()),
    );
  });

  test('非空 secret 输入产生 replace，未配置凭据的新账号保存为 clear', () async {
    final fixture = await _fixture(_legacyAccount());
    final replacement = fixture.repository.saveAccount(
      _create(secret: const AccountSecretUpdate.replace('sk-new')),
    );
    final replacing = await fixture.port.saved(0);
    expect(replacing.request.account.secret, isA<ReplaceAccountSecret>());
    expect(
      (replacing.request.account.secret as ReplaceAccountSecret).value,
      'sk-new',
    );
    await _reject(replacing, replacement);

    final cleared = fixture.repository.saveAccount(
      _create(secret: const AccountSecretUpdate.clear()),
    );
    final clearing = await fixture.port.saved(1);
    expect(clearing.request.account.secret, isA<ClearAccountSecret>());
    await _reject(clearing, cleared);
  });

  test('空白 replacement 凭据在进入写入通道前被拒绝', () {
    final fixture = ConfigurationFixture();
    addTearDown(
      () => fixture.repository.close(
        deadline: DateTime.now().add(const Duration(seconds: 3)),
      ),
    );
    // 空白凭据不是“清除”，也不是“保留”；客户端拒绝该意图，编辑器负责 trim。
    expect(
      () => fixture.repository.saveAccount(
        _create(secret: const AccountSecretUpdate.replace('  ')),
      ),
      throwsA(
        isA<StudioFailure>().having(
          (StudioFailure error) => error.code,
          'code',
          StudioFailureCode.invalidArgument,
        ),
      ),
    );
    expect(fixture.port.saves, isEmpty);
  });

  test('显示名与模板变化不改动账号 ID 或统计身份', () async {
    final fixture = await _fixture(_legacyAccount());
    final switched = fixture.repository.saveAccount(
      _create(
        templateId: 'openai-compatible',
        protocol: 'open_ai_compatible',
        name: '自定义（OpenAI 兼容）',
        baseUrl: 'http://localhost:11434/v1',
        pricingEnabled: false,
      ),
    );
    final call = await fixture.port.saved(0);
    expect(call.request.account.accountId, 'account-1');
    expect(call.request.account.protocol, 'open_ai_compatible');
    expect(call.request.account.templateId, 'openai-compatible');
    expect(call.request.account.name, '自定义（OpenAI 兼容）');
    expect(call.request.account.pricingEnabled, isFalse);
    await _reject(call, switched);
  });

  test('没有模板引用的既有账号保留 canonical 协议，不猜厂商', () async {
    final fixture = await _fixture(_legacyAccount());
    final ticket = fixture.repository.saveAccount(
      AccountEdit(
        accountId: 'legacy',
        create: false,
        templateId: const FieldEdit.keep(),
        protocol: const FieldEdit.keep(),
        name: const FieldEdit.keep(),
        baseUrl: const FieldEdit.keep(),
        secret: const AccountSecretUpdate.preserve(),
        pricingEnabled: const FieldEdit.keep(),
        rebuildModelConfiguration: false,
        customModels: const [],
        connections: const [],
        autoCompactLimits: const [],
      ),
    );
    final call = await fixture.port.saved(0);
    final update = call.request.account;
    expect(update.templateId, isNull);
    expect(update.protocol, 'open_ai_compatible');
    expect(update.name, 'Legacy endpoint');
    expect(update.baseUrl, 'https://legacy.example/v1');
    await _reject(call, ticket);
  });

  test('未知模板不静默退回其它模板', () {
    final catalog = _catalog();
    expect(
      catalog.templates.where((AccountTemplate item) => item.id == 'missing'),
      isEmpty,
    );
    expect(catalog.modelCatalogs['missing'], isNull);
  });
}
