import 'package:anywork_client/configuration_ports.dart';
import 'package:anywork_client/models.dart';
import 'package:anywork_client/operations_ports.dart';
import 'package:anywork_client/resources_ports.dart';
import 'package:test/test.dart';

import 'support/configuration_fixture.dart';
import 'support/configuration_command_fixture.dart';
import 'support/profile_model_port.dart';

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

const _catalogOrigin = ProductReadOrigin(
  ownerEpoch: 'template-native-catalog',
  incarnation: 3,
);
const _catalogTarget = ModelCatalogReadTarget(
  origin: _catalogOrigin,
  reference: ModelCatalogReadRef(entry: 1, revision: 1),
);

/// Explicit native reply; the feed publication below is declared separately and
/// never derived from the request.
ConfigurationCommandReply _reply(OperationId operationId, int revision) =>
    ConfigurationCommandReply(
      receipt: CommitReceipt(
        operationId: operationId,
        disposition: CommitDisposition.applied,
        targets: [
          ResourceStamp(
            resourceKey: 'settings',
            ownerEpoch: configurationFixtureOrigin.ownerEpoch,
            revision: revision,
          ),
        ],
        effect: EffectPoint.futureSession,
        effective: false,
        durable: true,
      ),
      configuration: ConfigurationReadTarget(
        origin: configurationFixtureOrigin,
        reference: ConfigurationReadRef(entry: 1, revision: revision),
      ),
      models: _catalogTarget,
    );

/// The account a successful create makes canonical: no explicit billing
/// category was chosen, so only the inferred one is observable.
AccountConfiguration _createdAccount() => AccountConfiguration(
  accountId: 'account-1',
  templateId: 'open-ai',
  protocol: 'open_ai',
  name: 'OpenAI',
  baseUrl: 'https://api.openai.example/v1',
  hasBearerToken: false,
  bearerTokenEnv: null,
  billingKind: BillingKind.metered,
  billingKindOverride: null,
  disabledModels: const [],
  usageQueryRevision: 1,
  catalogId: 'open-ai',
  customModels: const [],
  modelConnectionModes: const [],
  modelAutoCompactLimits: const [],
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
  AccountSecretUpdate secret = const AccountSecretUpdate.preserve(),
  BillingKind? initialBillingKind,
}) => AccountEdit(
  accountId: accountId,
  create: true,
  templateId: FieldEdit.set(templateId),
  protocol: FieldEdit.set(protocol),
  name: FieldEdit.set(name),
  baseUrl: FieldEdit.set(baseUrl),
  secret: secret,
  // 创建路径可以携带真实初始类别；未显式选择时为 null。
  initialBillingKind: initialBillingKind,
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
    // 创建时没有显式选择计费类别，因此不提交初始类别。
    expect(update.initialBillingKind, isNull);
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
      ),
    );
    final call = await fixture.port.saved(0);
    expect(call.request.account.accountId, 'account-1');
    expect(call.request.account.protocol, 'open_ai_compatible');
    expect(call.request.account.templateId, 'openai-compatible');
    expect(call.request.account.name, '自定义（OpenAI 兼容）');
    // 普通连接/模板编辑不回传也不覆盖计费类别：显式覆盖只由独立的窄命令改写。
    expect(
      fixture.port.billingChanges,
      isEmpty,
      reason: 'An ordinary connection edit must not replay billing intent',
    );
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
        initialBillingKind: null,
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

  test('创建可携带真实初始计费类别，编辑携带该类别在进入写入通道前被拒绝', () async {
    final fixture = await _fixture(_legacyAccount());
    final created = fixture.repository.saveAccount(
      _create(initialBillingKind: BillingKind.noCharge),
    );
    final call = await fixture.port.saved(0);
    expect(call.request.account.initialBillingKind, BillingKind.noCharge);
    await _reject(call, created);

    // `unknown` 表示“未指定”，不是可提交的初始类别，也不能当作“免费”。
    final unspecified = fixture.repository.saveAccount(
      _create(initialBillingKind: BillingKind.unknown),
    );
    final unspecifiedCall = await fixture.port.saved(1);
    expect(unspecifiedCall.request.account.initialBillingKind, isNull);
    await _reject(unspecifiedCall, unspecified);

    // 编辑既有账号不得用初始类别改写计费：SDK 在提交前拒绝该意图。
    expect(
      () => fixture.repository.saveAccount(
        AccountEdit(
          accountId: 'legacy',
          create: false,
          templateId: const FieldEdit.keep(),
          protocol: const FieldEdit.keep(),
          name: const FieldEdit.keep(),
          baseUrl: const FieldEdit.keep(),
          secret: const AccountSecretUpdate.preserve(),
          initialBillingKind: BillingKind.noCharge,
          rebuildModelConfiguration: false,
          customModels: const [],
          connections: const [],
          autoCompactLimits: const [],
        ),
      ),
      throwsA(
        isA<StudioFailure>().having(
          (StudioFailure error) => error.code,
          'code',
          StudioFailureCode.invalidArgument,
        ),
      ),
    );
    expect(fixture.port.saves, hasLength(2), reason: '被拒绝的编辑没有创建原生调用');
    expect(
      fixture.port.billingChanges,
      isEmpty,
      reason: '计费类别只由窄命令改写，编辑不回传该类别',
    );
  });

  test('新建账号提交后没有显式计费覆盖，类别仍由模板与 endpoint 推导', () async {
    final nativeModels = ProfileModelsPort(
      origin: _catalogOrigin,
      accounts: const [],
      textEligibleAccounts: const {},
    );
    final fixture = ConfigurationFixture(modelsPort: nativeModels);
    await fixture.establish(_legacyAccount());
    addTearDown(() async {
      final deadline = DateTime.now().add(const Duration(seconds: 3));
      final reports = await Future.wait([
        fixture.repository.close(deadline: deadline),
        fixture.models.close(deadline: deadline),
      ]);
      expect(
        reports.expand((CloseReport report) => report.unresolved),
        isEmpty,
      );
      expect(fixture.budget.usage, isEmpty);
    });

    final ticket = fixture.repository.saveAccount(_create());
    final call = await fixture.port.saved(0);
    await call.native.resultRead(0);
    call.native.resultAt(0).reply.complete(_reply(ticket.id, 2));
    await fixture.port.publishAccount(2, _createdAccount());
    await nativeModels.feed.listened.future;
    nativeModels.baseline();
    await nativeModels.feed.acknowledged(1);
    final result = await ticket.result;
    expect(result, isA<CommittedCommandResult<Unit>>());
    final closing = await call.native.closed(0);
    closing.reply.complete(
      FeedCloseReport(
        feedId: call.native.callId,
        outcome: const FeedCloseOutcome.clean(),
      ),
    );

    final created = await fixture.repository.loadAccount('account-1');
    // 新建账号不把开关状态当作持久覆盖：没有显式选择时只有推导出的生效类别。
    expect(
      created.billingKindOverride,
      isNull,
      reason: 'A new account carries no explicit billing category',
    );
    expect(created.billingKind, BillingKind.metered);
    expect(
      fixture.port.billingChanges,
      isEmpty,
      reason: 'Creation is not a billing narrow command',
    );
  });
}
