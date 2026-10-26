import 'package:anywork_client/configuration_ports.dart';
import 'package:anywork_client/models.dart';
import 'package:anywork_client/operations_ports.dart';
import 'package:anywork_client/resources_ports.dart';
import 'package:test/test.dart';

import 'support/configuration_fixture.dart';

/// 模型来源（online/bundled/manual）与类型支持现在是原生目录数据：
/// Rust 在 `ModelDescriptor`/`AccountCatalogEntry.effectiveModels` 上给出
/// `origin` 与 `typeSupport`，前端 `account_details_view` 只按 origin 分组显示。
/// 客户端因此不再派生 online/bundled 分组，也不把设置帧回写进目录字段；
/// 它只保留“manual 自定义模型”这一条 canonical 列表，并把窄删除命令的
/// canonical revision 送到原生。
ModelDescriptor _descriptor(String modelId, ModelOrigin origin) =>
    ModelDescriptor(
      modelId: modelId,
      enabled: true,
      typeSupport: [
        ModelTypeSupport(modelType: ModelType.text, exclusions: const []),
      ],
      origin: origin,
      displayName: modelId,
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

AccountConfiguration _account() => AccountConfiguration(
  accountId: 'fixture',
  templateId: 'template-a',
  protocol: 'openai',
  name: 'Fixture',
  baseUrl: 'http://fixture.invalid',
  hasBearerToken: true,
  bearerTokenEnv: null,
  billingKind: BillingKind.metered,
  billingKindOverride: null,
  disabledModels: const [],
  usageQueryRevision: 7,
  catalogId: 'catalog',
  // Manual declarations are the only models the settings side owns.
  customModels: [customModel('manual-model', contextWindow: 512)],
  modelConnectionModes: const [
    ModelConnection(modelId: 'manual-model', connectionMode: 'http'),
  ],
  modelAutoCompactLimits: const [
    ModelAutoCompact(modelId: 'manual-model', overrideLimit: 111),
  ],
);

const _nativeRefusal = StudioFailure(
  code: StudioFailureCode.conflict,
  message: 'The scripted native boundary declined this narrow removal',
  retryable: false,
  correlationId: 'origin-native-refusal',
);

Future<ConfigurationFixture> _fixture() async {
  final fixture = ConfigurationFixture();
  await fixture.establish(_account());
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
  test('origin and type support belong to the native catalog, not to a client projection', () {
    final catalog = AccountCatalogEntry(
      accountId: 'fixture',
      credentialRequired: true,
      capabilitySource: 'template',
      hostedWebSearch: true,
      hostedWebSearchDialect: 'responses',
      standaloneWebSearch: null,
      promptCacheDialect: 'openai',
      responsesProgrammaticToolCalling: true,
      defaultModelId: 'manual-model',
      effectiveModels: [
        _descriptor('online-model', ModelOrigin.online),
        _descriptor('bundled-model', ModelOrigin.bundled),
        _descriptor('manual-model', ModelOrigin.manual),
      ],
      modelCatalog: const ModelCatalogStatus(
        supported: true,
        source: ModelCatalogSource.cached,
        probing: false,
        lastSuccessAt: 1,
        checkedAt: 1,
        error: null,
        cacheWarning: null,
      ),
    );
    // The catalog list is native order and native origin; the client never
    // splits it into derived online/bundled collections.
    expect(
      catalog.effectiveModels.map((ModelDescriptor model) => model.origin),
      [ModelOrigin.online, ModelOrigin.bundled, ModelOrigin.manual],
    );
    expect(
      catalog.effectiveModels.map((ModelDescriptor model) => model.modelId),
      ['online-model', 'bundled-model', 'manual-model'],
    );
    // Type support (including exclusions) is carried by the descriptor itself.
    final descriptor = catalog.effectiveModels.first;
    expect(descriptor.typeSupport.single.modelType, ModelType.text);
    expect(descriptor.typeSupport.single.exclusions, isEmpty);
    // The settings-side account keeps only its own manual declarations.
    final settings = _account();
    expect(
      settings.customModels.map(
        (CustomModelConfiguration model) => model.modelId,
      ),
      ['manual-model'],
    );
    expect(settings.modelConnectionModes.single.modelId, 'manual-model');
    expect(settings.modelAutoCompactLimits.single.modelId, 'manual-model');
  });

  test('narrow removal uses the canonical revision and a rejection leaves canonical intact', () async {
    final fixture = await _fixture();
    final ticket = fixture.repository.removeAccountModel(
      'fixture',
      'manual-model',
    );
    final call = await fixture.port.removed(0);
    expect(call.request.expectedRevision, 1);
    expect(call.request.accountId, 'fixture');
    expect(call.request.modelId, 'manual-model');
    // Removal never becomes a whole-account write that could resurrect
    // unrelated catalog or override state.
    expect(fixture.port.saves, isEmpty);

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
    closing.reply.complete(
      FeedCloseReport(
        feedId: call.native.callId,
        outcome: const FeedCloseOutcome.clean(),
      ),
    );
    // No optimistic canonical edit: the manual model and its overrides stay.
    expect(await fixture.repository.loadAccount('fixture'), _account());
  });
}
