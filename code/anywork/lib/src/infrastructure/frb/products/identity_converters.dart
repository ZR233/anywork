import 'package:anywork_client/resources.dart';

import '../../../rust/api/studio/products/identity.dart' as native;
import '../shared/adapter_failure.dart';
import '../shared/exact_numbers.dart';

ProductResource productResourceFromBridge(
  native.BridgeProductResource value,
) => switch (value) {
  native.BridgeProductResource.projectDirectory =>
    ProductResource.projectDirectory,
  native.BridgeProductResource.threadDirectory =>
    ProductResource.threadDirectory,
  native.BridgeProductResource.agentDirectory => ProductResource.agentDirectory,
  native.BridgeProductResource.configuration => ProductResource.configuration,
  native.BridgeProductResource.modelCatalog => ProductResource.modelCatalog,
  native.BridgeProductResource.accountTemplates =>
    ProductResource.accountTemplates,
  native.BridgeProductResource.agentProfiles => ProductResource.agentProfiles,
  native.BridgeProductResource.modeCatalog => ProductResource.modeCatalog,
  native.BridgeProductResource.accountUsage => ProductResource.accountUsage,
  native.BridgeProductResource.performanceSummaries =>
    ProductResource.performanceSummaries,
  native.BridgeProductResource.performanceHistory =>
    ProductResource.performanceHistory,
  native.BridgeProductResource.sessionCosts => ProductResource.sessionCosts,
  native.BridgeProductResource.recovery => ProductResource.recovery,
  native.BridgeProductResource.mcp => ProductResource.mcp,
  native.BridgeProductResource.lsp => ProductResource.lsp,
  native.BridgeProductResource.skills => ProductResource.skills,
  native.BridgeProductResource.persistence => ProductResource.persistence,
  native.BridgeProductResource.persistenceQueue =>
    ProductResource.persistenceQueue,
  native.BridgeProductResource.updates => ProductResource.updates,
  native.BridgeProductResource.bots => ProductResource.bots,
  native.BridgeProductResource.acpAuth => ProductResource.acpAuth,
  native.BridgeProductResource.acpInstall => ProductResource.acpInstall,
};

ProductFeedIdentity productFeedIdentityFromBridge(
  native.BridgeProductFeedIdentity value,
) => ProductFeedIdentity(
  feedId: value.feedId,
  ownerEpoch: value.ownerEpoch,
  incarnation: exactU64(value.incarnation, 'product incarnation'),
  resource: productResourceFromBridge(value.resource),
);

ProductProjectionStamp productStampFromBridge(
  native.BridgeProductProjectionStamp value,
) => ProductProjectionStamp(
  ownerEpoch: value.ownerEpoch,
  incarnation: exactU64(value.incarnation, 'product incarnation'),
  revision: exactU64(value.revision, 'product projection revision'),
);

ProductReadOrigin productOriginFromBridge(
  native.BridgeProductReadOrigin value,
) => ProductReadOrigin(
  ownerEpoch: value.ownerEpoch,
  incarnation: exactU64(value.incarnation, 'product read incarnation'),
);

native.BridgeProductReadOrigin productOriginToBridge(ProductReadOrigin value) =>
    native.BridgeProductReadOrigin(
      ownerEpoch: value.ownerEpoch,
      incarnation: nativeU64(value.incarnation, 'product read incarnation'),
    );

ProductReadScopeIdentity productScopeFromBridge(
  native.BridgeProductReadScopeIdentity value,
) => ProductReadScopeIdentity(
  scopeId: value.scopeId,
  ownerEpoch: value.ownerEpoch,
  incarnation: exactU64(value.incarnation, 'product read incarnation'),
  version: switch (value.version) {
    native.BridgeProductReadVersion_Value(:final entry, :final revision) =>
      ProductReadVersion.value(
        entry: exactU64(entry, 'product value entry'),
        revision: exactU64(revision, 'product value revision'),
      ),
    native.BridgeProductReadVersion_SourceStatus(
      :final entry,
      :final revision,
    ) =>
      ProductReadVersion.sourceStatus(
        entry: exactU64(entry, 'product source entry'),
        revision: exactU64(revision, 'product source revision'),
      ),
  },
);

/// Version equality includes its value/source-status discriminator. Same
/// numeric entry/revision in another owner/scope is never sufficient.
void requireProductReadScope(
  ProductReadScopeIdentity actual,
  ProductReadScopeIdentity expected,
) {
  if (actual.scopeId.isEmpty ||
      actual.scopeId != expected.scopeId ||
      actual.ownerEpoch != expected.ownerEpoch ||
      actual.incarnation != expected.incarnation ||
      actual.version != expected.version) {
    throw adapterProtocol('product-read-scope-identity');
  }
}

ProductSourceStatusRef sourceStatusRefFromBridge(
  native.BridgeProductSourceStatusRef value,
) => ProductSourceStatusRef(
  entry: exactU64(value.entry, 'source status entry'),
  revision: exactU64(value.revision, 'source status revision'),
);
ProductEntityRef entityRefFromBridge(native.BridgeProductEntityRef value) =>
    ProductEntityRef(
      entry: exactU64(value.entry, 'product entity entry'),
      revision: exactU64(value.revision, 'product entity revision'),
    );
ProductCollectionRef collectionRefFromBridge(
  native.BridgeProductCollectionRef value,
) => ProductCollectionRef(
  entry: exactU64(value.entry, 'product collection entry'),
  revision: exactU64(value.revision, 'product collection revision'),
  total: exactU64(value.total, 'product collection total'),
);

ProductResyncReason productResyncFromBridge(
  native.BridgeProductResyncReason value,
) => switch (value) {
  native.BridgeProductResyncReason.sourceLagged =>
    ProductResyncReason.sourceLagged,
  native.BridgeProductResyncReason.reliableQueueFull =>
    ProductResyncReason.reliableQueueFull,
  native.BridgeProductResyncReason.revisionGap =>
    ProductResyncReason.revisionGap,
};
ProductFeedCloseReason productClosedFromBridge(
  native.BridgeProductFeedCloseReason value,
) => switch (value) {
  native.BridgeProductFeedCloseReason.requested =>
    ProductFeedCloseReason.requested,
  native.BridgeProductFeedCloseReason.ownerReplaced =>
    ProductFeedCloseReason.ownerReplaced,
  native.BridgeProductFeedCloseReason.runtimeStopped =>
    ProductFeedCloseReason.runtimeStopped,
};
