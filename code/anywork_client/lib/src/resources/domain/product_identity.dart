import 'package:freezed_annotation/freezed_annotation.dart';

part 'product_identity.freezed.dart';

enum ProductResource {
  projectDirectory,
  threadDirectory,
  agentDirectory,
  configuration,
  modelCatalog,
  accountTemplates,
  agentProfiles,
  modeCatalog,
  accountUsage,
  performanceSummaries,
  performanceHistory,
  sessionCosts,
  recovery,
  mcp,
  lsp,
  skills,
  persistence,
  persistenceQueue,
  updates,
  bots,
}

enum ProductResyncReason { sourceLagged, reliableQueueFull, revisionGap }

enum ProductFeedCloseReason { requested, ownerReplaced, runtimeStopped }

@freezed
abstract class ProductFeedIdentity with _$ProductFeedIdentity {
  const factory ProductFeedIdentity({
    required String feedId,
    required String ownerEpoch,
    required int incarnation,
    required ProductResource resource,
  }) = _ProductFeedIdentity;
}

@freezed
abstract class ProductProjectionStamp with _$ProductProjectionStamp {
  const ProductProjectionStamp._();

  const factory ProductProjectionStamp({
    required String ownerEpoch,
    required int incarnation,
    required int revision,
  }) = _ProductProjectionStamp;

  ProductReadOrigin get origin =>
      ProductReadOrigin(ownerEpoch: ownerEpoch, incarnation: incarnation);
}

@freezed
abstract class ProductReadOrigin with _$ProductReadOrigin {
  const factory ProductReadOrigin({
    required String ownerEpoch,
    required int incarnation,
  }) = _ProductReadOrigin;
}

@freezed
sealed class ProductReadVersion with _$ProductReadVersion {
  const factory ProductReadVersion.value({
    required int entry,
    required int revision,
  }) = ProductValueReadVersion;
  const factory ProductReadVersion.sourceStatus({
    required int entry,
    required int revision,
  }) = ProductSourceStatusReadVersion;
}

@freezed
abstract class ProductReadScopeIdentity with _$ProductReadScopeIdentity {
  const factory ProductReadScopeIdentity({
    required String scopeId,
    required String ownerEpoch,
    required int incarnation,
    required ProductReadVersion version,
  }) = _ProductReadScopeIdentity;
}

@freezed
abstract class ProductSourceStatusRef with _$ProductSourceStatusRef {
  const factory ProductSourceStatusRef({
    required int entry,
    required int revision,
  }) = _ProductSourceStatusRef;
}

@freezed
abstract class ProductEntityRef with _$ProductEntityRef {
  const factory ProductEntityRef({required int entry, required int revision}) =
      _ProductEntityRef;
}

@freezed
abstract class ProductCollectionRef with _$ProductCollectionRef {
  const factory ProductCollectionRef({
    required int entry,
    required int revision,
    required int total,
  }) = _ProductCollectionRef;
}
