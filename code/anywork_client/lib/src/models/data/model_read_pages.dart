import 'package:freezed_annotation/freezed_annotation.dart';

import '../../../resources.dart';
import 'model_reads.dart';
import 'template_reads.dart';

part 'model_read_pages.freezed.dart';

@freezed
final class ModelCatalogEntryPage with _$ModelCatalogEntryPage {
  ModelCatalogEntryPage({
    required this.collection,
    required this.offset,
    required List<ProductEntityRef> items,
    required this.nextOffset,
  }) : items = List.unmodifiable(items);
  final ProductCollectionRef collection;
  final int offset;
  final List<ProductEntityRef> items;
  final int? nextOffset;
}

@Freezed(toStringOverride: false)
abstract class ModelCatalogEntityRead with _$ModelCatalogEntityRead {
  const factory ModelCatalogEntityRead({
    required ProductEntityRef reference,
    required AccountCatalogEntryRead value,
  }) = _ModelCatalogEntityRead;
}

@freezed
final class AccountTemplatesEntryPage with _$AccountTemplatesEntryPage {
  AccountTemplatesEntryPage({
    required this.collection,
    required this.offset,
    required List<ProductEntityRef> items,
    required this.nextOffset,
  }) : items = List.unmodifiable(items);
  final ProductCollectionRef collection;
  final int offset;
  final List<ProductEntityRef> items;
  final int? nextOffset;
}

@Freezed(toStringOverride: false)
abstract class AccountTemplatesEntityRead with _$AccountTemplatesEntityRead {
  const factory AccountTemplatesEntityRead({
    required ProductEntityRef reference,
    required AccountTemplateRead value,
  }) = _AccountTemplatesEntityRead;
}

@Freezed(toStringOverride: false)
final class AccountCatalogEntryReadPage with _$AccountCatalogEntryReadPage {
  AccountCatalogEntryReadPage({
    required this.listId,
    required this.offset,
    required this.total,
    required List<AccountCatalogEntryRead> items,
    required this.nextOffset,
  }) : items = List.unmodifiable(items);
  final int listId;
  final int offset;
  final int total;
  final List<AccountCatalogEntryRead> items;
  final int? nextOffset;
}

@Freezed(toStringOverride: false)
final class AccountTemplateReadPage with _$AccountTemplateReadPage {
  AccountTemplateReadPage({
    required this.listId,
    required this.offset,
    required this.total,
    required List<AccountTemplateRead> items,
    required this.nextOffset,
  }) : items = List.unmodifiable(items);
  final int listId;
  final int offset;
  final int total;
  final List<AccountTemplateRead> items;
  final int? nextOffset;
}

@Freezed(toStringOverride: false)
final class NamedModelCatalogReadPage with _$NamedModelCatalogReadPage {
  NamedModelCatalogReadPage({
    required this.listId,
    required this.offset,
    required this.total,
    required List<NamedModelCatalogReadItem> items,
    required this.nextOffset,
  }) : items = List.unmodifiable(items);
  final int listId;
  final int offset;
  final int total;
  final List<NamedModelCatalogReadItem> items;
  final int? nextOffset;
}

@Freezed(toStringOverride: false)
final class ModelDescriptorReadPage with _$ModelDescriptorReadPage {
  ModelDescriptorReadPage({
    required this.listId,
    required this.offset,
    required this.total,
    required List<ModelDescriptorRead> items,
    required this.nextOffset,
  }) : items = List.unmodifiable(items);
  final int listId;
  final int offset;
  final int total;
  final List<ModelDescriptorRead> items;
  final int? nextOffset;
}

@freezed
final class ModelTypeSupportReadPage with _$ModelTypeSupportReadPage {
  ModelTypeSupportReadPage({
    required this.listId,
    required this.offset,
    required this.total,
    required List<ModelTypeSupportRead> items,
    required this.nextOffset,
  }) : items = List.unmodifiable(items);
  final int listId;
  final int offset;
  final int total;
  final List<ModelTypeSupportRead> items;
  final int? nextOffset;
}

@freezed
final class ModelTypeExclusionReadPage with _$ModelTypeExclusionReadPage {
  ModelTypeExclusionReadPage({
    required this.listId,
    required this.offset,
    required this.total,
    required List<ModelTypeExclusionReadItem> items,
    required this.nextOffset,
  }) : items = List.unmodifiable(items);
  final int listId;
  final int offset;
  final int total;
  final List<ModelTypeExclusionReadItem> items;
  final int? nextOffset;
}

@Freezed(toStringOverride: false)
final class ConnectionModeReadPage with _$ConnectionModeReadPage {
  ConnectionModeReadPage({
    required this.listId,
    required this.offset,
    required this.total,
    required List<ConnectionModeRead> items,
    required this.nextOffset,
  }) : items = List.unmodifiable(items);
  final int listId;
  final int offset;
  final int total;
  final List<ConnectionModeRead> items;
  final int? nextOffset;
}

@freezed
final class ModelInputCapabilityReadPage with _$ModelInputCapabilityReadPage {
  ModelInputCapabilityReadPage({
    required this.listId,
    required this.offset,
    required this.total,
    required List<ModelInputCapabilityRead> items,
    required this.nextOffset,
  }) : items = List.unmodifiable(items);
  final int listId;
  final int offset;
  final int total;
  final List<ModelInputCapabilityRead> items;
  final int? nextOffset;
}

@freezed
final class ModelInputSourceReadPage with _$ModelInputSourceReadPage {
  ModelInputSourceReadPage({
    required this.listId,
    required this.offset,
    required this.total,
    required List<ModelInputSourceReadItem> items,
    required this.nextOffset,
  }) : items = List.unmodifiable(items);
  final int listId;
  final int offset;
  final int total;
  final List<ModelInputSourceReadItem> items;
  final int? nextOffset;
}

@freezed
final class ModelModalityReadPage with _$ModelModalityReadPage {
  ModelModalityReadPage({
    required this.listId,
    required this.offset,
    required this.total,
    required List<ModelModalityReadItem> items,
    required this.nextOffset,
  }) : items = List.unmodifiable(items);
  final int listId;
  final int offset;
  final int total;
  final List<ModelModalityReadItem> items;
  final int? nextOffset;
}

@Freezed(toStringOverride: false)
final class ModelPriceTierReadPage with _$ModelPriceTierReadPage {
  ModelPriceTierReadPage({
    required this.listId,
    required this.offset,
    required this.total,
    required List<ModelPriceTierRead> items,
    required this.nextOffset,
  }) : items = List.unmodifiable(items);
  final int listId;
  final int offset;
  final int total;
  final List<ModelPriceTierRead> items;
  final int? nextOffset;
}
