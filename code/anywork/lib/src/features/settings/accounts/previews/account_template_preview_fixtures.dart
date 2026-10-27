import '../accounts_views.dart';
import 'account_preview_fixtures.dart';

/// Real template identities/endpoints with explicitly synthetic account state.
/// No providers, credentials or runtime are initialized by these fixtures.
abstract final class AccountTemplatePreviewFixtures {
  static AccountTemplatePresentation template(String id) =>
      AccountPreviewFixtures.templates.singleWhere(
        (value) => value.key.id == id,
      );

  static AccountDisplayKey key(String id) => AccountDisplayKey(
    kind: id == 'antigravity' ? AccountKind.acp : AccountKind.native,
    id: 'preview-$id',
  );

  static AccountBilling billing(String id) => switch (id) {
    'zhipu-coding-plan' || 'mimo-token-plan' => AccountBilling.subscription,
    'openai-compatible' => AccountBilling.unknown,
    _ => AccountBilling.metered,
  };

  static AccountUsagePresentation usage(String id) => switch (id) {
    'deepseek' => AccountPreviewFixtures.normalBalance,
    'zhipu-coding-plan' => AccountPreviewFixtures.subscription,
    // MiMo Token Plan has subscription billing but no usage query. Do not
    // manufacture Zhipu quota windows or a monetary balance for it.
    _ => const AccountUsagePresentation(phase: AccountQueryPhase.unsupported),
  };

  static String endpoint(String id) => switch (id) {
    'openai' => 'https://api.openai.com/v1',
    'deepseek' => 'https://api.deepseek.com',
    'xai' => 'https://api.x.ai/v1',
    'zhipu' => 'https://open.bigmodel.cn/api/paas/v4',
    'zhipu-coding-plan' => 'https://open.bigmodel.cn/api/v1',
    'mimo-api' => 'https://api.xiaomimimo.com/v1',
    'mimo-token-plan' => 'https://token-plan-cn.xiaomimimo.com/v1',
    'openai-compatible' => 'http://localhost:11434/v1',
    _ => throw ArgumentError.value(id, 'id', 'not a Native template'),
  };

  static String protocol(String id) => switch (id) {
    'openai' || 'xai' || 'zhipu-coding-plan' => 'Responses',
    'deepseek' => 'DeepSeek',
    'zhipu' => 'Zhipu · Chat Completions',
    'mimo-api' || 'mimo-token-plan' => 'MiMo · Chat Completions',
    _ => 'OpenAI API 兼容 · Chat Completions',
  };

  static AccountModelPresentation model(String id) {
    final modelId = switch (id) {
      'openai' => 'gpt-6-astra',
      'deepseek' => 'deepseek-flash',
      'xai' => 'grok-4.7',
      'zhipu' || 'zhipu-coding-plan' => 'glm-5.3',
      'mimo-api' || 'mimo-token-plan' => 'mimo-v2.5-pro',
      _ => 'my-custom-model',
    };
    return AccountModelPresentation(
      key: AccountModelKey(account: key(id), modelId: modelId),
      name: modelId,
      origin: id == 'openai-compatible'
          ? AccountModelOrigin.manual
          : AccountModelOrigin.bundled,
      canToggle: true,
      canEdit: id == 'openai-compatible',
      canDelete: id == 'openai-compatible',
      // Capability/price/performance facts are omitted rather than borrowing
      // another template's declarations. Rich synthetic readouts have their
      // own component/state previews in accounts_previews.dart.
    );
  }

  static AccountRowPresentation row(String id) {
    final value = template(id);
    return AccountRowPresentation(
      key: key(id),
      name: value.name,
      iconKey: value.iconKey,
      billing: id == 'antigravity' ? null : billing(id),
      usage: id == 'antigravity' ? null : usage(id),
      acpStatus: id == 'antigravity' ? AccountPreviewFixtures.acp.status : null,
      actions: [
        if (id == 'deepseek' || id == 'zhipu-coding-plan')
          AccountRowAction.refresh,
        if (id != 'antigravity') AccountRowAction.setDefault,
        AccountRowAction.edit,
        AccountRowAction.delete,
      ],
    );
  }

  static AccountBillingPresentation billingControl(String id) =>
      AccountBillingPresentation(
        effective: billing(id),
        allowedOverrides: AccountPreviewFixtures.billingOverrides,
      );

  static AccountDetailsPresentation details(String id) {
    final value = template(id);
    return AccountDetailsPresentation(
      key: key(id),
      name: value.name,
      iconKey: value.iconKey,
      endpoint: id == 'antigravity' ? null : endpoint(id),
      canEdit: true,
      canDelete: true,
      canSetDefault: id != 'antigravity',
      content: id == 'antigravity'
          ? const AccountDetailsContent.acp(AccountPreviewFixtures.acp)
          : AccountDetailsContent.native(
              NativeAccountDetailsPresentation(
                credentialReady: id != 'openai-compatible',
                billing: billingControl(id),
                catalog: AccountCatalogPresentation(
                  models: [model(id)],
                  // Discovery capability is independent of the retained
                  // bundled snapshot; no successful online check is simulated.
                  canSync: switch (id) {
                    'openai' ||
                    'deepseek' ||
                    'xai' ||
                    'mimo-api' ||
                    'mimo-token-plan' => true,
                    _ => false,
                  },
                  sourceLabel: id == 'openai-compatible' ? '手动模型' : '内置目录',
                ),
                usage: usage(id),
                advanced: [
                  AccountDisplayFact(label: '账号 ID', value: key(id).id),
                  AccountDisplayFact(label: '模板', value: id),
                  AccountDisplayFact(label: '协议', value: protocol(id)),
                ],
              ),
            ),
    );
  }

  static NativeAccountEditorPresentation editor(String id) =>
      NativeAccountEditorPresentation(
        editorId: 'editor-$id',
        accountKey: key(id),
        templateKey: template(id).key,
        templates: AccountPreviewFixtures.nativeTemplates,
        name: AccountTextPresentation(raw: template(id).name),
        endpoint: AccountTextPresentation(raw: endpoint(id)),
        credential: const AccountTextPresentation(),
        hasStoredCredential: id != 'openai-compatible',
        credentialRequired: id != 'openai-compatible',
        protocolLabel: protocol(id),
        canSave: true,
        canAddModel: true,
        billing: billingControl(id),
        declaredModels: id == 'openai-compatible' ? [] : [model(id)],
        manualModels: id == 'openai-compatible'
            ? AccountPreviewFixtures.editor.manualModels
            : [],
      );

  static AccountsListPresentation get allTemplates => AccountsListPresentation(
    canRefresh: true,
    rows: [
      for (final value in AccountPreviewFixtures.templates) row(value.key.id),
    ],
  );
}
