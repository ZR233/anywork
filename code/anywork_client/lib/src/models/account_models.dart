import 'model_catalog.dart';
import 'delegation_models.dart';

enum ModelModalityView { text, image, audio, video, file }

enum ModelType { text }

enum ModelTypeExclusion {
  textInputUnsupported,
  textOutputUnsupported,
  contextWindowUnknown,
  contextParametersInvalid,
  inputBudgetExhausted,
}

class ModelTypeSupportView {
  const ModelTypeSupportView({
    required this.modelType,
    this.exclusions = const [],
  });
  final ModelType modelType;
  final List<ModelTypeExclusion> exclusions;
}

enum ModelInputSourceView { local, remoteUrl }

class ModelInputCapabilityView {
  const ModelInputCapabilityView({
    required this.modality,
    required this.sources,
    this.maxCount,
    this.maxBytes,
    this.maxTotalBytes,
    this.maxWidth,
    this.maxHeight,
    this.mediaTypes = const [],
  });

  final ModelModalityView modality;
  final List<ModelInputSourceView> sources;
  final int? maxCount;
  final int? maxBytes;
  final int? maxTotalBytes;
  final int? maxWidth;
  final int? maxHeight;
  final List<String> mediaTypes;

  bool supportsSource(ModelInputSourceView source) => sources.contains(source);
}

class ModelPriceTierView {
  const ModelPriceTierView({
    required this.label,
    required this.input,
    required this.output,
    this.cacheRead,
    this.cacheWrite,
  });
  final String label;
  final double input;
  final double output;
  final double? cacheRead;
  final double? cacheWrite;
}

enum ModelContextUnavailable {
  windowUnknown,
  invalidParameters,
  inputBudgetExhausted,
}

enum ModelContextAdjustment { safetyLimit }

/// Immutable backend result; this layer performs no budget or threshold arithmetic.
class ModelContextView {
  const ModelContextView({
    this.unavailable = ModelContextUnavailable.windowUnknown,
    this.contextWindow,
    this.inputTokenLimit,
    this.autoCompactLimit,
    this.adjustment,
  });
  final ModelContextUnavailable? unavailable;
  final int? contextWindow;
  final int? inputTokenLimit;
  final int? autoCompactLimit;
  final ModelContextAdjustment? adjustment;
  @override
  bool operator ==(Object other) =>
      other is ModelContextView &&
      unavailable == other.unavailable &&
      contextWindow == other.contextWindow &&
      inputTokenLimit == other.inputTokenLimit &&
      autoCompactLimit == other.autoCompactLimit &&
      adjustment == other.adjustment;
  @override
  int get hashCode => Object.hash(
    unavailable,
    contextWindow,
    inputTokenLimit,
    autoCompactLimit,
    adjustment,
  );
}

class AccountModelView {
  const AccountModelView({
    required this.modelId,
    required this.displayName,
    required this.reasoningEfforts,
    this.enabled = true,
    this.typeSupport = const [],
    this.description = '',
    this.contextWindow,
    this.maxContextWindow,
    this.context = const ModelContextView(),
    this.maxOutputTokens,
    this.inputCapabilities = const [],
    this.outputModalities = const [],
    this.capabilities = const [],
    this.reasoningLabel = '',
    this.defaultReasoningEffort = '',
    this.currency = '',
    this.priceSource = '',
    this.priceVerifiedAt,
    this.priceTiers = const [],
    this.baseInstructions = '',
    this.wireApi = 'chat_completions',
    this.supportedConnectionModes = const ['http'],
    this.defaultConnectionMode = 'http',
    this.connectionMode = 'http',
    this.origin = ModelOrigin.bundled,
  });

  final String modelId;
  final bool enabled;
  final List<ModelTypeSupportView> typeSupport;

  ModelTypeSupportView? supportFor(ModelType type) =>
      typeSupport.where((support) => support.modelType == type).firstOrNull;

  bool matchesType(ModelType type) =>
      supportFor(type)?.exclusions.isEmpty == true;
  final String displayName;
  final List<String> reasoningEfforts;
  final String description;
  final int? contextWindow;
  final int? maxContextWindow;

  /// 后端完成声明合并和账号覆盖解析后的最终上下文策略。
  final ModelContextView context;
  final int? maxOutputTokens;
  final List<ModelInputCapabilityView> inputCapabilities;
  final List<ModelModalityView> outputModalities;
  final List<String> capabilities;
  final String reasoningLabel;
  final String defaultReasoningEffort;
  final String currency;
  final String priceSource;
  final int? priceVerifiedAt;
  final List<ModelPriceTierView> priceTiers;
  final String baseInstructions;
  final String wireApi;
  final List<String> supportedConnectionModes;
  final String defaultConnectionMode;
  final String connectionMode;
  final ModelOrigin origin;

  AccountModelView copyWith({
    String? modelId,
    bool? enabled,
    String? displayName,
    List<String>? reasoningEfforts,
    List<ModelTypeSupportView>? typeSupport,
    String? description,
    int? contextWindow,
    int? maxContextWindow,
    ModelContextView? context,
    int? maxOutputTokens,
    List<ModelInputCapabilityView>? inputCapabilities,
    List<ModelModalityView>? outputModalities,
    List<String>? capabilities,
    String? reasoningLabel,
    String? defaultReasoningEffort,
    String? currency,
    String? priceSource,
    int? priceVerifiedAt,
    List<ModelPriceTierView>? priceTiers,
    String? baseInstructions,
    String? wireApi,
    List<String>? supportedConnectionModes,
    String? defaultConnectionMode,
    String? connectionMode,
    ModelOrigin? origin,
  }) {
    return AccountModelView(
      modelId: modelId ?? this.modelId,
      enabled: enabled ?? this.enabled,
      displayName: displayName ?? this.displayName,
      reasoningEfforts: reasoningEfforts ?? this.reasoningEfforts,
      typeSupport: typeSupport ?? this.typeSupport,
      description: description ?? this.description,
      contextWindow: contextWindow ?? this.contextWindow,
      maxContextWindow: maxContextWindow ?? this.maxContextWindow,
      context: context ?? this.context,
      maxOutputTokens: maxOutputTokens ?? this.maxOutputTokens,
      inputCapabilities: inputCapabilities ?? this.inputCapabilities,
      outputModalities: outputModalities ?? this.outputModalities,
      capabilities: capabilities ?? this.capabilities,
      reasoningLabel: reasoningLabel ?? this.reasoningLabel,
      defaultReasoningEffort:
          defaultReasoningEffort ?? this.defaultReasoningEffort,
      currency: currency ?? this.currency,
      priceSource: priceSource ?? this.priceSource,
      priceVerifiedAt: priceVerifiedAt ?? this.priceVerifiedAt,
      priceTiers: priceTiers ?? this.priceTiers,
      baseInstructions: baseInstructions ?? this.baseInstructions,
      wireApi: wireApi ?? this.wireApi,
      supportedConnectionModes:
          supportedConnectionModes ?? this.supportedConnectionModes,
      defaultConnectionMode:
          defaultConnectionMode ?? this.defaultConnectionMode,
      connectionMode: connectionMode ?? this.connectionMode,
      origin: origin ?? this.origin,
    );
  }
}

/// Raw persisted override intent and the catalog's final context read model.
class AccountModelAutoCompactView {
  const AccountModelAutoCompactView({
    required this.modelId,
    this.overrideLimit,
    this.context = const ModelContextView(),
  });
  final String modelId;
  final int? overrideLimit;
  final ModelContextView context;
  bool get hasOverride => overrideLimit != null;
}

class AccountSettingsView {
  const AccountSettingsView({
    this.billingKind = BillingKind.unknown,
    this.billingKindOverride,
    this.disabledModels = const [],
    this.modelCatalog = const ModelCatalogStatusView(),
    required this.id,
    this.templateId,
    this.protocol = '',
    required this.name,
    this.subtitle = '',
    required this.baseUrl,
    this.bearerToken = '',
    this.hasBearerToken = false,
    this.credentialRequired = true,
    this.usageQueryRevision = 0,
    required this.defaultModelId,
    required this.models,
    this.modelConnectionModes = const {},
    this.autoCompactLimits = const {},
    required this.status,
    required this.usageLabel,
    this.modelCount = '',
    this.updatedAt = '',
    this.catalogId = '',
    this.credentialLabel = 'API Key',
    this.credentialEnv = '',
    this.capabilitySource = 'explicit',
    this.hostedWebSearch = false,
    this.hostedWebSearchDialect = 'open_ai_responses',
    this.standaloneWebSearch = '',
    this.promptCacheDialect = 'none',
    this.responsesProgrammaticToolCalling = false,
    this.iconKey,
  });

  final BillingKind billingKind;
  final BillingKind? billingKindOverride;
  final List<String> disabledModels;
  final ModelCatalogStatusView modelCatalog;
  final String id;

  /// 可选的内置账号模板引用；完全自定义账号为 `null`。
  final String? templateId;

  /// 明确的厂商协议适配选择；来自 canonical 配置或模板 descriptor。
  final String protocol;
  final String name;
  final String subtitle;
  final String baseUrl;
  final String bearerToken;
  final bool hasBearerToken;
  final bool credentialRequired;
  final int usageQueryRevision;

  /// 目录或创建路由的默认模型投影；不是账号 runtime 的第二份模型选择。
  final String defaultModelId;
  final List<AccountModelView> models;

  /// Queries the canonical model-layer classification; omitted type returns the full catalog.
  List<AccountModelView> modelsFor({ModelType? type}) => type == null
      ? models
      : models
            .where((model) => model.matchesType(type) && model.enabled)
            .toList();
  final Map<String, String> modelConnectionModes;
  final Map<String, AccountModelAutoCompactView> autoCompactLimits;
  final String status;
  final String usageLabel;
  final String modelCount;
  final String updatedAt;
  final String catalogId;
  final String credentialLabel;
  final String credentialEnv;
  final String capabilitySource;
  final bool hostedWebSearch;
  final String hostedWebSearchDialect;
  final String standaloneWebSearch;
  final String promptCacheDialect;
  final bool responsesProgrammaticToolCalling;
  final String? iconKey;

  List<AccountModelView> modelsWithOrigin(ModelOrigin origin) => [
    for (final model in models)
      if (model.origin == origin) model,
  ];

  List<AccountModelView> get bundledModels =>
      modelsWithOrigin(ModelOrigin.bundled);

  List<AccountModelView> get onlineModels =>
      modelsWithOrigin(ModelOrigin.online);

  List<AccountModelView> get customModels =>
      modelsWithOrigin(ModelOrigin.manual);

  AccountSettingsView withModelConnection(String modelId, String mode) {
    AccountModelView update(AccountModelView model) =>
        model.modelId == modelId ? model.copyWith(connectionMode: mode) : model;
    return copyWith(
      models: models.map(update).toList(),
      modelConnectionModes: {...modelConnectionModes, modelId: mode},
    );
  }

  AccountModelAutoCompactView autoCompactLimitFor(AccountModelView model) =>
      AccountModelAutoCompactView(
        modelId: model.modelId,
        overrideLimit: autoCompactLimits[model.modelId]?.overrideLimit,
        context: model.context,
      );

  /// Apply a raw intent; only the backend resolves its effective policy.
  AccountSettingsView withAutoCompactLimit(AccountModelAutoCompactView limit) {
    return copyWith(
      autoCompactLimits: {...autoCompactLimits, limit.modelId: limit},
    );
  }

  AccountSettingsView copyWith({
    ModelCatalogStatusView? modelCatalog,
    BillingKind? billingKind,
    Object? billingKindOverride = _accountSettingsUnset,
    List<String>? disabledModels,
    String? id,
    Object? templateId = _accountTemplateUnset,
    String? protocol,
    String? name,
    String? subtitle,
    String? baseUrl,
    String? bearerToken,
    bool? hasBearerToken,
    bool? credentialRequired,
    int? usageQueryRevision,
    String? defaultModelId,
    List<AccountModelView>? models,
    Map<String, String>? modelConnectionModes,
    Map<String, AccountModelAutoCompactView>? autoCompactLimits,
    String? status,
    String? usageLabel,
    String? modelCount,
    String? updatedAt,
    String? catalogId,
    String? credentialLabel,
    String? credentialEnv,
    String? capabilitySource,
    bool? hostedWebSearch,
    String? hostedWebSearchDialect,
    String? standaloneWebSearch,
    String? promptCacheDialect,
    bool? responsesProgrammaticToolCalling,
    Object? iconKey = _accountSettingsUnset,
  }) {
    return AccountSettingsView(
      modelCatalog: modelCatalog ?? this.modelCatalog,
      billingKind: billingKind ?? this.billingKind,
      billingKindOverride: identical(billingKindOverride, _accountSettingsUnset)
          ? this.billingKindOverride
          : billingKindOverride as BillingKind?,
      disabledModels: disabledModels ?? this.disabledModels,
      id: id ?? this.id,
      templateId: identical(templateId, _accountTemplateUnset)
          ? this.templateId
          : templateId as String?,
      protocol: protocol ?? this.protocol,
      name: name ?? this.name,
      subtitle: subtitle ?? this.subtitle,
      baseUrl: baseUrl ?? this.baseUrl,
      bearerToken: bearerToken ?? this.bearerToken,
      hasBearerToken: hasBearerToken ?? this.hasBearerToken,
      credentialRequired: credentialRequired ?? this.credentialRequired,
      usageQueryRevision: usageQueryRevision ?? this.usageQueryRevision,
      defaultModelId: defaultModelId ?? this.defaultModelId,
      models: models ?? this.models,
      modelConnectionModes: modelConnectionModes ?? this.modelConnectionModes,
      autoCompactLimits: autoCompactLimits ?? this.autoCompactLimits,
      status: status ?? this.status,
      usageLabel: usageLabel ?? this.usageLabel,
      modelCount: modelCount ?? this.modelCount,
      updatedAt: updatedAt ?? this.updatedAt,
      catalogId: catalogId ?? this.catalogId,
      credentialLabel: credentialLabel ?? this.credentialLabel,
      credentialEnv: credentialEnv ?? this.credentialEnv,
      capabilitySource: capabilitySource ?? this.capabilitySource,
      hostedWebSearch: hostedWebSearch ?? this.hostedWebSearch,
      hostedWebSearchDialect:
          hostedWebSearchDialect ?? this.hostedWebSearchDialect,
      standaloneWebSearch: standaloneWebSearch ?? this.standaloneWebSearch,
      promptCacheDialect: promptCacheDialect ?? this.promptCacheDialect,
      responsesProgrammaticToolCalling:
          responsesProgrammaticToolCalling ??
          this.responsesProgrammaticToolCalling,
      iconKey: identical(iconKey, _accountSettingsUnset)
          ? this.iconKey
          : iconKey as String?,
    );
  }
}

const _accountSettingsUnset = Object();
const _accountTemplateUnset = Object();

class AccountCatalogView {
  const AccountCatalogView({
    required this.schemaVersion,
    required this.revision,
    required this.templates,
    required this.modelCatalogs,
  });

  const AccountCatalogView.empty()
    : schemaVersion = 0,
      revision = '',
      templates = const [],
      modelCatalogs = const {};

  final int schemaVersion;
  final String revision;
  final List<AccountTemplateView> templates;
  final Map<String, List<AccountModelView>> modelCatalogs;

  /// 空目录只表示尚未加载，不能覆盖已经加载的静态事实。
  bool get isUsable => revision.isNotEmpty && templates.isNotEmpty;

  AccountTemplateView? template(String id) {
    for (final template in templates) {
      if (template.id == id) return template;
    }
    return null;
  }

  List<AccountModelView> modelsFor(String catalogId) {
    return modelCatalogs[catalogId] ?? const [];
  }
}

class AccountTemplateView {
  const AccountTemplateView({
    required this.id,
    required this.displayName,
    required this.description,
    required this.baseUrl,
    required this.credentialLabel,
    required this.credentialEnv,
    required this.modelCatalogId,
    required this.protocol,
    required this.suggestedModelId,
    this.hostedWebSearch = false,
    this.hostedWebSearchDialect = 'open_ai_responses',
    this.standaloneWebSearch = '',
    this.promptCacheDialect = 'none',
    this.responsesProgrammaticToolCalling = false,
    this.iconKey,
  });

  final String id;
  final String displayName;
  final String description;
  final String baseUrl;
  final String credentialLabel;
  final String credentialEnv;
  final String modelCatalogId;

  /// 模板默认的厂商协议选择；与 canonical descriptor 的 wire 值一致。
  final String protocol;

  /// 模板推荐的默认模型；不是账号 runtime 的第二份模型选择。
  final String suggestedModelId;
  final bool hostedWebSearch;
  final String hostedWebSearchDialect;
  final String standaloneWebSearch;
  final String promptCacheDialect;
  final bool responsesProgrammaticToolCalling;
  final String? iconKey;

  /// 以该模板重建一份完整的不可变账号草稿；模板只提供创建默认值。
  AccountSettingsView createAccount(
    String accountId,
    List<AccountModelView> models,
  ) {
    return AccountSettingsView(
      id: accountId,
      templateId: id,
      protocol: protocol,
      name: displayName,
      subtitle: description,
      baseUrl: baseUrl,
      bearerToken: '',
      hasBearerToken: false,
      usageQueryRevision: 0,
      defaultModelId: suggestedModelId,
      models: [
        for (final model in models)
          model.origin == ModelOrigin.bundled
              ? model
              : model.copyWith(origin: ModelOrigin.bundled),
      ],
      status: credentialEnv.isEmpty ? 'ready' : 'missingCredential',
      credentialRequired: credentialEnv.isNotEmpty,
      usageLabel: '${models.length} models',
      modelCount: '${models.length}',
      updatedAt: 'Draft',
      catalogId: modelCatalogId,
      credentialLabel: credentialLabel,
      credentialEnv: credentialEnv,
      capabilitySource: 'template_defaults',
      hostedWebSearch: hostedWebSearch,
      hostedWebSearchDialect: hostedWebSearchDialect,
      standaloneWebSearch: standaloneWebSearch,
      promptCacheDialect: promptCacheDialect,
      responsesProgrammaticToolCalling: responsesProgrammaticToolCalling,
      iconKey: iconKey,
    );
  }
}

class ModelConnectionModeView {
  const ModelConnectionModeView({required this.id, required this.displayName});

  final String id;
  final String displayName;
}

AccountSettingsView accountWithCatalogMetadata(
  AccountSettingsView account,
  AccountCatalogView catalog,
) {
  final template = catalog.template(account.templateId ?? '');
  AccountModelView applyConnectionMode(AccountModelView model) =>
      model.copyWith(
        connectionMode:
            account.modelConnectionModes[model.modelId] ??
            model.defaultConnectionMode,
      );
  final effectiveModels = account.models.map(applyConnectionMode).toList();
  return account.copyWith(
    subtitle: account.subtitle.isEmpty && template != null
        ? template.description
        : account.subtitle,
    catalogId: template?.modelCatalogId ?? account.catalogId,
    credentialLabel: template?.credentialLabel ?? account.credentialLabel,
    credentialEnv: template?.credentialEnv ?? account.credentialEnv,
    iconKey: template?.iconKey ?? account.iconKey,
    models: effectiveModels,
    modelCount: '${effectiveModels.length}',
    usageLabel: effectiveModels.isEmpty
        ? account.defaultModelId
        : '${effectiveModels.length} models',
  );
}

/// 为整组供应商附加静态目录元数据。
///
/// 所有 UI 投影都通过这里完成目录 join，避免设置、状态栏和 Driver 各自
/// 维护一份字段合并逻辑。
List<AccountSettingsView> accountsWithCatalogMetadata(
  Iterable<AccountSettingsView> accounts,
  AccountCatalogView catalog,
) => [
  for (final account in accounts) accountWithCatalogMetadata(account, catalog),
];

class AccountUsageView {
  const AccountUsageView({
    required this.accountId,
    this.revision = 0,
    required this.updatedAt,
    required this.state,
  });

  final String accountId;
  final int revision;
  final int updatedAt;
  final AccountUsageStateView state;
}

sealed class AccountUsageStateView {
  const AccountUsageStateView();
}

final class UnsupportedAccountUsageView extends AccountUsageStateView {
  const UnsupportedAccountUsageView();
}

final class MissingCredentialAccountUsageView extends AccountUsageStateView {
  const MissingCredentialAccountUsageView({required this.message});
  final String message;
}

final class ReadyAccountUsageView extends AccountUsageStateView {
  const ReadyAccountUsageView({required this.data});
  final AccountUsageDataView data;
}

final class FailedAccountUsageView extends AccountUsageStateView {
  const FailedAccountUsageView({
    required this.code,
    required this.message,
    required this.retryable,
  });
  final String code;
  final String message;
  final bool retryable;
}

sealed class AccountUsageDataView {
  const AccountUsageDataView();
}

final class DeepSeekBalanceAccountUsageView extends AccountUsageDataView {
  const DeepSeekBalanceAccountUsageView({required this.balance});
  final DeepSeekBalanceUsageView balance;
}

final class ZhipuCodingPlanAccountUsageView extends AccountUsageDataView {
  const ZhipuCodingPlanAccountUsageView({required this.codingPlan});
  final ZhipuCodingPlanUsageView codingPlan;
}

class DeepSeekBalanceUsageView {
  const DeepSeekBalanceUsageView({
    required this.isAvailable,
    required this.balances,
  });

  final bool isAvailable;
  final List<DeepSeekBalanceInfoView> balances;
}

class DeepSeekBalanceInfoView {
  const DeepSeekBalanceInfoView({
    required this.currency,
    required this.totalBalance,
    required this.grantedBalance,
    required this.toppedUpBalance,
  });

  final String currency;
  final String totalBalance;
  final String grantedBalance;
  final String toppedUpBalance;
}

class ZhipuCodingPlanUsageView {
  const ZhipuCodingPlanUsageView({this.level, required this.limits});

  final String? level;
  final List<ZhipuQuotaLimitView> limits;
}

class ZhipuQuotaLimitView {
  const ZhipuQuotaLimitView({
    required this.window,
    required this.label,
    required this.percentage,
    this.currentValue,
    this.total,
    this.remaining,
    this.nextResetAt,
    required this.usageDetails,
  });

  final String window;
  final String label;
  final double percentage;
  final double? currentValue;
  final double? total;
  final double? remaining;
  final int? nextResetAt;
  final List<ZhipuToolUsageDetailView> usageDetails;
}

class ZhipuToolUsageDetailView {
  const ZhipuToolUsageDetailView({
    required this.name,
    this.currentValue,
    this.total,
    this.percentage,
  });

  final String name;
  final double? currentValue;
  final double? total;
  final double? percentage;
}
