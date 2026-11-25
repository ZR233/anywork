import 'package:anywork/src/features/settings/accounts/accounts_views.dart';
import 'package:anywork/src/features/settings/accounts/state/account_gemini_connection.dart';

import 'account_preview_fixtures.dart';
import 'account_list_preview_data.dart';

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

  static NativeAccountTemplateContent nativeContent(String id) =>
      switch (template(id).content) {
        final NativeAccountTemplateContent value => value,
        AcpAccountTemplateContent() => throw ArgumentError.value(
          id,
          'id',
          'not a Native template',
        ),
      };

  static AccountBilling billing(String id) => nativeContent(id).defaultBilling;

  static AccountGeminiConnectionPresentation? geminiConnection(
    String id, {
    bool creating = false,
    String? endpointRaw,
  }) => projectGeminiConnection(
    protocol: id == 'gemini' || id == 'vertex-ai' ? 'gemini' : '',
    templateId: id,
    endpoint: endpointRaw ?? endpoint(id),
    canSwitchMode: creating,
    supportsModelDiscovery: nativeContent(id).supportsModelDiscovery,
    hasBundledCatalog: id == 'vertex-ai',
  );

  static final _sharedUsageUnknownTemplate = _createUsageUnknownTemplate();

  static AccountTemplatePresentation usageUnknownTemplate() =>
      _sharedUsageUnknownTemplate;

  /// Explicitly synthetic omission state; not a built-in account template.
  static AccountTemplatePresentation _createUsageUnknownTemplate() {
    final source = nativeContent('deepseek');
    return AccountTemplatePresentation(
      key: const AccountTemplateKey(
        kind: AccountKind.native,
        id: 'synthetic-usage-unknown',
      ),
      name: '合成目录条目 · 用量能力未提供',
      iconKey: template('deepseek').iconKey,
      description: '仅展示 supportsUsageQuery 为 null 的合成状态。',
      content: AccountTemplateContent.native(
        defaultBilling: source.defaultBilling,
        protocolLabel: source.protocolLabel,
        defaultEndpoint: source.defaultEndpoint,
        supportsModelDiscovery: source.supportsModelDiscovery,
        supportsUsageQuery: null,
      ),
    );
  }

  static AccountUsagePresentation usage(String id) {
    final support = nativeContent(id).supportsUsageQuery;
    if (support == null) {
      return const AccountUsagePresentation(phase: AccountQueryPhase.idle);
    }
    if (!support) {
      return const AccountUsagePresentation(
        phase: AccountQueryPhase.unsupported,
      );
    }
    return switch (id) {
      'deepseek' => AccountPreviewFixtures.normalBalance,
      'zhipu-coding-plan' => AccountPreviewFixtures.subscription,
      _ => throw StateError('Missing synthetic usage fixture for $id'),
    };
  }

  static String endpoint(String id) => nativeContent(id).defaultEndpoint;

  static String protocol(String id) => nativeContent(id).protocolLabel;

  static AccountModelPresentation model(String id) {
    final modelId = switch (id) {
      'openai' => 'gpt-6-astra',
      'deepseek' => 'deepseek-flash',
      'xai' => 'grok-4.7',
      'zhipu' || 'zhipu-coding-plan' => 'glm-5.3',
      'mimo-api' || 'mimo-token-plan' => 'mimo-v2.5-pro',
      'vertex-ai' || 'gemini' => 'gemini-4-hydrogen',
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

  static List<AccountModelPresentation> declaredModels(String id) {
    if (id == 'openai-compatible') return const [];
    if (id == 'vertex-ai' || id == 'gemini') {
      return [
        AccountModelPresentation(
          key: AccountModelKey(account: key(id), modelId: 'gemini-4-hydrogen'),
          name: 'Gemini 4 Hydrogen',
          origin: AccountModelOrigin.bundled,
          summary: 'Fast, cost-efficient Gemini 4 multimodal reasoning model for everyday coding and agentic workflows.',
          canToggle: true,
        ),
        AccountModelPresentation(
          key: AccountModelKey(account: key(id), modelId: 'gemini-4-neon'),
          name: 'Gemini 4 Neon',
          origin: AccountModelOrigin.bundled,
          summary: 'Frontier-level Gemini 4 model balancing deep reasoning with fast end-to-end completion.',
          canToggle: true,
        ),
        AccountModelPresentation(
          key: AccountModelKey(account: key(id), modelId: 'gemini-4-argon'),
          name: 'Gemini 4 Argon',
          origin: AccountModelOrigin.bundled,
          summary: 'Efficient Gemini 4 frontier reasoning model with faster responses and lower token spend per turn than Carbon.',
          canToggle: true,
        ),
        AccountModelPresentation(
          key: AccountModelKey(account: key(id), modelId: 'gemini-4-carbon'),
          name: 'Gemini 4 Carbon',
          origin: AccountModelOrigin.bundled,
          summary: 'Strongest Gemini 4 reasoning model for complex engineering, science, and security.',
          canToggle: true,
        ),
      ];
    }
    return [model(id)];
  }

  static AccountRowPresentation row(String id, {String? displayEndpoint}) {
    final value = template(id);
    return AccountRowPresentation(
      key: key(id),
      name: value.name,
      iconKey: value.iconKey,
      content: switch (value.content) {
        NativeAccountTemplateContent(:final defaultBilling) =>
          AccountRowContent.native(
            billing: defaultBilling,
            usage: usage(id),
            displayEndpoint: displayEndpoint,
          ),
        AcpAccountTemplateContent() => AccountRowContent.acp(
          status: AccountPreviewFixtures.acp.status,
        ),
      },
      actions: [
        if (value.content case NativeAccountTemplateContent(
          supportsUsageQuery: true,
        ))
          AccountRowAction.refresh,
        if (value.content case NativeAccountTemplateContent())
          AccountRowAction.setDefault,
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
                authentication: AccountAuthenticationMethod.apiKey,
                credentialReady: id != 'openai-compatible',
                billing: billingControl(id),
                catalog: AccountCatalogPresentation(
                  models: [model(id)],
                  // No successful online check is simulated.
                  canSync: nativeContent(id).supportsModelDiscovery,
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
        isOpenAiTemplate: id == 'openai',
        protocolLabel: protocol(id),
        geminiConnection: geminiConnection(id),
        canSave: true,
        canAddModel: true,
        billing: billingControl(id),
        declaredModels: declaredModels(id),
        manualModels: id == 'openai-compatible'
            ? AccountPreviewFixtures.editor.manualModels
            : [],
      );

  static String? credentialHelper(String id) => switch (id) {
    'vertex-ai' || 'gemini' => null,
    _ => template(id).description,
  };

  static NativeAccountEditorPresentation createEditor(String id) {
    final isGemini = id == 'vertex-ai' || id == 'gemini';
    return NativeAccountEditorPresentation(
      editorId: 'create-$id',
      templateKey: template(id).key,
      templates: AccountPreviewFixtures.nativeTemplates,
      name: AccountTextPresentation(
        raw: template(id).name,
        helper: isGemini ? null : template(id).description,
      ),
      endpoint: AccountTextPresentation(raw: endpoint(id)),
      credential: AccountTextPresentation(helper: credentialHelper(id)),
      canChangeTemplate: true,
      showSetDefaultOnCreate: true,
      hasStoredCredential: false,
      credentialRequired: id != 'openai-compatible',
      isOpenAiTemplate: id == 'openai',
      protocolLabel: protocol(id),
      geminiConnection: geminiConnection(id, creating: true),
      canSave: true,
      canAddModel: true,
      billing: billingControl(id),
      declaredModels: declaredModels(id),
      manualModels: const [],
    );
  }

  static NativeAccountEditorPresentation
  geminiEditEditor() => editor('vertex-ai').copyWith(
    dirty: true,
    geminiConnection: geminiConnection(
      'vertex-ai',
      endpointRaw: AccountGeminiEndpointPreset.vertexUsCentral1.endpoint,
    ),
    endpoint: const AccountTextPresentation(
      raw: 'https://us-central1-aiplatform.googleapis.com/v1/publishers/google',
    ),
    manualModels: const [
      ManualAccountModelPresentation(
        editorKey: 'synthetic-gemini-manual',
        id: AccountTextPresentation(raw: 'gemini-4-neon'),
        name: AccountTextPresentation(raw: 'Gemini 4 Neon (us-central1)'),
        contextWindow: AccountTextPresentation(raw: '1048576'),
        maxOutputTokens: AccountTextPresentation(raw: '65536'),
        wireApi: AccountWireApi.geminiGenerateContent,
        allowedWireApis: [AccountWireApi.geminiGenerateContent],
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

  static final editorWithUsageUnknownTemplate =
      _createEditorWithUsageUnknownTemplate();

  static NativeAccountEditorPresentation
  _createEditorWithUsageUnknownTemplate() {
    final base = editor('deepseek');
    final unknown = usageUnknownTemplate();
    return base.copyWith(
      templates: [...base.templates, unknown],
      templateKey: unknown.key,
    );
  }

  static AccountListPreviewData get allTemplates => AccountListPreviewData(
    canRefresh: true,
    rows: [
      for (final value in AccountPreviewFixtures.templates) row(value.key.id),
    ],
  );
}
