import 'package:anywork_client/models.dart';
import 'package:anywork_client/resources.dart';

bool supportsProfileText(ModelDescriptor model) => model.typeSupport.any((support) =>
  support.modelType == ModelType.text && support.exclusions.isEmpty);

ModelDescriptor? profileModel(List<AccountCatalogEntry> accounts, String accountId, String modelId) =>
  accounts.where((account) => account.accountId == accountId).firstOrNull?.effectiveModels
    .where((model) => model.modelId == modelId).firstOrNull;

/// Only a current exact catalog may supply display details for a paired read.
/// This never decides route presence, eligibility, ordering or effort policy.
ModelCatalogReadTarget? profileCatalogTarget(ModelsState source) {
  final origin = source.projection.stamp?.origin;
  final reference = source.projection.header?.reference;
  return source.projection.sync.phase != ResourceSyncPhase.ready || origin == null || reference == null
    ? null : ModelCatalogReadTarget(origin: origin, reference: reference);
}
