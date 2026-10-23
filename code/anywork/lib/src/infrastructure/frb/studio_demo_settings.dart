part of 'studio_api.dart';

const demoAccountCatalogFixture = AccountCatalogView(
  schemaVersion: 6,
  revision: 'demo-future-catalog-v6',
  templates: [
    AccountTemplateView(
      id: 'future-account',
      displayName: 'Future Account',
      description: 'Injected demo account catalog fixture',
      baseUrl: 'https://future.example/v1',
      credentialLabel: 'Access Key',
      credentialEnv: 'FUTURE_PROVIDER_KEY',
      modelCatalogId: 'future-catalog',
      protocol: 'open_ai_compatible',
      suggestedModelId: 'future-model',
      hostedWebSearch: true,
      hostedWebSearchDialect: 'open_ai_responses',
      standaloneWebSearch: 'future_search_dialect',
      promptCacheDialect: 'implicit_prefix',
      responsesProgrammaticToolCalling: false,
    ),
    AccountTemplateView(
      id: 'openai-compatible',
      displayName: 'OpenAI API 兼容',
      description: 'Custom compatible API',
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
    'openai-compatible': [],
    'future-catalog': [
      AccountModelView(
        typeSupport: [ModelTypeSupportView(modelType: ModelType.text)],
        modelId: 'future-model',
        displayName: 'Future Model',
        reasoningEfforts: ['eco', 'balanced', 'max'],
        defaultReasoningEffort: 'balanced',
        inputCapabilities: [
          ModelInputCapabilityView(
            modality: ModelModalityView.text,
            sources: [
              ModelInputSourceView.local,
              ModelInputSourceView.remoteUrl,
            ],
          ),
          ModelInputCapabilityView(
            modality: ModelModalityView.image,
            sources: [
              ModelInputSourceView.local,
              ModelInputSourceView.remoteUrl,
            ],
          ),
        ],
        contextWindow: 500000,
        maxOutputTokens: 64000,
        wireApi: 'chat_completions',
        supportedConnectionModes: ['http'],
        defaultConnectionMode: 'http',
        connectionMode: 'http',
        origin: ModelOrigin.bundled,
      ),
      AccountModelView(
        typeSupport: [ModelTypeSupportView(modelType: ModelType.text)],
        modelId: 'future-text',
        displayName: 'Future Text',
        reasoningEfforts: ['eco', 'balanced'],
        defaultReasoningEffort: 'balanced',
        inputCapabilities: [
          ModelInputCapabilityView(
            modality: ModelModalityView.text,
            sources: [ModelInputSourceView.local],
          ),
        ],
        contextWindow: 256000,
        maxOutputTokens: 32000,
        wireApi: 'chat_completions',
        supportedConnectionModes: ['http'],
        defaultConnectionMode: 'http',
        connectionMode: 'http',
        origin: ModelOrigin.bundled,
      ),
      AccountModelView(
        typeSupport: [ModelTypeSupportView(modelType: ModelType.text)],
        modelId: 'future-vision',
        displayName: 'Future Vision',
        reasoningEfforts: ['balanced', 'max'],
        defaultReasoningEffort: 'max',
        inputCapabilities: [
          ModelInputCapabilityView(
            modality: ModelModalityView.text,
            sources: [
              ModelInputSourceView.local,
              ModelInputSourceView.remoteUrl,
            ],
          ),
          ModelInputCapabilityView(
            modality: ModelModalityView.image,
            sources: [ModelInputSourceView.local],
          ),
        ],
        contextWindow: 1000000,
        maxOutputTokens: 128000,
        wireApi: 'chat_completions',
        supportedConnectionModes: ['http'],
        defaultConnectionMode: 'http',
        connectionMode: 'http',
        origin: ModelOrigin.bundled,
      ),
    ],
  },
);

AccountUsageView _demoAccountUsage(AccountSettingsView account) {
  final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
  if (!account.hasBearerToken) {
    return AccountUsageView(
      accountId: account.id,
      updatedAt: now,
      state: const MissingCredentialAccountUsageView(
        message: 'account API key is not configured',
      ),
    );
  }
  return AccountUsageView(
    accountId: account.id,
    updatedAt: now,
    state: const UnsupportedAccountUsageView(),
  );
}

List<AccountSettingsView> _providersFromCommands(
  List<AccountCommand> commands, {
  List<AccountSettingsView> previous = const [],
  required AccountCatalogView catalog,
}) {
  return commands.map((account) {
    final customModels = account.customModels
        .map(
          (model) => AccountModelView(
            typeSupport: [ModelTypeSupportView(modelType: ModelType.text)],
            modelId: model.modelId,
            displayName: model.displayName,
            reasoningEfforts: const [],
            contextWindow: model.contextWindow,
            maxOutputTokens: model.maxOutputTokens,
            wireApi: model.wireApi,
            supportedConnectionModes: const ['http'],
            defaultConnectionMode: 'http',
            connectionMode: 'http',
            origin: ModelOrigin.manual,
          ),
        )
        .where((model) => model.modelId.isNotEmpty)
        .toList();
    final template =
        catalog.template(account.templateId ?? '') ?? catalog.templates.first;
    final connectionModes = {
      for (final model in account.modelConnectionModes)
        model.modelId: model.connectionMode,
    };
    AccountModelView withCurrentConnection(AccountModelView model) =>
        model.copyWith(
          connectionMode:
              connectionModes[model.modelId] ?? model.defaultConnectionMode,
        );
    final previousAccount = previous
        .where((item) => item.id == account.id)
        .firstOrNull;
    final observed = [
      for (final model in previousAccount?.models ?? const <AccountModelView>[])
        if (model.origin != ModelOrigin.manual) model,
    ];
    final catalogModels = catalog.modelsFor(template.modelCatalogId);
    final observedModels = (observed.isNotEmpty ? observed : catalogModels)
        .map(withCurrentConnection)
        .toList();
    final models = [
      ...observedModels,
      ...customModels.map(withCurrentConnection),
    ];
    final autoCompactOverrides = {
      for (final limit in account.modelAutoCompactLimits)
        limit.modelId: limit.limit,
    };
    final autoCompactLimits = {
      for (final model in models)
        model.modelId: _demoAutoCompactLimit(
          model,
          override: autoCompactOverrides[model.modelId],
        ),
    };
    final hasToken = switch (account.secret.action) {
      AccountSecretAction.preserve => previousAccount?.hasBearerToken ?? false,
      AccountSecretAction.replace => true,
      AccountSecretAction.clear => false,
    };
    return AccountSettingsView(
      id: account.id,
      templateId: account.templateId,
      protocol: account.protocol,
      name: account.name.isEmpty ? template.displayName : account.name,
      subtitle: account.name.isEmpty ? template.displayName : account.name,
      baseUrl: account.baseUrl.isEmpty ? template.baseUrl : account.baseUrl,
      bearerToken: '',
      hasBearerToken: hasToken,
      credentialRequired: template.credentialEnv.isNotEmpty,
      defaultModelId:
          models.any((model) => model.modelId == template.suggestedModelId)
          ? template.suggestedModelId
          : models.firstOrNull?.modelId ?? '',
      models: models,
      autoCompactLimits: autoCompactLimits,
      status: hasToken || template.credentialEnv.isEmpty
          ? 'ready'
          : 'missingCredential',
      usageLabel: '${models.length} models',
      modelCount: '${models.length}',
      updatedAt: 'Preview',
      catalogId: template.modelCatalogId,
      credentialLabel: template.credentialLabel,
      credentialEnv: template.credentialEnv,
      pricingEnabled: account.pricingEnabled,
      billingKind: previousAccount?.billingKind ?? BillingKind.unknown,
      billingKindOverride: previousAccount?.billingKindOverride,
      disabledModels: previousAccount?.disabledModels ?? const [],
      capabilitySource: 'template_defaults',
      hostedWebSearch:
          previousAccount?.hostedWebSearch ?? template.hostedWebSearch,
      hostedWebSearchDialect:
          previousAccount?.hostedWebSearchDialect ??
          template.hostedWebSearchDialect,
      standaloneWebSearch:
          previousAccount?.standaloneWebSearch ?? template.standaloneWebSearch,
      promptCacheDialect:
          previousAccount?.promptCacheDialect ?? template.promptCacheDialect,
      responsesProgrammaticToolCalling:
          previousAccount?.responsesProgrammaticToolCalling ??
          template.responsesProgrammaticToolCalling,
      iconKey: template.iconKey,
    );
  }).toList();
}

/// 预览态也消费共享模型规则，不维护独立的默认值算法。
AccountModelAutoCompactView _demoAutoCompactLimit(
  AccountModelView model, {
  int? override,
}) {
  return AccountModelAutoCompactView(
    modelId: model.modelId,
    overrideLimit: override,
    context: model.context,
  );
}
