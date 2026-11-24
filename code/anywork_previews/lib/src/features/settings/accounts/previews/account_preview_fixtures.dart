import 'package:anywork/src/features/settings/accounts/accounts_views.dart';

import 'account_list_preview_data.dart';

/// Entirely synthetic fixtures. These are not demo providers or SDK snapshots.
abstract final class AccountPreviewFixtures {
  static const nativeKey = AccountDisplayKey(
    kind: AccountKind.native,
    id: 'synthetic-native',
  );
  static const acpKey = AccountDisplayKey(
    kind: AccountKind.acp,
    id: 'synthetic-native',
  );
  static const templateKey = AccountTemplateKey(
    kind: AccountKind.native,
    id: 'deepseek',
  );
  static const billingOverrides = [
    AccountBilling.metered,
    AccountBilling.subscription,
    AccountBilling.noCharge,
  ];
  static const billing = AccountBillingPresentation(
    effective: AccountBilling.metered,
    allowedOverrides: billingOverrides,
  );
  static const balance = AccountUsagePresentation(
    phase: AccountQueryPhase.ready,
    hasLastGood: true,
    balanceHealth: AccountBalanceHealth.sufficient,
    canRefresh: true,
    updatedLabel: '10/26 12:34',
    balances: [
      AccountCurrencyBalance(
        currency: 'CNY',
        total: '2595.220000',
        granted: '0.0000',
        toppedUp: '2595.220000',
      ),
      AccountCurrencyBalance(
        currency: 'USD',
        total: '12.345678901',
        toppedUp: '12.345678901',
      ),
    ],
  );
  static const normalBalance = AccountUsagePresentation(
    phase: AccountQueryPhase.ready,
    hasLastGood: true,
    balanceHealth: AccountBalanceHealth.sufficient,
    canRefresh: true,
    updatedLabel: '10/26 12:34',
    balances: [
      AccountCurrencyBalance(
        currency: 'CNY',
        total: '2595.22',
        granted: '0.00',
        toppedUp: '2595.22',
      ),
    ],
  );
  static const subscription = AccountUsagePresentation(
    phase: AccountQueryPhase.ready,
    hasLastGood: true,
    canRefresh: true,
    updatedLabel: '10/26 12:34',
    quotas: [
      AccountQuotaPresentation(
        label: '5 小时额度',
        remaining: '94%',
        remainingFraction: .94,
        resetLabel: '14:12',
      ),
      AccountQuotaPresentation(
        label: '每周额度',
        remaining: '25%',
        remainingFraction: .25,
        resetLabel: '明天 12:00',
        low: true,
      ),
      AccountQuotaPresentation(
        label: 'MCP 额度',
        remaining: '98.9%',
        remainingFraction: .989,
        resetLabel: '11/15 09:16',
      ),
    ],
  );
  static const model = AccountModelPresentation(
    key: AccountModelKey(account: nativeKey, modelId: 'synthetic-flash'),
    name: 'DeepSeek · 合成模型 Flash',
    origin: AccountModelOrigin.online,
    summary: '文本、视觉 → 文本 · 1.05M tokens',
    canToggle: true,
    canLoadReadout: true,
    connection: AccountConnection.automatic,
    allowedConnections: AccountConnection.values,
    specificationFacts: AccountModelSpecificationFacts(
      modalityCapabilities: [
        AccountDisplayFact(label: '输入 / 输出', value: '文本、视觉 / 文本'),
        AccountDisplayFact(label: '能力', value: '流式输出 · 思考 · 工具调用'),
      ],
      context: [AccountDisplayFact(label: '上下文窗口', value: '1,050,000 tokens')],
    ),
    currency: 'CNY',
    priceSource: 'https://example.invalid/pricing',
    priceTiers: [
      AccountModelPriceTier(
        label: '≤ 128K',
        input: 2,
        output: 3,
        cacheRead: .2,
      ),
      AccountModelPriceTier(
        label: '> 128K',
        input: 4,
        output: 6,
        cacheRead: .4,
      ),
    ],
    compact: AccountCompactPresentation(
      raw: '475000',
      overridden: true,
      effective: '475000',
      automatic: '800000',
      canEdit: true,
      canReset: true,
    ),
    performance: AccountPerformancePresentation(
      sampleCount: 16,
      ttftSampleCount: 12,
      tokensPerSecond: 42,
      averageTtftMillis: 800,
    ),
    evaluations: evaluations,
    evaluationSummary: AccountEvaluationSummary(
      count: 3,
      quality: 3.5,
      instructionFollowing: 4,
      qualityDistribution: {5: 1, 2: 1},
      visible: evaluations,
    ),
  );
  static final filteredEmptyEvaluationSummary = model.evaluationSummary
      .copyWith(
        visible: const [],
        filter: const AccountEvaluationFilter(
          outcome: AccountEvaluationOutcome.failed,
        ),
      );
  static const evaluations = [
    AccountModelEvaluation(
      category: AccountEvaluationCategory.coding,
      categoryLabel: '编码',
      outcome: AccountEvaluationOutcome.passed,
      outcomeLabel: '通过',
      updatedAt: 200,
      updatedLabel: '10/26 12:34',
      comment: '完整保留输入语义，并正确处理边界。此为合成预览。',
      quality: 5,
      instructionFollowing: 5,
    ),
    AccountModelEvaluation(
      category: AccountEvaluationCategory.tooling,
      categoryLabel: '工具使用',
      outcome: AccountEvaluationOutcome.failed,
      outcomeLabel: '未通过',
      updatedAt: 100,
      updatedLabel: '10/25 09:12',
      comment: '缺少失败恢复；此条仅用于预览。',
      quality: 2,
      instructionFollowing: 3,
    ),
    AccountModelEvaluation(
      category: AccountEvaluationCategory.general,
      categoryLabel: '通用',
      outcome: AccountEvaluationOutcome.notRated,
      outcomeLabel: '未评级',
      updatedAt: 50,
      updatedLabel: '10/24 09:12',
      comment: '证据不足，不生成分数。',
    ),
  ];
  static final catalog = AccountCatalogPresentation(
    canSync: true,
    checkedLabel: '10/26 09:31',
    sourceLabel: '在线目录',
    models: [
      model,
      model.copyWith(
        key: const AccountModelKey(
          account: nativeKey,
          modelId: 'synthetic-pro',
        ),
        name: 'DeepSeek · 合成模型 Pro',
        enabled: false,
        compact: const AccountCompactPresentation(
          raw: '',
          automatic: '800000',
          effective: '800000',
          canEdit: true,
        ),
      ),
      model.copyWith(
        key: const AccountModelKey(
          account: nativeKey,
          modelId: 'synthetic-bundled',
        ),
        name: 'Bundled · 离线声明模型',
        origin: AccountModelOrigin.bundled,
      ),
      model.copyWith(
        key: const AccountModelKey(
          account: nativeKey,
          modelId: 'synthetic-manual',
        ),
        name: 'Manual · 自定义模型',
        origin: AccountModelOrigin.manual,
        canEdit: true,
        canDelete: true,
      ),
    ],
  );
  static final details = AccountDetailsPresentation(
    key: nativeKey,
    name: 'DeepSeek',
    iconKey: 'deepseek',
    endpoint: 'https://api.deepseek.com',
    canEdit: true,
    canDelete: true,
    canSetDefault: true,
    content: AccountDetailsContent.native(
      NativeAccountDetailsPresentation(
        authentication: AccountAuthenticationMethod.apiKey,
        credentialReady: true,
        billing: billing,
        catalog: catalog,
        usage: normalBalance,
        advanced: const [
          AccountDisplayFact(label: '账号 ID', value: 'synthetic-native'),
          AccountDisplayFact(label: '模板', value: '合成 DeepSeek'),
          AccountDisplayFact(label: '协议', value: 'DeepSeek'),
        ],
      ),
    ),
  );
  static final conceptDetails = _detailsWithSyntheticContextWindow(details);

  static AccountDetailsPresentation _detailsWithSyntheticContextWindow(
    AccountDetailsPresentation value,
  ) {
    final content = value.content;
    if (content is! NativeAccountDetailsContent) {
      throw StateError('Concept account fixture must be Native');
    }
    final native = content.value;
    final models = [
      for (final model in native.catalog.models)
        if (model.key == AccountPreviewFixtures.model.key)
          model.copyWith(
            compact: model.compact?.copyWith(
              // Synthetic usable window for concept-only preset previews.
              contextWindow: 1050000,
              dirty: false,
              canSave: false,
            ),
          )
        else
          model,
    ];
    return value.copyWith(
      content: AccountDetailsContent.native(
        native.copyWith(catalog: native.catalog.copyWith(models: models)),
      ),
    );
  }

  static const acp = AcpAccountPresentation(
    phase: AcpPresentationPhase.needsLogin,
    status: '需要登录',
    subtitle: '服务器需要登录才能使用。请选择下方登录方式并点击「开始登录」。',
    message: '已完成连接检查。请选择官方支持的登录方式。',
    primaryAction: AcpAccountAction.login,
    availableActions: [
      AcpAccountAction.check,
      AcpAccountAction.login,
      AcpAccountAction.openGuide,
      AcpAccountAction.openTerms,
    ],
    loginMethods: [
      AcpLoginMethodPresentation(
        label: '在浏览器登录',
        id: 'synthetic-browser',
        description: '使用个人 Google 账号在浏览器中完成登录授权（推荐个人用户使用）',
        recommended: true,
      ),
      AcpLoginMethodPresentation(
        label: '使用设备码',
        id: 'synthetic-device',
        description: '适用于企业或受限环境的备用登录方式',
      ),
    ],
    selectedLoginMethod: 'synthetic-browser',
    canSelectLoginMethod: true,
    facts: [
      AccountDisplayFact(label: '受管服务器', value: '合成版本 1.4.5 · linux-x64'),
    ],
  );
  static const acpSubscriptionUsage = AcpUsagePresentation(
    status: '已连接',
    updatedLabel: '10/26 12:34',
    queried: true,
    groups: [
      AccountQuotaGroupPresentation(
        name: 'Claude',
        quotas: [
          AccountQuotaPresentation(
            label: 'Claude Opus 4.5 / Sonnet 4.5',
            remaining: '92%',
            remainingFraction: .92,
            resetLabel: '14:12',
          ),
        ],
      ),
      AccountQuotaGroupPresentation(
        name: 'Gemini',
        quotas: [
          AccountQuotaPresentation(
            label: 'Gemini 3.1 Pro (High)',
            remaining: '18%',
            remainingFraction: .18,
            resetLabel: '今天 18:00',
            low: true,
          ),
          AccountQuotaPresentation(
            label: 'Gemini 3 Flash',
            remaining: '100%',
            remainingFraction: 1,
            resetLabel: '16:30',
          ),
        ],
      ),
    ],
  );
  static const acpManagedKey = AccountDisplayKey(
    kind: AccountKind.acp,
    id: 'synthetic-agy-managed',
  );
  static const acpManagedUpdateRow = AccountRowPresentation(
    key: acpManagedKey,
    name: 'Antigravity (受管)',
    iconKey: 'antigravity',
    content: AccountRowContent.acp(
      status: '已连接',
      phase: AcpPresentationPhase.connected,
      isManaged: true,
      sourceLabel: '官方受管 · 1.x',
      versionLabel: 'v1.4.5',
      upgrade: AcpCardUpgradePresentation(
        phase: AcpUpgradePhase.updateAvailable,
        installedVersion: '1.4.5',
        runningVersion: '1.4.5',
        latestVersion: '1.5.2',
        canUpgrade: true,
        canCheck: true,
      ),
      usage: acpSubscriptionUsage,
    ),
    actions: [
      AccountRowAction.refresh,
      AccountRowAction.upgrade,
      AccountRowAction.checkUpdate,
      AccountRowAction.edit,
      AccountRowAction.delete,
    ],
  );
  static const acpManagedUpgradingRow = AccountRowPresentation(
    key: acpManagedKey,
    name: 'Antigravity (受管)',
    iconKey: 'antigravity',
    content: AccountRowContent.acp(
      status: '已连接',
      phase: AcpPresentationPhase.connected,
      isManaged: true,
      sourceLabel: '官方受管 · 1.x',
      versionLabel: 'v1.4.5',
      upgrade: AcpCardUpgradePresentation(
        phase: AcpUpgradePhase.upgrading,
        installedVersion: '1.4.5',
        runningVersion: '1.4.5',
        latestVersion: '1.5.2',
        stageLabel: '下载官方安装包',
        progress: .64,
        progressLabel: '44.8 MB / 70.0 MB · 14.2 MB/s',
        canCancel: true,
      ),
      usage: acpSubscriptionUsage,
    ),
    actions: [
      AccountRowAction.cancelUpgrade,
      AccountRowAction.edit,
      AccountRowAction.delete,
    ],
  );
  static const acpManagedPendingSwitchRow = AccountRowPresentation(
    key: acpManagedKey,
    name: 'Antigravity (受管)',
    iconKey: 'antigravity',
    content: AccountRowContent.acp(
      status: '已连接',
      phase: AcpPresentationPhase.connected,
      isManaged: true,
      sourceLabel: '官方受管 · 1.x',
      versionLabel: 'v1.4.5',
      upgrade: AcpCardUpgradePresentation(
        phase: AcpUpgradePhase.pendingSwitch,
        installedVersion: '1.5.2',
        runningVersion: '1.4.5',
        latestVersion: '1.5.2',
        canCheck: true,
      ),
      usage: acpSubscriptionUsage,
    ),
    actions: [
      AccountRowAction.refresh,
      AccountRowAction.checkUpdate,
      AccountRowAction.edit,
      AccountRowAction.delete,
    ],
  );
  static const acpManagedUpToDateRow = AccountRowPresentation(
    key: acpManagedKey,
    name: 'Antigravity (受管)',
    iconKey: 'antigravity',
    content: AccountRowContent.acp(
      status: '已连接',
      phase: AcpPresentationPhase.connected,
      isManaged: true,
      sourceLabel: '官方受管 · 1.x',
      versionLabel: 'v1.5.2',
      upgrade: AcpCardUpgradePresentation(
        phase: AcpUpgradePhase.upToDate,
        installedVersion: '1.5.2',
        runningVersion: '1.5.2',
        latestVersion: '1.5.2',
        canCheck: true,
      ),
      usage: acpSubscriptionUsage,
    ),
    actions: [
      AccountRowAction.refresh,
      AccountRowAction.checkUpdate,
      AccountRowAction.edit,
      AccountRowAction.delete,
    ],
  );
  static const acpManagedIncompatibleRow = AccountRowPresentation(
    key: acpManagedKey,
    name: 'Antigravity (受管)',
    iconKey: 'antigravity',
    content: AccountRowContent.acp(
      status: '已连接',
      phase: AcpPresentationPhase.connected,
      isManaged: true,
      sourceLabel: '官方受管 · 1.x',
      versionLabel: 'v1.5.2',
      upgrade: AcpCardUpgradePresentation(
        phase: AcpUpgradePhase.incompatibleMajor,
        installedVersion: '1.5.2',
        runningVersion: '1.5.2',
        latestVersion: '2.0.0',
        canCheck: true,
      ),
      usage: acpSubscriptionUsage,
    ),
    actions: [
      AccountRowAction.refresh,
      AccountRowAction.checkUpdate,
      AccountRowAction.edit,
      AccountRowAction.delete,
    ],
  );
  static const acpLocalRow = AccountRowPresentation(
    key: AccountDisplayKey(kind: AccountKind.acp, id: 'synthetic-agy-local'),
    name: '本机 agy CLI',
    iconKey: 'antigravity',
    content: AccountRowContent.acp(
      status: '需要登录',
      phase: AcpPresentationPhase.needsLogin,
      isManaged: false,
      sourceLabel: '本机命令 · agy',
      versionLabel: 'v1.5.2',
    ),
    actions: [AccountRowAction.edit, AccountRowAction.delete],
  );
  static final listWithManagedAcp = AccountListPreviewData(
    canRefresh: true,
    rows: [acpManagedUpdateRow, acpLocalRow, ...list.rows],
  );
  static final acpDetailsManagedUpdate = AccountDetailsPresentation(
    key: acpManagedKey,
    name: 'Antigravity (受管)',
    iconKey: 'antigravity',
    canEdit: true,
    canDelete: true,
    content: AccountDetailsContent.acp(
      acp.copyWith(
        phase: AcpPresentationPhase.connected,
        status: '已连接',
        subtitle: '受管服务器已就绪并在后台保持单例连接。',
        message: '当前运行版本 v1.4.5，已发现 1.x 新版本 v1.5.2。',
        primaryAction: AcpAccountAction.check,
        supportsUsage: true,
        usage: acpSubscriptionUsage,
        upgrade: const AcpCardUpgradePresentation(
          phase: AcpUpgradePhase.updateAvailable,
          installedVersion: '1.4.5',
          runningVersion: '1.4.5',
          latestVersion: '1.5.2',
          canUpgrade: true,
          canCheck: true,
        ),
        availableActions: const [
          AcpAccountAction.check,
          AcpAccountAction.queryUsage,
          AcpAccountAction.openGuide,
          AcpAccountAction.openTerms,
        ],
        facts: const [
          AccountDisplayFact(label: '模板', value: 'Antigravity (受管 1.x)'),
          AccountDisplayFact(label: '安装版本', value: 'v1.4.5'),
          AccountDisplayFact(label: '目标平台', value: 'linux-x86_64'),
        ],
      ),
    ),
  );
  static final list = AccountListPreviewData(
    canRefresh: true,
    rows: [
      const AccountRowPresentation(
        key: nativeKey,
        name: 'DeepSeek',
        iconKey: 'deepseek',
        content: AccountRowContent.native(
          billing: AccountBilling.metered,
          usage: normalBalance,
          displayEndpoint: 'https://api.example.test:8443',
        ),
        actions: AccountRowAction.values,
      ),
      const AccountRowPresentation(
        key: AccountDisplayKey(
          kind: AccountKind.native,
          id: 'synthetic-openai',
        ),
        name: 'OpenAI',
        iconKey: 'openai',
        content: AccountRowContent.native(
          billing: AccountBilling.metered,
          usage: AccountUsagePresentation(phase: AccountQueryPhase.unsupported),
        ),
        actions: [AccountRowAction.edit, AccountRowAction.delete],
      ),
      const AccountRowPresentation(
        key: AccountDisplayKey(kind: AccountKind.native, id: 'synthetic-xai'),
        name: 'xAI',
        iconKey: 'xai',
        content: AccountRowContent.native(
          billing: AccountBilling.metered,
          usage: AccountUsagePresentation(phase: AccountQueryPhase.unsupported),
        ),
        actions: [AccountRowAction.edit, AccountRowAction.delete],
      ),
      const AccountRowPresentation(
        key: AccountDisplayKey(kind: AccountKind.native, id: 'synthetic-zhipu'),
        name: 'Zhipu Coding Plan',
        iconKey: 'zhipu',
        isDefault: true,
        content: AccountRowContent.native(
          billing: AccountBilling.subscription,
          usage: subscription,
        ),
        actions: AccountRowAction.values,
      ),
      const AccountRowPresentation(
        key: AccountDisplayKey(kind: AccountKind.native, id: 'synthetic-local'),
        name: '本地服务',
        content: AccountRowContent.native(
          billing: AccountBilling.noCharge,
          usage: AccountUsagePresentation(phase: AccountQueryPhase.unsupported),
        ),
        actions: [AccountRowAction.edit, AccountRowAction.delete],
      ),
    ],
  );
  static final stackedLastGoodRow = list.rows.first.copyWith(
    name: '长账号名称 · 查询保留最近数据',
    iconKey: 'unregistered',
    content: AccountRowContent.native(
      billing: AccountBilling.unknown,
      usage: balance.copyWith(
        phase: AccountQueryPhase.failed,
        canRetry: true,
        error: '合成请求失败，继续显示最近成功的多币种数据。',
      ),
    ),
  );
  static const nativeTemplates = [
    AccountTemplatePresentation(
      key: templateKey,
      name: 'DeepSeek',
      content: AccountTemplateContent.native(
        defaultBilling: AccountBilling.metered,
        protocolLabel: 'DeepSeek',
        defaultEndpoint: 'https://api.deepseek.com',
        supportsModelDiscovery: true,
        supportsUsageQuery: true,
      ),
      iconKey: 'deepseek',
    ),
    AccountTemplatePresentation(
      key: AccountTemplateKey(kind: AccountKind.native, id: 'zhipu'),
      name: '智谱',
      content: AccountTemplateContent.native(
        defaultBilling: AccountBilling.metered,
        protocolLabel: 'Zhipu · Chat Completions',
        defaultEndpoint: 'https://open.bigmodel.cn/api/paas/v4',
        supportsModelDiscovery: false,
        supportsUsageQuery: false,
      ),
      iconKey: 'zhipu',
    ),
    AccountTemplatePresentation(
      key: AccountTemplateKey(kind: AccountKind.native, id: 'openai'),
      name: 'OpenAI',
      content: AccountTemplateContent.native(
        defaultBilling: AccountBilling.metered,
        protocolLabel: 'Responses',
        defaultEndpoint: 'https://api.openai.com/v1',
        supportsModelDiscovery: true,
        supportsUsageQuery: false,
      ),
      iconKey: 'openai',
    ),
    AccountTemplatePresentation(
      key: AccountTemplateKey(kind: AccountKind.native, id: 'xai'),
      name: 'xAI',
      content: AccountTemplateContent.native(
        defaultBilling: AccountBilling.metered,
        protocolLabel: 'Responses',
        defaultEndpoint: 'https://api.x.ai/v1',
        supportsModelDiscovery: true,
        supportsUsageQuery: false,
      ),
      iconKey: 'xai',
    ),
    AccountTemplatePresentation(
      key: AccountTemplateKey(kind: AccountKind.native, id: 'vertex-ai'),
      name: 'Vertex AI',
      content: AccountTemplateContent.native(
        defaultBilling: AccountBilling.metered,
        protocolLabel: 'Google Gemini',
        defaultEndpoint:
            'https://aiplatform.googleapis.com/v1/publishers/google',
        supportsModelDiscovery: false,
        supportsUsageQuery: false,
      ),
      iconKey: 'vertex',
      description: 'Vertex AI Gemini API.',
    ),
    AccountTemplatePresentation(
      key: AccountTemplateKey(kind: AccountKind.native, id: 'gemini'),
      name: 'AI Studio',
      content: AccountTemplateContent.native(
        defaultBilling: AccountBilling.metered,
        protocolLabel: 'Google Gemini',
        defaultEndpoint: 'https://generativelanguage.googleapis.com/v1beta',
        supportsModelDiscovery: true,
        supportsUsageQuery: false,
      ),
      iconKey: 'gemini',
      description: 'Google AI Studio Gemini API.',
    ),
    AccountTemplatePresentation(
      key: AccountTemplateKey(kind: AccountKind.native, id: 'mimo-api'),
      name: 'MiMo API',
      content: AccountTemplateContent.native(
        defaultBilling: AccountBilling.metered,
        protocolLabel: 'MiMo · Chat Completions',
        defaultEndpoint: 'https://api.xiaomimimo.com/v1',
        supportsModelDiscovery: true,
        supportsUsageQuery: false,
      ),
      iconKey: 'mimo',
    ),
    AccountTemplatePresentation(
      key: AccountTemplateKey(
        kind: AccountKind.native,
        id: 'openai-compatible',
      ),
      name: 'OpenAI API 兼容',
      content: AccountTemplateContent.native(
        defaultBilling: AccountBilling.unknown,
        protocolLabel: 'OpenAI API 兼容',
        defaultEndpoint: 'http://localhost:11434/v1',
        supportsModelDiscovery: false,
        supportsUsageQuery: false,
      ),
    ),
    AccountTemplatePresentation(
      key: AccountTemplateKey(
        kind: AccountKind.native,
        id: 'zhipu-coding-plan',
      ),
      name: 'Zhipu Coding Plan',
      content: AccountTemplateContent.native(
        defaultBilling: AccountBilling.subscription,
        protocolLabel: 'Responses',
        defaultEndpoint: 'https://open.bigmodel.cn/api/v1',
        supportsModelDiscovery: false,
        supportsUsageQuery: true,
      ),
      iconKey: 'zhipu',
    ),
    AccountTemplatePresentation(
      key: AccountTemplateKey(kind: AccountKind.native, id: 'mimo-token-plan'),
      name: 'MiMo Token Plan',
      content: AccountTemplateContent.native(
        defaultBilling: AccountBilling.subscription,
        protocolLabel: 'MiMo · Chat Completions',
        defaultEndpoint: 'https://token-plan-cn.xiaomimimo.com/v1',
        supportsModelDiscovery: true,
        supportsUsageQuery: false,
      ),
      iconKey: 'mimo',
    ),
  ];
  static const templates = [
    ...nativeTemplates,
    AccountTemplatePresentation(
      key: AccountTemplateKey(kind: AccountKind.acp, id: 'command'),
      name: 'ACP',
      content: AccountTemplateContent.acp(),
    ),
    AccountTemplatePresentation(
      key: AccountTemplateKey(kind: AccountKind.acp, id: 'antigravity'),
      name: 'Antigravity',
      content: AccountTemplateContent.acp(),
      description: '合成受管服务器（仅预览）',
    ),
  ];
  static const editor = NativeAccountEditorPresentation(
    editorId: 'synthetic-editor',
    accountKey: nativeKey,
    templateKey: templateKey,
    templates: nativeTemplates,
    name: AccountTextPresentation(raw: 'DeepSeek'),
    endpoint: AccountTextPresentation(raw: 'https://api.deepseek.com'),
    credential: AccountTextPresentation(),
    hasStoredCredential: true,
    protocolLabel: 'DeepSeek',
    dirty: true,
    canSave: true,
    canAddModel: true,
    billing: billing,
    manualModels: [
      ManualAccountModelPresentation(
        editorKey: 'synthetic-manual-edit',
        id: AccountTextPresentation(raw: 'my-model'),
        name: AccountTextPresentation(raw: '我的手动模型'),
        contextWindow: AccountTextPresentation(raw: '32000'),
        maxOutputTokens: AccountTextPresentation(raw: '4096'),
        wireApi: AccountWireApi.chatCompletions,
        allowedWireApis: AccountWireApi.values,
        connection: AccountConnection.http,
        allowedConnections: [
          AccountConnection.automatic,
          AccountConnection.http,
        ],
        canRemove: true,
        canEditId: true,
      ),
    ],
  );
  static const acpEditor = AcpAccountEditorPresentation(
    source: AcpAccountSource.managed,
    editorId: 'synthetic-acp-editor',
    templateName: '官方 ACP 接入',
    name: AccountTextPresentation(raw: '我的 ACP'),
    dirty: true,
    preparation: AcpAccountPresentation(
      phase: AcpPresentationPhase.preparing,
      status: '正在下载并准备服务器',
      progress: .42,
      progressLabel: '42 MiB / 100 MiB · 2 MiB/s',
      availableActions: [
        AcpAccountAction.cancelPreparation,
        AcpAccountAction.openGuide,
        AcpAccountAction.openTerms,
      ],
      facts: [AccountDisplayFact(label: '阶段', value: '下载并校验官方服务器')],
    ),
  );
}
