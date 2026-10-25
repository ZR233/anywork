import 'package:freezed_annotation/freezed_annotation.dart';

import '../../../resources.dart';
import 'model_values.dart';
import 'template_values.dart';

part 'models_state.freezed.dart';

@freezed
abstract class ModelCatalogReadRef with _$ModelCatalogReadRef {
  const factory ModelCatalogReadRef({
    required int entry,
    required int revision,
  }) = _ModelCatalogReadRef;
}

@freezed
abstract class ModelCatalogReadTarget with _$ModelCatalogReadTarget {
  const factory ModelCatalogReadTarget({
    required ProductReadOrigin origin,
    required ModelCatalogReadRef reference,
  }) = _ModelCatalogReadTarget;
}

@freezed
abstract class AccountTemplatesReadRef with _$AccountTemplatesReadRef {
  const factory AccountTemplatesReadRef({
    required int entry,
    required int revision,
  }) = _AccountTemplatesReadRef;
}

@freezed
abstract class AccountTemplatesReadTarget with _$AccountTemplatesReadTarget {
  const factory AccountTemplatesReadTarget({
    required ProductReadOrigin origin,
    required AccountTemplatesReadRef reference,
  }) = _AccountTemplatesReadTarget;
}

@freezed
abstract class ModelCatalogHeader with _$ModelCatalogHeader {
  const factory ModelCatalogHeader({
    required ObservedHeader source,
    required int? catalogRevision,
    required int? updatedAt,
    required ModelCatalogReadRef? reference,
  }) = _ModelCatalogHeader;
}

@freezed
abstract class AccountTemplatesHeader with _$AccountTemplatesHeader {
  const factory AccountTemplatesHeader({
    required int schemaVersion,
    required AccountTemplatesReadRef reference,
  }) = _AccountTemplatesHeader;
}

@Freezed(toStringOverride: false)
abstract class ModelsState with _$ModelsState {
  const factory ModelsState({
    required ProductProjection<ModelCatalogHeader> projection,
    required ReadValue<ProductSourceStatus, ProductSourceStatusRef>?
    sourceStatus,
    required CollectionMirror<AccountCatalogEntry> accounts,
    required ReadValue<EffectiveWebSearch, ModelCatalogReadRef>? webSearch,
    required ReadValue<EffectiveDeepSeekSearch, ModelCatalogReadRef>?
    deepSeekSearch,
  }) = _ModelsState;
}

@Freezed(toStringOverride: false)
final class TemplatesState with _$TemplatesState {
  TemplatesState({
    required this.projection,
    required this.templates,
    required ReadValue<Map<String, NamedModelCatalog>, AccountTemplatesReadRef>?
    catalogs,
    required this.catalogRevision,
  }) : catalogs = _snapshotCatalogs(catalogs);

  final ProductProjection<AccountTemplatesHeader> projection;
  final CollectionMirror<AccountTemplate> templates;
  final ReadValue<Map<String, NamedModelCatalog>, AccountTemplatesReadRef>?
  catalogs;
  final ReadValue<String, AccountTemplatesReadRef>? catalogRevision;
}

ReadValue<Map<String, NamedModelCatalog>, AccountTemplatesReadRef>?
_snapshotCatalogs(
  ReadValue<Map<String, NamedModelCatalog>, AccountTemplatesReadRef>? value,
) {
  Materialized<Map<String, NamedModelCatalog>, AccountTemplatesReadRef>?
  snapshot(
    Materialized<Map<String, NamedModelCatalog>, AccountTemplatesReadRef>?
    material,
  ) => material == null
      ? null
      : material.copyWith(
          value: Map<String, NamedModelCatalog>.unmodifiable(material.value),
        );
  return switch (value) {
    null => null,
    UnloadedReadValue<
      Map<String, NamedModelCatalog>,
      AccountTemplatesReadRef
    >() =>
      value,
    LoadingReadValue<Map<String, NamedModelCatalog>, AccountTemplatesReadRef>(
      :final origin,
      :final reference,
      :final previous,
    ) =>
      ReadValue.loading(
        origin: origin,
        reference: reference,
        previous: snapshot(previous),
      ),
    ReadyReadValue<Map<String, NamedModelCatalog>, AccountTemplatesReadRef>(
      :final current,
    ) =>
      ReadValue.ready(current: snapshot(current)!),
    FailedReadValue<Map<String, NamedModelCatalog>, AccountTemplatesReadRef>(
      :final origin,
      :final reference,
      :final error,
      :final previous,
    ) =>
      ReadValue.failed(
        origin: origin,
        reference: reference,
        error: error,
        previous: snapshot(previous),
      ),
  };
}
