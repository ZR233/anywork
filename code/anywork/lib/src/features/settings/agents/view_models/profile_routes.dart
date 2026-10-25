import 'package:anywork_client/models.dart';
import 'package:anywork_client/resources.dart';

import '../../view_models/collection_values.dart';
import '../state/profile_editor_state.dart';

bool supportsProfileText(ModelDescriptor model) =>
    model.enabled &&
    model.typeSupport.any(
      (support) =>
          support.modelType == ModelType.text && support.exclusions.isEmpty,
    );

/// Display-only lookup; these rows may contain last-known material.
ModelDescriptor? profileModel(
  List<AccountCatalogEntry> accounts,
  String accountId,
  String modelId,
) => accounts
    .where((account) => account.accountId == accountId)
    .firstOrNull
    ?.effectiveModels
    .where((model) => model.modelId == modelId)
    .firstOrNull;

/// Effort candidates and validation require current material for this exact
/// model. A pinned detail may supply it without a Ready account page row.
ModelDescriptor? currentProfileModel(
  ModelsState source,
  String accountId,
  String modelId, {
  ProfileRouteModel? detail,
}) {
  final catalog = profileCatalogTarget(source);
  if (catalog == null) return null;
  if (detail != null &&
      detail.catalog == catalog &&
      detail.model == AccountModelKey(accountId: accountId, modelId: modelId) &&
      detail.descriptor.modelId == modelId) {
    return detail.descriptor;
  }
  final account = currentCollectionRow(
    source.accounts,
    catalog.origin,
    (row) => row.accountId == accountId,
  )?.value;
  return account?.effectiveModels
      .where((model) => model.modelId == modelId)
      .firstOrNull;
}

/// Only a current exact catalog may supply display details for a paired read.
/// This never decides route presence, eligibility, ordering or effort policy.
ModelCatalogReadTarget? profileCatalogTarget(ModelsState source) {
  final origin = source.projection.stamp?.origin;
  final reference = source.projection.header?.reference;
  return source.projection.sync.phase != ResourceSyncPhase.ready ||
          origin == null ||
          reference == null
      ? null
      : ModelCatalogReadTarget(origin: origin, reference: reference);
}
