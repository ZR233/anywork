import 'package:anywork_client/models.dart';

import '../../../rust/api/studio/types/settings.dart' as native;
import '../products/model_read_scalars.dart';
import '../products/models/numeric_values.dart';
import '../shared/exact_numbers.dart';
import '../shared/read_converters.dart';

ModelDescriptor commandModelFromBridge(native.BridgeModelDescriptor value) =>
    ModelDescriptor(
      modelId: value.modelId,
      enabled: value.enabled,
      typeSupport: [
        for (final support in value.typeSupport)
          ModelTypeSupport(
            modelType: modelTypeFromBridge(support.modelType),
            exclusions: support.exclusions
                .map(modelExclusionFromBridge)
                .toList(growable: false),
          ),
      ],
      origin: modelOriginFromBridge(value.origin),
      displayName: value.displayName,
      description: value.description,
      contextWindow: nullableU64(
        value.contextWindow,
        'command model context window',
      ),
      maxContextWindow: nullableU64(
        value.maxContextWindow,
        'command model maximum context window',
      ),
      context: commandModelContextFromBridge(value.context),
      maxOutputTokens: nullableU64(
        value.maxOutputTokens,
        'command model maximum output tokens',
      ),
      transport: ModelTransportDescriptor(
        protocol: value.transport.protocol,
        connectionModes: [
          for (final mode in value.transport.connectionModes)
            ConnectionMode(id: mode.id, displayName: mode.displayName),
        ],
        defaultConnectionMode: value.transport.defaultConnectionMode,
      ),
      capabilities: ModelCapabilities(
        input: value.capabilities.input
            .map(commandModelInputFromBridge)
            .toList(growable: false),
        output: value.capabilities.output
            .map(modelModalityFromBridge)
            .toList(growable: false),
        streaming: value.capabilities.streaming,
        temperature: value.capabilities.temperature,
        reasoning: value.capabilities.reasoning,
        webSearch: value.capabilities.webSearch,
        functionCalling: value.capabilities.functionCalling,
        parallelToolCalls: value.capabilities.parallelToolCalls,
        customTools: value.capabilities.customTools,
        freeformTools: value.capabilities.freeformTools,
        instructionSnapshotOverrides:
            value.capabilities.instructionSnapshotOverrides,
        nativeContextFamily: value.capabilities.nativeContextFamily,
      ),
      reasoning: value.reasoning == null
          ? null
          : ModelReasoningDescriptor(
              parameter: value.reasoning!.parameter,
              label: value.reasoning!.label,
              defaultValue: value.reasoning!.defaultCandidate,
              candidates: value.reasoning!.candidates,
            ),
      pricing: value.pricing == null
          ? null
          : ModelPricing(
              currency: value.pricing!.currency,
              tiers: [
                for (final tier in value.pricing!.tiers)
                  ModelPriceTier(
                    label: tier.label,
                    inputPerMtok: finiteModelNumber(
                      tier.inputPerMtok,
                      'command model input price',
                    ),
                    outputPerMtok: finiteModelNumber(
                      tier.outputPerMtok,
                      'command model output price',
                    ),
                    cacheReadPerMtok: nullableFiniteModelNumber(
                      tier.cacheReadPerMtok,
                      'command model cache read price',
                    ),
                    cacheWritePerMtok: nullableFiniteModelNumber(
                      tier.cacheWritePerMtok,
                      'command model cache write price',
                    ),
                  ),
              ],
              source: value.pricing!.source,
              verifiedAt: exactI64(
                BigInt.from(value.pricing!.verifiedAt),
                'command pricing verified Unix seconds',
              ),
            ),
    );

ModelInputCapability commandModelInputFromBridge(
  native.BridgeModelInputCapability value,
) => ModelInputCapability(
  modality: modelModalityFromBridge(value.modality),
  sources: value.sources
      .map(modelInputSourceFromBridge)
      .toList(growable: false),
  maxCount: value.maxCount,
  maxBytes: nullableU64(value.maxBytes, 'command input maximum bytes'),
  maxTotalBytes: nullableU64(
    value.maxTotalBytes,
    'command input maximum total bytes',
  ),
  maxWidth: value.maxWidth,
  maxHeight: value.maxHeight,
  mediaTypes: value.mediaTypes,
);

ModelContextResolution commandModelContextFromBridge(
  native.BridgeModelContextResolution value,
) {
  // These scalar-only conversions have no read scope, deferred fields or I/O.
  final mapped = modelContextReadFromBridge(value);
  return ModelContextResolution(
    unavailable: mapped.unavailable,
    contextWindow: mapped.contextWindow,
    inputTokenLimit: mapped.inputTokenLimit,
    autoCompactLimit: mapped.autoCompactLimit,
    adjustment: mapped.adjustment,
  );
}

ModelCatalogStatus commandCatalogStatusFromBridge(
  native.BridgeModelCatalogStatusDto value,
) {
  final mapped = modelCatalogStatusReadFromBridge(value);
  return ModelCatalogStatus(
    supported: mapped.supported,
    source: mapped.source,
    probing: mapped.probing,
    lastSuccessAt: mapped.lastSuccessAt,
    checkedAt: mapped.checkedAt,
    error: mapped.error,
    cacheWarning: mapped.cacheWarning,
  );
}
