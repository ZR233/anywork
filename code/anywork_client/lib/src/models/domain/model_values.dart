import 'package:freezed_annotation/freezed_annotation.dart';

part 'model_values.freezed.dart';

/// Model IDs are only unique within an account, never by display name.
@freezed
abstract class AccountModelKey with _$AccountModelKey {
  const factory AccountModelKey({
    required String accountId,
    required String modelId,
  }) = _AccountModelKey;
}

@freezed
abstract class ModelSelection with _$ModelSelection {
  const factory ModelSelection({
    required AccountModelKey model,
    required String? effort,
  }) = _ModelSelection;
}

enum ModelType { text }

enum BillingKind { metered, subscription, unknown }

enum ModelTypeExclusion {
  textInputUnsupported,
  textOutputUnsupported,
  contextWindowUnknown,
  contextParametersInvalid,
  inputBudgetExhausted,
}

enum ModelOrigin { bundled, online, manual }

enum ModelContextUnavailable {
  windowUnknown,
  invalidParameters,
  inputBudgetExhausted,
}

enum ModelContextAdjustment { safetyLimit }

enum ModelModality { text, image, audio, video, file }

enum ModelInputSource { local, remoteUrl }

enum ModelCatalogSource { defaultSource, cached, online }

enum ModelCatalogCacheWarning { read, schema, identity, declaration }

@freezed
final class ModelDescriptor with _$ModelDescriptor {
  ModelDescriptor({
    required this.modelId,
    required this.enabled,
    required List<ModelTypeSupport> typeSupport,
    required this.origin,
    required this.displayName,
    required this.description,
    required this.contextWindow,
    required this.maxContextWindow,
    required this.context,
    required this.maxOutputTokens,
    required this.transport,
    required this.capabilities,
    required this.reasoning,
    required this.pricing,
  }) : typeSupport = List.unmodifiable(typeSupport);
  final String modelId;

  /// Rust-owned catalog qualification. Dart does not infer it from overrides.
  final bool enabled;
  final List<ModelTypeSupport> typeSupport;
  final ModelOrigin origin;
  final String displayName;
  final String? description;
  final int? contextWindow;
  final int? maxContextWindow;
  final ModelContextResolution context;
  final int? maxOutputTokens;
  final ModelTransportDescriptor transport;
  final ModelCapabilities capabilities;
  final ModelReasoningDescriptor? reasoning;
  final ModelPricing? pricing;
}

@freezed
final class ModelTypeSupport with _$ModelTypeSupport {
  ModelTypeSupport({
    required this.modelType,
    required List<ModelTypeExclusion> exclusions,
  }) : exclusions = List.unmodifiable(exclusions);
  final ModelType modelType;
  final List<ModelTypeExclusion> exclusions;
}

@freezed
abstract class ModelContextResolution with _$ModelContextResolution {
  const factory ModelContextResolution({
    required ModelContextUnavailable? unavailable,
    required int? contextWindow,
    required int? inputTokenLimit,
    required int? autoCompactLimit,
    required ModelContextAdjustment? adjustment,
  }) = _ModelContextResolution;
}

@freezed
final class ModelTransportDescriptor with _$ModelTransportDescriptor {
  ModelTransportDescriptor({
    required this.protocol,
    required List<ConnectionMode> connectionModes,
    required this.defaultConnectionMode,
  }) : connectionModes = List.unmodifiable(connectionModes);
  final String protocol;
  final List<ConnectionMode> connectionModes;
  final String defaultConnectionMode;
}

@freezed
abstract class ConnectionMode with _$ConnectionMode {
  const factory ConnectionMode({
    required String id,
    required String displayName,
  }) = _ConnectionMode;
}

@freezed
final class ModelCapabilities with _$ModelCapabilities {
  ModelCapabilities({
    required List<ModelInputCapability> input,
    required List<ModelModality> output,
    required this.streaming,
    required this.temperature,
    required this.reasoning,
    required this.webSearch,
    required this.functionCalling,
    required this.parallelToolCalls,
    required this.customTools,
    required this.freeformTools,
    required this.instructionSnapshotOverrides,
    required this.nativeContextFamily,
  }) : input = List.unmodifiable(input),
       output = List.unmodifiable(output);
  final List<ModelInputCapability> input;
  final List<ModelModality> output;
  final bool streaming;
  final bool temperature;
  final bool reasoning;
  final bool webSearch;
  final bool functionCalling;
  final bool parallelToolCalls;
  final bool customTools;
  final bool freeformTools;
  final bool instructionSnapshotOverrides;
  final String? nativeContextFamily;
}

@freezed
final class ModelInputCapability with _$ModelInputCapability {
  ModelInputCapability({
    required this.modality,
    required List<ModelInputSource> sources,
    required this.maxCount,
    required this.maxBytes,
    required this.maxTotalBytes,
    required this.maxWidth,
    required this.maxHeight,
    required List<String> mediaTypes,
  }) : sources = List.unmodifiable(sources),
       mediaTypes = List.unmodifiable(mediaTypes);
  final ModelModality modality;
  final List<ModelInputSource> sources;
  final int? maxCount;
  final int? maxBytes;
  final int? maxTotalBytes;
  final int? maxWidth;
  final int? maxHeight;
  final List<String> mediaTypes;
}

@freezed
final class ModelReasoningDescriptor with _$ModelReasoningDescriptor {
  ModelReasoningDescriptor({
    required this.parameter,
    required this.label,
    // Adapter maps the wire field `default` here, without changing the wire.
    required this.defaultValue,
    required List<String> candidates,
  }) : candidates = List.unmodifiable(candidates);
  final String parameter;
  final String label;
  final String? defaultValue;
  final List<String> candidates;
}

@freezed
final class ModelPricing with _$ModelPricing {
  ModelPricing({
    required this.currency,
    required List<ModelPriceTier> tiers,
    required this.source,
    required this.verifiedAt,
  }) : tiers = List.unmodifiable(tiers);
  final String currency;
  final List<ModelPriceTier> tiers;
  final String source;
  final int verifiedAt;
}

@freezed
abstract class ModelPriceTier with _$ModelPriceTier {
  const factory ModelPriceTier({
    required String label,
    required double inputPerMtok,
    required double outputPerMtok,
    required double? cacheReadPerMtok,
    required double? cacheWritePerMtok,
  }) = _ModelPriceTier;
}

@freezed
sealed class ModelCatalogError with _$ModelCatalogError {
  const factory ModelCatalogError.unsupported() = ModelCatalogUnsupported;
  const factory ModelCatalogError.configuration() =
      ModelCatalogConfigurationError;
  const factory ModelCatalogError.timeout() = ModelCatalogTimeout;
  const factory ModelCatalogError.transport({required int? httpStatus}) =
      ModelCatalogTransportError;
  const factory ModelCatalogError.http({required int status}) =
      ModelCatalogHttpError;
  const factory ModelCatalogError.tooLarge() = ModelCatalogTooLarge;
  const factory ModelCatalogError.protocol() = ModelCatalogProtocolError;
  const factory ModelCatalogError.cacheIdentity() = ModelCatalogCacheIdentity;
  const factory ModelCatalogError.unexpectedNotModified() =
      ModelCatalogUnexpectedNotModified;
  const factory ModelCatalogError.cacheWrite() = ModelCatalogCacheWrite;
  const factory ModelCatalogError.closing() = ModelCatalogClosing;
}

@freezed
abstract class ModelCatalogStatus with _$ModelCatalogStatus {
  const factory ModelCatalogStatus({
    required bool supported,
    required ModelCatalogSource source,
    required bool probing,
    required int? lastSuccessAt,
    required int? checkedAt,
    required ModelCatalogError? error,
    required ModelCatalogCacheWarning? cacheWarning,
  }) = _ModelCatalogStatus;
}

@freezed
final class AccountCatalogEntry with _$AccountCatalogEntry {
  AccountCatalogEntry({
    required this.accountId,
    required this.credentialRequired,
    required this.capabilitySource,
    required this.hostedWebSearch,
    required this.hostedWebSearchDialect,
    required this.standaloneWebSearch,
    required this.promptCacheDialect,
    required this.responsesProgrammaticToolCalling,
    required this.defaultModelId,
    required List<ModelDescriptor> effectiveModels,
    required this.modelCatalog,
  }) : effectiveModels = List.unmodifiable(effectiveModels);
  final String accountId;
  final bool credentialRequired;
  final String capabilitySource;
  final bool hostedWebSearch;
  final String hostedWebSearchDialect;
  final String? standaloneWebSearch;
  final String promptCacheDialect;
  final bool responsesProgrammaticToolCalling;
  final String defaultModelId;
  final List<ModelDescriptor> effectiveModels;
  final ModelCatalogStatus modelCatalog;
}

@freezed
abstract class EffectiveWebSearch with _$EffectiveWebSearch {
  const factory EffectiveWebSearch({
    required String effectiveMode,
    required String availability,
    required String? accountId,
    required String? modelId,
  }) = _EffectiveWebSearch;
}

@freezed
abstract class EffectiveDeepSeekSearch with _$EffectiveDeepSeekSearch {
  const factory EffectiveDeepSeekSearch({
    required bool effectiveEnabled,
    required bool effectiveFetchEnabled,
    required String availability,
    required String? accountId,
  }) = _EffectiveDeepSeekSearch;
}

@freezed
final class ModelsValue with _$ModelsValue {
  ModelsValue({
    required List<AccountCatalogEntry> accounts,
    required this.webSearch,
    required this.deepseekWebSearch,
  }) : accounts = List.unmodifiable(accounts);
  final List<AccountCatalogEntry> accounts;
  final EffectiveWebSearch webSearch;
  final EffectiveDeepSeekSearch deepseekWebSearch;
}
