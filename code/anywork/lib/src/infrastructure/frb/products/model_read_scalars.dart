import 'package:anywork_client/models_ports.dart';

import '../../../rust/api/studio/types/settings.dart' as native;
import '../shared/read_converters.dart';

ModelOrigin modelOriginFromBridge(native.BridgeModelOrigin value) => switch (value) {
  native.BridgeModelOrigin.bundled => ModelOrigin.bundled,
  native.BridgeModelOrigin.online => ModelOrigin.online,
  native.BridgeModelOrigin.manual => ModelOrigin.manual,
};

ModelType modelTypeFromBridge(native.BridgeModelType value) => switch (value) {
  native.BridgeModelType.text => ModelType.text,
};

ModelTypeExclusion modelExclusionFromBridge(native.BridgeModelTypeExclusion value) => switch (value) {
  native.BridgeModelTypeExclusion.textInputUnsupported => ModelTypeExclusion.textInputUnsupported,
  native.BridgeModelTypeExclusion.textOutputUnsupported => ModelTypeExclusion.textOutputUnsupported,
  native.BridgeModelTypeExclusion.contextWindowUnknown => ModelTypeExclusion.contextWindowUnknown,
  native.BridgeModelTypeExclusion.contextParametersInvalid => ModelTypeExclusion.contextParametersInvalid,
  native.BridgeModelTypeExclusion.inputBudgetExhausted => ModelTypeExclusion.inputBudgetExhausted,
};

ModelModality modelModalityFromBridge(native.BridgeModelModality value) => switch (value) {
  native.BridgeModelModality.text => ModelModality.text,
  native.BridgeModelModality.image => ModelModality.image,
  native.BridgeModelModality.audio => ModelModality.audio,
  native.BridgeModelModality.video => ModelModality.video,
  native.BridgeModelModality.file => ModelModality.file,
};

ModelInputSource modelInputSourceFromBridge(native.BridgeModelInputSource value) => switch (value) {
  native.BridgeModelInputSource.local => ModelInputSource.local,
  native.BridgeModelInputSource.remoteUrl => ModelInputSource.remoteUrl,
};

ModelContextResolutionRead modelContextReadFromBridge(native.BridgeModelContextResolution value) => ModelContextResolutionRead(
  unavailable: switch (value.unavailable) {
    null => null,
    native.BridgeModelContextUnavailable.windowUnknown => ModelContextUnavailable.windowUnknown,
    native.BridgeModelContextUnavailable.invalidParameters => ModelContextUnavailable.invalidParameters,
    native.BridgeModelContextUnavailable.inputBudgetExhausted => ModelContextUnavailable.inputBudgetExhausted,
  },
  contextWindow: nullableU64(value.contextWindow, 'model context window'),
  inputTokenLimit: nullableU64(value.inputTokenLimit, 'model input token limit'),
  autoCompactLimit: nullableU64(value.autoCompactLimit, 'model auto compact limit'),
  adjustment: switch (value.adjustment) {
    null => null,
    native.BridgeModelContextAdjustment.safetyLimit => ModelContextAdjustment.safetyLimit,
  },
);

ModelCatalogError modelCatalogErrorFromBridge(native.BridgeModelCatalogError value) => switch (value) {
  native.BridgeModelCatalogError_Unsupported() => const ModelCatalogError.unsupported(),
  native.BridgeModelCatalogError_Configuration() => const ModelCatalogError.configuration(),
  native.BridgeModelCatalogError_Timeout() => const ModelCatalogError.timeout(),
  native.BridgeModelCatalogError_Transport(:final httpStatus) => ModelCatalogError.transport(httpStatus: httpStatus),
  native.BridgeModelCatalogError_Http(:final status) => ModelCatalogError.http(status: status),
  native.BridgeModelCatalogError_TooLarge() => const ModelCatalogError.tooLarge(),
  native.BridgeModelCatalogError_Protocol() => const ModelCatalogError.protocol(),
  native.BridgeModelCatalogError_CacheIdentity() => const ModelCatalogError.cacheIdentity(),
  native.BridgeModelCatalogError_UnexpectedNotModified() => const ModelCatalogError.unexpectedNotModified(),
  native.BridgeModelCatalogError_CacheWrite() => const ModelCatalogError.cacheWrite(),
  native.BridgeModelCatalogError_Closing() => const ModelCatalogError.closing(),
};

ModelCatalogStatusRead modelCatalogStatusReadFromBridge(native.BridgeModelCatalogStatusDto value) => ModelCatalogStatusRead(
  supported: value.supported,
  source: switch (value.source) {
    native.BridgeModelCatalogSource.default_ => ModelCatalogSource.defaultSource,
    native.BridgeModelCatalogSource.cached => ModelCatalogSource.cached,
    native.BridgeModelCatalogSource.online => ModelCatalogSource.online,
  },
  probing: value.probing,
  lastSuccessAt: nullableI64(value.lastSuccessAt, 'catalog last success Unix seconds'),
  checkedAt: nullableI64(value.checkedAt, 'catalog checked Unix seconds'),
  error: value.error == null ? null : modelCatalogErrorFromBridge(value.error!),
  cacheWarning: switch (value.cacheWarning) {
    null => null,
    native.BridgeModelCatalogCacheWarning.read => ModelCatalogCacheWarning.read,
    native.BridgeModelCatalogCacheWarning.schema => ModelCatalogCacheWarning.schema,
    native.BridgeModelCatalogCacheWarning.identity => ModelCatalogCacheWarning.identity,
    native.BridgeModelCatalogCacheWarning.declaration => ModelCatalogCacheWarning.declaration,
  },
);
