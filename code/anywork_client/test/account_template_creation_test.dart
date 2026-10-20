import 'package:anywork_client/models.dart';
import 'package:test/test.dart';

/// 模板只负责创建默认值，不是已有账号或统计的身份来源。
void main() {
  const catalog = AccountCatalogView(
    schemaVersion: 16,
    revision: 'catalog-r1',
    templates: [
      AccountTemplateView(
        id: 'open-ai',
        displayName: 'OpenAI',
        description: 'OpenAI template',
        baseUrl: 'https://api.openai.example/v1',
        credentialLabel: 'API Key',
        credentialEnv: 'OPENAI_API_KEY',
        modelCatalogId: 'open-ai',
        protocol: 'open_ai',
        suggestedModelId: 'gpt-5.6',
      ),
      AccountTemplateView(
        id: 'openai-compatible',
        displayName: '自定义（OpenAI 兼容）',
        description: 'Custom compatible endpoint',
        baseUrl: 'http://localhost:11434/v1',
        credentialLabel: 'API Key (optional)',
        credentialEnv: '',
        modelCatalogId: 'openai-compatible',
        protocol: 'open_ai_compatible',
        suggestedModelId: '',
        pricingEnabled: false,
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
      'openai-compatible': const [],
    },
  );

  test('创建草稿的名称、协议与模型来自模板 descriptor', () {
    final account = catalog
        .template('open-ai')!
        .createAccount('account-1', catalog.modelsFor('open-ai'));
    // 默认名称取模板展示名，用户之后可以改名。
    expect(account.name, 'OpenAI');
    expect(account.id, 'account-1');
    expect(account.templateId, 'open-ai');
    // 协议只来自 descriptor，不按模板 ID、显示名或 URL 推断。
    expect(account.protocol, 'open_ai');
    expect(account.baseUrl, 'https://api.openai.example/v1');
    expect(account.credentialEnv, 'OPENAI_API_KEY');
    expect(account.defaultModelId, 'gpt-5.6');
    expect(account.models.map((model) => model.modelId), ['gpt-5.6']);
  });

  test('自定义模板同样由 descriptor 提供协议，不硬编码空模板分支', () {
    final account = catalog
        .template('openai-compatible')!
        .createAccount('account-2', catalog.modelsFor('openai-compatible'));
    expect(account.templateId, 'openai-compatible');
    expect(account.protocol, 'open_ai_compatible');
    expect(account.pricingEnabled, isFalse);
    expect(account.models, isEmpty);
    expect(account.defaultModelId, isEmpty);
  });

  test('保存意图携带稳定 ID、模板与协议，且没有账号默认模型字段', () {
    final account = catalog
        .template('open-ai')!
        .createAccount('account-1', catalog.modelsFor('open-ai'));
    final renamed = account.copyWith(name: '工作账号', hasBearerToken: true);
    final command = AccountCommandBuilder.buildAccount(renamed);
    expect(command.id, 'account-1');
    expect(command.name, '工作账号');
    expect(command.templateId, 'open-ai');
    expect(command.protocol, 'open_ai');
    expect(command.secret.action, AccountSecretAction.preserve);
    expect(command.customModels, isEmpty);
  });

  test('非空 secret 输入产生 replace，未配置凭据的新账号保存为 clear', () {
    final account = catalog
        .template('open-ai')!
        .createAccount('account-1', catalog.modelsFor('open-ai'));
    final replacement = AccountCommandBuilder.buildAccount(
      account.copyWith(bearerToken: '  sk-new  '),
    );
    expect(replacement.secret.action, AccountSecretAction.replace);
    expect(replacement.secret.value, 'sk-new');

    final cleared = AccountCommandBuilder.buildAccount(
      account.copyWith(name: 'x'),
    );
    expect(cleared.secret.action, AccountSecretAction.clear);
  });

  test('显示名与模板变化不改动账号 ID 或统计身份', () {
    final created = catalog
        .template('open-ai')!
        .createAccount('account-1', catalog.modelsFor('open-ai'));
    final renamed = created.copyWith(name: '另一个名字');
    expect(renamed.id, created.id);
    final switched = catalog
        .template('openai-compatible')!
        .createAccount(renamed.id, catalog.modelsFor('openai-compatible'));
    expect(switched.id, renamed.id);
    expect(switched.protocol, 'open_ai_compatible');
    expect(switched.name, '自定义（OpenAI 兼容）');
  });

  test('没有模板引用的既有账号保留 canonical 协议，不猜厂商', () {
    const legacy = AccountSettingsView(
      id: 'legacy',
      templateId: null,
      protocol: 'open_ai_compatible',
      name: 'Legacy endpoint',
      baseUrl: 'https://legacy.example/v1',
      defaultModelId: '',
      models: [],
      status: 'ready',
      usageLabel: '',
    );
    final joined = accountWithCatalogMetadata(legacy, catalog);
    expect(joined.templateId, isNull);
    expect(joined.protocol, 'open_ai_compatible');
    expect(joined.name, 'Legacy endpoint');
    expect(joined.baseUrl, 'https://legacy.example/v1');
  });

  test('未知模板不静默退回其它模板', () {
    expect(catalog.template('missing'), isNull);
    expect(
      catalog.template('missing')?.createAccount('account-1', const []),
      isNull,
    );
  });
}
