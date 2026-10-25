import 'package:anywork_client/models_ports.dart';

import '../../../rust/api/studio/products/read/model_values.dart' as native;
import '../../../rust/api/studio/products/read/primitives.dart' as primitive;
import '../shared/exact_numbers.dart';
import '../shared/read_converters.dart';
import 'model_read_scalars.dart';
import 'models/numeric_values.dart';

ModelDescriptorRead modelDescriptorReadFromBridge(
  native.BridgeModelDescriptorRead value,
) => ModelDescriptorRead(
  modelId: readTextFromBridge(value.modelId),
  enabled: value.enabled,
  typeSupport: typedListFromBridge(value.typeSupport),
  origin: modelOriginFromBridge(value.origin),
  displayName: readTextFromBridge(value.displayName),
  description: nullableReadText(value.description),
  contextWindow: nullableU64(value.contextWindow, 'model context window'),
  maxContextWindow: nullableU64(
    value.maxContextWindow,
    'model max context window',
  ),
  context: modelContextReadFromBridge(value.context),
  maxOutputTokens: nullableU64(
    value.maxOutputTokens,
    'model max output tokens',
  ),
  transport: modelTransportReadFromBridge(value.transport),
  capabilities: modelCapabilitiesReadFromBridge(value.capabilities),
  reasoning: value.reasoning == null
      ? null
      : modelReasoningReadFromBridge(value.reasoning!),
  pricing: value.pricing == null
      ? null
      : modelPricingReadFromBridge(value.pricing!),
);

ModelTypeSupportRead modelTypeSupportReadFromBridge(
  native.BridgeModelTypeSupportRead value,
) => ModelTypeSupportRead(
  modelType: modelTypeFromBridge(value.modelType),
  exclusions: typedListFromBridge(value.exclusions),
);
ModelTypeExclusionReadItem modelExclusionReadFromBridge(
  native.BridgeModelTypeExclusionReadItem value,
) => ModelTypeExclusionReadItem(value: modelExclusionFromBridge(value.value));

ModelTransportDescriptorRead modelTransportReadFromBridge(
  native.BridgeModelTransportDescriptorRead value,
) => ModelTransportDescriptorRead(
  protocol: readTextFromBridge(value.protocol),
  connectionModes: typedListFromBridge(value.connectionModes),
  defaultConnectionMode: readTextFromBridge(value.defaultConnectionMode),
);
ConnectionModeRead connectionModeReadFromBridge(
  native.BridgeConnectionModeRead value,
) => ConnectionModeRead(
  id: readTextFromBridge(value.id),
  displayName: readTextFromBridge(value.displayName),
);

ModelCapabilitiesRead modelCapabilitiesReadFromBridge(
  native.BridgeModelCapabilitiesRead value,
) => ModelCapabilitiesRead(
  input: typedListFromBridge(value.input),
  output: typedListFromBridge(value.output),
  streaming: value.streaming,
  temperature: value.temperature,
  reasoning: value.reasoning,
  webSearch: value.webSearch,
  functionCalling: value.functionCalling,
  parallelToolCalls: value.parallelToolCalls,
  customTools: value.customTools,
  freeformTools: value.freeformTools,
  instructionSnapshotOverrides: value.instructionSnapshotOverrides,
  nativeContextFamily: nullableReadText(value.nativeContextFamily),
);

ModelInputCapabilityRead modelInputCapabilityReadFromBridge(
  native.BridgeModelInputCapabilityRead value,
) => ModelInputCapabilityRead(
  modality: modelModalityFromBridge(value.modality),
  sources: typedListFromBridge(value.sources),
  maxCount: value.maxCount,
  maxBytes: nullableU64(value.maxBytes, 'model input max bytes'),
  maxTotalBytes: nullableU64(
    value.maxTotalBytes,
    'model input max total bytes',
  ),
  maxWidth: value.maxWidth,
  maxHeight: value.maxHeight,
  mediaTypes: typedListFromBridge(value.mediaTypes),
);
ModelInputSourceReadItem modelInputSourceReadFromBridge(
  native.BridgeModelInputSourceReadItem value,
) => ModelInputSourceReadItem(value: modelInputSourceFromBridge(value.value));
ModelModalityReadItem modelModalityReadFromBridge(
  native.BridgeModelModalityReadItem value,
) => ModelModalityReadItem(value: modelModalityFromBridge(value.value));

ModelReasoningDescriptorRead modelReasoningReadFromBridge(
  native.BridgeModelReasoningDescriptorRead value,
) => ModelReasoningDescriptorRead(
  parameter: readTextFromBridge(value.parameter),
  label: readTextFromBridge(value.label),
  defaultValue: nullableReadText(value.default_),
  candidates: typedListFromBridge(value.candidates),
);
ModelPricingRead modelPricingReadFromBridge(
  native.BridgeModelPricingRead value,
) => ModelPricingRead(
  currency: readTextFromBridge(value.currency),
  tiers: typedListFromBridge(value.tiers),
  source: readTextFromBridge(value.source),
  verifiedAt: exactI64(
    BigInt.from(value.verifiedAt),
    'model pricing verified Unix seconds',
  ),
);
ModelPriceTierRead modelPriceTierReadFromBridge(
  native.BridgeModelPriceTierRead value,
) => ModelPriceTierRead(
  label: readTextFromBridge(value.label),
  inputPerMtok: finiteModelNumber(
    value.inputPerMtok,
    'model input price per Mtok',
  ),
  outputPerMtok: finiteModelNumber(
    value.outputPerMtok,
    'model output price per Mtok',
  ),
  cacheReadPerMtok: nullableFiniteModelNumber(
    value.cacheReadPerMtok,
    'model cache read price per Mtok',
  ),
  cacheWritePerMtok: nullableFiniteModelNumber(
    value.cacheWritePerMtok,
    'model cache write price per Mtok',
  ),
);

AccountCatalogEntryRead accountCatalogReadFromBridge(
  native.BridgeAccountCatalogEntryRead value,
) => AccountCatalogEntryRead(
  accountId: readTextFromBridge(value.accountId),
  credentialRequired: value.credentialRequired,
  capabilitySource: readTextFromBridge(value.capabilitySource),
  hostedWebSearch: value.hostedWebSearch,
  hostedWebSearchDialect: readTextFromBridge(value.hostedWebSearchDialect),
  standaloneWebSearch: nullableReadText(value.standaloneWebSearch),
  promptCacheDialect: readTextFromBridge(value.promptCacheDialect),
  responsesProgrammaticToolCalling: value.responsesProgrammaticToolCalling,
  defaultModelId: readTextFromBridge(value.defaultModelId),
  effectiveModels: typedListFromBridge(value.effectiveModels),
  modelCatalog: modelCatalogStatusReadFromBridge(value.modelCatalog),
);

ModelCatalogReadHeader modelCatalogReadHeaderFromBridge(
  native.BridgeModelCatalogReadHeader value,
) => ModelCatalogReadHeader(
  accounts: typedListFromBridge(value.accounts),
  webSearch: EffectiveWebSearchRead(
    effectiveMode: readTextFromBridge(value.webSearch.effectiveMode),
    availability: readTextFromBridge(value.webSearch.availability),
    accountId: nullableReadText(value.webSearch.accountId),
    modelId: nullableReadText(value.webSearch.modelId),
  ),
  deepseekWebSearch: EffectiveDeepSeekSearchRead(
    effectiveEnabled: value.deepseekWebSearch.effectiveEnabled,
    effectiveFetchEnabled: value.deepseekWebSearch.effectiveFetchEnabled,
    availability: readTextFromBridge(value.deepseekWebSearch.availability),
    accountId: nullableReadText(value.deepseekWebSearch.accountId),
  ),
);

ModelSelection modelSelectionFromBridge(primitive.BridgeModelSelection value) =>
    ModelSelection(
      model: AccountModelKey(
        accountId: value.model.accountId,
        modelId: value.model.modelId,
      ),
      effort: value.effort,
    );
