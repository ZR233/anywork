part of 'studio_api.dart';

/// Demo/preview 使用的 ACP 目录：官方 server 契约与安装说明由真实 catalog 拥有，
/// 这里只是 demo 的 typed 替身，不参与生产判定。
const demoAcpAccountCatalogFixture = AcpAccountCatalogView(
  templates: [
    AcpAccountTemplateView(
      provider: AcpProviderView.antigravity,
      displayName: 'Antigravity',
      description: '通过官方 ACP server 连接 Antigravity，并使用其自身登录凭据。',
      iconKey: 'antigravity',
      // 产品固定的受管版本由后端模板给出；demo 只镜像这一权威值。
      supportedVersion: '1.4.1',
      installUrl: 'https://antigravity.google/docs/ide/extensions',
      termsUrl: 'https://antigravity.google/terms',
      // demo 预览固定声明一个可用目标；真实目标只由后端按宿主平台给出。
      automaticInstall: AcpInstallAvailableView(target: 'linux-x86_64'),
    ),
  ],
);

/// Demo 的认证观察替身。
///
/// 它只模拟后端发布的 canonical 事实（未检查 → 需要登录 → 认证通过/取消），
/// 不模拟真实进程，也不参与生产路径；真实 Authenticating/Verifying 由 fake CLI
/// 与生产 bridge 的 manual-gui 验收覆盖。
class DemoAcpAuth {
  final Map<String, AcpAuthAccountView> _accounts = {};
  final Set<String> _verifiedConnectionKeys = {};
  int _revision = 0;

  static const methods = [
    AcpAuthMethodView(
      id: 'browser',
      name: 'Sign in with browser',
      description: '官方登录窗口完成授权',
      kind: AcpAuthMethodKindView.agent,
    ),
    AcpAuthMethodView(
      id: 'terminal',
      name: 'Terminal sign-in',
      description: '需要终端交互，本阶段不支持',
      kind: AcpAuthMethodKindView.terminal,
    ),
  ];

  static const server = AcpServerInfoView(
    name: 'antigravity',
    title: 'Antigravity',
    version: '0.0.0-demo',
  );

  AcpAuthSnapshotView get snapshot => AcpAuthSnapshotView(
    revision: _revision,
    updatedAt: DateTime.now().millisecondsSinceEpoch ~/ 1000,
    accounts: _accounts.values.toList(growable: false),
  );

  AcpAuthStateView stateOf(String accountId) =>
      _accounts[accountId]?.state ?? const AcpUncheckedState();

  /// 保存后登记连接身份；连接身份变化让旧观察失效。
  void retain(AcpAccountSettingsView account) {
    final existing = _accounts[account.accountId];
    if (existing != null &&
        existing.connectionRevision == account.connectionRevision) {
      return;
    }
    _accounts[account.accountId] = AcpAuthAccountView(
      accountId: account.accountId,
      connectionRevision: account.connectionRevision,
      state: const AcpUncheckedState(),
    );
    _revision += 1;
  }

  void forget(String accountId) {
    if (_accounts.remove(accountId) == null) return;
    _revision += 1;
  }

  String _connectionKey(AcpAccountSettingsView account) =>
      '${account.accountId}:${account.connectionRevision}';

  AcpAuthSnapshotView check(AcpAccountSettingsView account) {
    if (_verifiedConnectionKeys.contains(_connectionKey(account))) {
      _set(
        account,
        AcpVerifiedState(
          checkedAt: DateTime.now().millisecondsSinceEpoch ~/ 1000,
          server: server,
        ),
      );
      return snapshot;
    }
    _set(account, const AcpRequiredState(server: server, methods: methods));
    return snapshot;
  }

  AcpAuthSnapshotView authenticate(
    AcpAccountSettingsView account,
    String methodId,
  ) {
    final method = methods.where((item) => item.id == methodId).firstOrNull;
    if (method == null || !method.isAgent) {
      throw StudioFailure(
        code: StudioFailureCode.invalidArgument,
        message: 'Unsupported ACP authentication method: $methodId',
        retryable: false,
        correlationId: 'demo-acp-auth',
      );
    }
    _verifiedConnectionKeys.add(_connectionKey(account));
    _set(
      account,
      AcpVerifiedState(
        checkedAt: DateTime.now().millisecondsSinceEpoch ~/ 1000,
        server: server,
      ),
    );
    return snapshot;
  }

  AcpAuthSnapshotView cancel(AcpAccountSettingsView account, String target) {
    if (stateOf(account.accountId).operationId != target) {
      throw StudioFailure(
        code: StudioFailureCode.staleRevision,
        message: 'ACP operation is no longer current: $target',
        retryable: false,
        correlationId: 'demo-acp-auth',
      );
    }
    _set(account, const AcpCancelledState());
    return snapshot;
  }

  void _set(AcpAccountSettingsView account, AcpAuthStateView state) {
    _accounts[account.accountId] = AcpAuthAccountView(
      accountId: account.accountId,
      connectionRevision: account.connectionRevision,
      // demo 不合成真实阶段：检查/登录直接收敛到需要登录或认证通过，
      // Authenticating/Verifying 只由 fake CLI + 生产 bridge 验收覆盖。
      state: state,
    );
    _revision += 1;
  }
}

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
