import 'package:freezed_annotation/freezed_annotation.dart';

import '../../../resources.dart';
import '../domain/model_values.dart';

part 'model_reads.freezed.dart';

@Freezed(toStringOverride: false)
abstract class ModelDescriptorRead with _$ModelDescriptorRead {
  const factory ModelDescriptorRead({
    required ReadText modelId,
    required bool enabled,
    required TypedListRef typeSupport,
    required ModelOrigin origin,
    required ReadText displayName,
    required ReadText? description,
    required int? contextWindow,
    required int? maxContextWindow,
    required ModelContextResolutionRead context,
    required int? maxOutputTokens,
    required ModelTransportDescriptorRead transport,
    required ModelCapabilitiesRead capabilities,
    required ModelReasoningDescriptorRead? reasoning,
    required ModelPricingRead? pricing,
  }) = _ModelDescriptorRead;
}

@freezed
abstract class ModelTypeSupportRead with _$ModelTypeSupportRead {
  const factory ModelTypeSupportRead({
    required ModelType modelType,
    required TypedListRef exclusions,
  }) = _ModelTypeSupportRead;
}

@freezed
abstract class ModelTypeExclusionReadItem with _$ModelTypeExclusionReadItem {
  const factory ModelTypeExclusionReadItem({
    required ModelTypeExclusion value,
  }) = _ModelTypeExclusionReadItem;
}

@freezed
abstract class ModelContextResolutionRead with _$ModelContextResolutionRead {
  const factory ModelContextResolutionRead({
    required ModelContextUnavailable? unavailable,
    required int? contextWindow,
    required int? inputTokenLimit,
    required int? autoCompactLimit,
    required ModelContextAdjustment? adjustment,
  }) = _ModelContextResolutionRead;
}

@Freezed(toStringOverride: false)
abstract class ModelTransportDescriptorRead
    with _$ModelTransportDescriptorRead {
  const factory ModelTransportDescriptorRead({
    required ReadText protocol,
    required TypedListRef connectionModes,
    required ReadText defaultConnectionMode,
  }) = _ModelTransportDescriptorRead;
}

@Freezed(toStringOverride: false)
abstract class ConnectionModeRead with _$ConnectionModeRead {
  const factory ConnectionModeRead({
    required ReadText id,
    required ReadText displayName,
  }) = _ConnectionModeRead;
}

@Freezed(toStringOverride: false)
abstract class ModelCapabilitiesRead with _$ModelCapabilitiesRead {
  const factory ModelCapabilitiesRead({
    required TypedListRef input,
    required TypedListRef output,
    required bool streaming,
    required bool temperature,
    required bool reasoning,
    required bool webSearch,
    required bool functionCalling,
    required bool parallelToolCalls,
    required bool customTools,
    required bool freeformTools,
    required bool instructionSnapshotOverrides,
    required ReadText? nativeContextFamily,
  }) = _ModelCapabilitiesRead;
}

@freezed
abstract class ModelInputCapabilityRead with _$ModelInputCapabilityRead {
  const factory ModelInputCapabilityRead({
    required ModelModality modality,
    required TypedListRef sources,
    required int? maxCount,
    required int? maxBytes,
    required int? maxTotalBytes,
    required int? maxWidth,
    required int? maxHeight,
    required TypedListRef mediaTypes,
  }) = _ModelInputCapabilityRead;
}

@freezed
abstract class ModelInputSourceReadItem with _$ModelInputSourceReadItem {
  const factory ModelInputSourceReadItem({required ModelInputSource value}) =
      _ModelInputSourceReadItem;
}

@freezed
abstract class ModelModalityReadItem with _$ModelModalityReadItem {
  const factory ModelModalityReadItem({required ModelModality value}) =
      _ModelModalityReadItem;
}

@Freezed(toStringOverride: false)
abstract class ModelReasoningDescriptorRead
    with _$ModelReasoningDescriptorRead {
  const factory ModelReasoningDescriptorRead({
    required ReadText parameter,
    required ReadText label,
    required ReadText? defaultValue,
    required TypedListRef candidates,
  }) = _ModelReasoningDescriptorRead;
}

@Freezed(toStringOverride: false)
abstract class ModelPricingRead with _$ModelPricingRead {
  const factory ModelPricingRead({
    required ReadText currency,
    required TypedListRef tiers,
    required ReadText source,
    required int verifiedAt,
  }) = _ModelPricingRead;
}

@Freezed(toStringOverride: false)
abstract class ModelPriceTierRead with _$ModelPriceTierRead {
  const factory ModelPriceTierRead({
    required ReadText label,
    required double inputPerMtok,
    required double outputPerMtok,
    required double? cacheReadPerMtok,
    required double? cacheWritePerMtok,
  }) = _ModelPriceTierRead;
}

@freezed
abstract class ModelCatalogStatusRead with _$ModelCatalogStatusRead {
  const factory ModelCatalogStatusRead({
    required bool supported,
    required ModelCatalogSource source,
    required bool probing,
    required int? lastSuccessAt,
    required int? checkedAt,
    required ModelCatalogError? error,
    required ModelCatalogCacheWarning? cacheWarning,
  }) = _ModelCatalogStatusRead;
}

@Freezed(toStringOverride: false)
abstract class AccountCatalogEntryRead with _$AccountCatalogEntryRead {
  const factory AccountCatalogEntryRead({
    required ReadText accountId,
    required bool credentialRequired,
    required ReadText capabilitySource,
    required bool hostedWebSearch,
    required ReadText hostedWebSearchDialect,
    required ReadText? standaloneWebSearch,
    required ReadText promptCacheDialect,
    required bool responsesProgrammaticToolCalling,
    required ReadText defaultModelId,
    required TypedListRef effectiveModels,
    required ModelCatalogStatusRead modelCatalog,
  }) = _AccountCatalogEntryRead;
}

@Freezed(toStringOverride: false)
abstract class EffectiveWebSearchRead with _$EffectiveWebSearchRead {
  const factory EffectiveWebSearchRead({
    required ReadText effectiveMode,
    required ReadText availability,
    required ReadText? accountId,
    required ReadText? modelId,
  }) = _EffectiveWebSearchRead;
}

@Freezed(toStringOverride: false)
abstract class EffectiveDeepSeekSearchRead with _$EffectiveDeepSeekSearchRead {
  const factory EffectiveDeepSeekSearchRead({
    required bool effectiveEnabled,
    required bool effectiveFetchEnabled,
    required ReadText availability,
    required ReadText? accountId,
  }) = _EffectiveDeepSeekSearchRead;
}

@Freezed(toStringOverride: false)
abstract class ModelCatalogReadHeader with _$ModelCatalogReadHeader {
  const factory ModelCatalogReadHeader({
    required TypedListRef accounts,
    required EffectiveWebSearchRead webSearch,
    required EffectiveDeepSeekSearchRead deepseekWebSearch,
  }) = _ModelCatalogReadHeader;
}
