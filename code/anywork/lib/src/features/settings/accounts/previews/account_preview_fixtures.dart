import '../accounts_views.dart';

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
    id: 'synthetic-deepseek',
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
    capabilities: [
      AccountDisplayFact(label: '上下文窗口', value: '1,050,000 tokens'),
      AccountDisplayFact(label: '输入 / 输出', value: '文本、视觉 / 文本'),
      AccountDisplayFact(label: '能力', value: '流式输出 · 思考 · 工具调用'),
    ],
    priceTiers: [
      AccountDisplayFact(
        label: '≤ 128K · CNY / 1M tokens',
        value: '输入 2.00 · 输出 3.00 · 缓存读 0.20',
      ),
      AccountDisplayFact(
        label: '> 128K · CNY / 1M tokens',
        value: '输入 4.00 · 输出 6.00 · 缓存读 0.40',
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
    performance: [
      AccountDisplayFact(
        label: '标准 · 12 次成功调用',
        value: '首词元 0.8s · 输出 42 tokens/s',
      ),
      AccountDisplayFact(
        label: '高思考 · 4 次成功调用',
        value: '首词元 2.1s · 输出 36 tokens/s',
      ),
    ],
    evaluations: [
      AccountModelEvaluation(
        title: '合成任务 A',
        outcome: '通过',
        updatedLabel: '10/26 12:34',
        comment: '完整保留输入语义，并正确处理边界。',
        scores: [AccountDisplayFact(label: '正确性 / 完整性', value: '4 / 5')],
      ),
      AccountModelEvaluation(
        title: '合成任务 B',
        outcome: '未通过',
        updatedLabel: '10/25 09:12',
        comment: '缺少失败恢复；此条仅用于预览。',
      ),
    ],
  );
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
    endpoint: 'https://api.synthetic.invalid/v1',
    canEdit: true,
    canDelete: true,
    canSetDefault: true,
    content: AccountDetailsContent.native(
      NativeAccountDetailsPresentation(
        credentialReady: true,
        billing: billing,
        catalog: catalog,
        usage: balance,
        advanced: const [
          AccountDisplayFact(label: '账号 ID', value: 'synthetic-native'),
          AccountDisplayFact(label: '模板', value: '合成 DeepSeek'),
          AccountDisplayFact(label: '协议', value: 'DeepSeek'),
        ],
      ),
    ),
  );
  static const acp = AcpAccountPresentation(
    phase: AcpPresentationPhase.needsLogin,
    status: '需要登录',
    message: '已完成连接检查。请选择官方支持的登录方式。',
    primaryAction: AcpAccountAction.login,
    availableActions: [
      AcpAccountAction.check,
      AcpAccountAction.login,
      AcpAccountAction.openGuide,
      AcpAccountAction.openTerms,
    ],
    loginMethods: [
      AcpLoginMethodPresentation(label: '在浏览器登录', id: 'synthetic-browser'),
      AcpLoginMethodPresentation(label: '使用设备码', id: 'synthetic-device'),
    ],
    selectedLoginMethod: 'synthetic-browser',
    canSelectLoginMethod: true,
    facts: [
      AccountDisplayFact(label: '受管服务器', value: '合成版本 1.4.1 · linux-x64'),
    ],
  );
  static final list = AccountsListPresentation(
    canRefresh: true,
    rows: [
      const AccountRowPresentation(
        key: nativeKey,
        name: 'DeepSeek',
        iconKey: 'deepseek',
        billing: AccountBilling.metered,
        usage: balance,
        actions: AccountRowAction.values,
      ),
      const AccountRowPresentation(
        key: AccountDisplayKey(
          kind: AccountKind.native,
          id: 'synthetic-openai',
        ),
        name: 'OpenAI',
        iconKey: 'openai',
        billing: AccountBilling.metered,
        usage: AccountUsagePresentation(phase: AccountQueryPhase.unsupported),
        actions: [AccountRowAction.edit, AccountRowAction.delete],
      ),
      const AccountRowPresentation(
        key: AccountDisplayKey(kind: AccountKind.native, id: 'synthetic-zhipu'),
        name: 'Zhipu Coding Plan',
        iconKey: 'zhipu',
        isDefault: true,
        billing: AccountBilling.subscription,
        usage: subscription,
        actions: AccountRowAction.values,
      ),
      AccountRowPresentation(
        key: const AccountDisplayKey(
          kind: AccountKind.native,
          id: 'synthetic-failed',
        ),
        name: '刷新失败 · 保留最近成功数据',
        iconKey: 'deepseek',
        billing: AccountBilling.metered,
        usage: balance.copyWith(
          phase: AccountQueryPhase.failed,
          canRetry: true,
          error: '合成网络错误，请重试。',
        ),
        actions: AccountRowAction.values,
      ),
      const AccountRowPresentation(
        key: AccountDisplayKey(kind: AccountKind.native, id: 'synthetic-local'),
        name: '本地服务',
        billing: AccountBilling.noCharge,
        usage: AccountUsagePresentation(phase: AccountQueryPhase.unsupported),
        actions: [AccountRowAction.edit, AccountRowAction.delete],
      ),
      const AccountRowPresentation(
        key: acpKey,
        name: '官方 ACP · 合成接入',
        acpStatus: '需要登录',
        actions: [AccountRowAction.edit, AccountRowAction.delete],
      ),
    ],
  );
  static const nativeTemplates = [
    AccountTemplatePresentation(
      key: templateKey,
      name: 'DeepSeek',
      iconKey: 'deepseek',
    ),
    AccountTemplatePresentation(
      key: AccountTemplateKey(kind: AccountKind.native, id: 'synthetic-zhipu'),
      name: '智谱',
      iconKey: 'zhipu',
    ),
    AccountTemplatePresentation(
      key: AccountTemplateKey(kind: AccountKind.native, id: 'synthetic-openai'),
      name: 'OpenAI · 合成模板',
      iconKey: 'openai',
    ),
    AccountTemplatePresentation(
      key: AccountTemplateKey(kind: AccountKind.native, id: 'synthetic-xai'),
      name: 'xAI · 合成模板',
      iconKey: 'xai',
    ),
    AccountTemplatePresentation(
      key: AccountTemplateKey(kind: AccountKind.native, id: 'synthetic-mimo'),
      name: 'MiMo · 合成模板',
      iconKey: 'mimo',
    ),
    AccountTemplatePresentation(
      key: AccountTemplateKey(
        kind: AccountKind.native,
        id: 'synthetic-compatible',
      ),
      name: '兼容接口 · 合成模板',
    ),
    AccountTemplatePresentation(
      key: AccountTemplateKey(kind: AccountKind.native, id: 'synthetic-local'),
      name: '本地模型 · 合成模板',
    ),
    AccountTemplatePresentation(
      key: AccountTemplateKey(kind: AccountKind.native, id: 'synthetic-team'),
      name: '团队网关 · 合成模板',
    ),
  ];
  // Native entries intentionally precede ACP in input; the production picker
  // must still place Antigravity first at a realistic catalog size.
  static const templates = [
    ...nativeTemplates,
    AccountTemplatePresentation(
      key: AccountTemplateKey(kind: AccountKind.acp, id: 'synthetic-acp'),
      name: 'Antigravity',
      description: '合成受管服务器（仅预览）',
    ),
  ];
  static const editor = NativeAccountEditorPresentation(
    editorId: 'synthetic-editor',
    accountKey: nativeKey,
    templateKey: templateKey,
    templates: nativeTemplates,
    name: AccountTextPresentation(raw: 'DeepSeek'),
    endpoint: AccountTextPresentation(raw: 'https://api.synthetic.invalid/v1'),
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
