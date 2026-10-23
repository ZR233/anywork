import 'package:anywork_client/models_ports.dart';
import 'package:anywork_client/resources.dart';

import '../../../rust/api/studio/products/read/pages.dart' as native;
import '../../../rust/api/studio/products/read/primitives.dart' as primitive;
import '../shared/exact_numbers.dart';
import '../shared/read_converters.dart';
import 'identity_converters.dart';
import 'model_read_values.dart';
import 'template_read_values.dart';

ModelCatalogEntryPage modelCatalogEntriesFromBridge(native.BridgeModelCatalogEntryPage value) => ModelCatalogEntryPage(
  collection: collectionRefFromBridge(value.collection), offset: exactU64(value.offset, 'catalog entries offset'),
  items: value.items.map(entityRefFromBridge).toList(growable: false), nextOffset: nullableU64(value.nextOffset, 'catalog entries next offset'),
);
AccountTemplatesEntryPage templatesEntriesFromBridge(native.BridgeAccountTemplatesEntryPage value) => AccountTemplatesEntryPage(
  collection: collectionRefFromBridge(value.collection), offset: exactU64(value.offset, 'templates entries offset'),
  items: value.items.map(entityRefFromBridge).toList(growable: false), nextOffset: nullableU64(value.nextOffset, 'templates entries next offset'),
);
ModelCatalogEntityRead modelCatalogEntityFromBridge(native.BridgeModelCatalogEntityRead value) => ModelCatalogEntityRead(
  reference: entityRefFromBridge(value.reference), value: accountCatalogReadFromBridge(value.value),
);
AccountTemplatesEntityRead templatesEntityFromBridge(native.BridgeAccountTemplatesEntityRead value) => AccountTemplatesEntityRead(
  reference: entityRefFromBridge(value.reference), value: accountTemplateReadFromBridge(value.value),
);

AccountCatalogEntryReadPage accountCatalogPageFromBridge(native.BridgeAccountCatalogEntryReadPage value) => AccountCatalogEntryReadPage(
  listId: exactU64(value.listId, 'accounts list'), offset: exactU64(value.offset, 'accounts offset'), total: exactU64(value.total, 'accounts total'),
  items: value.items.map(accountCatalogReadFromBridge).toList(growable: false), nextOffset: nullableU64(value.nextOffset, 'accounts next offset'),
);
AccountTemplateReadPage accountTemplatePageFromBridge(native.BridgeAccountTemplateReadPage value) => AccountTemplateReadPage(
  listId: exactU64(value.listId, 'templates list'), offset: exactU64(value.offset, 'templates offset'), total: exactU64(value.total, 'templates total'),
  items: value.items.map(accountTemplateReadFromBridge).toList(growable: false), nextOffset: nullableU64(value.nextOffset, 'templates next offset'),
);
NamedModelCatalogReadPage namedCatalogPageFromBridge(native.BridgeNamedModelCatalogReadPage value) => NamedModelCatalogReadPage(
  listId: exactU64(value.listId, 'named catalogs list'), offset: exactU64(value.offset, 'named catalogs offset'), total: exactU64(value.total, 'named catalogs total'),
  items: value.items.map(namedModelCatalogReadFromBridge).toList(growable: false), nextOffset: nullableU64(value.nextOffset, 'named catalogs next offset'),
);
ModelDescriptorReadPage modelDescriptorPageFromBridge(native.BridgeModelDescriptorReadPage value) => ModelDescriptorReadPage(
  listId: exactU64(value.listId, 'models list'), offset: exactU64(value.offset, 'models offset'), total: exactU64(value.total, 'models total'),
  items: value.items.map(modelDescriptorReadFromBridge).toList(growable: false), nextOffset: nullableU64(value.nextOffset, 'models next offset'),
);
ModelTypeSupportReadPage modelTypeSupportPageFromBridge(native.BridgeModelTypeSupportReadPage value) => ModelTypeSupportReadPage(
  listId: exactU64(value.listId, 'type support list'), offset: exactU64(value.offset, 'type support offset'), total: exactU64(value.total, 'type support total'),
  items: value.items.map(modelTypeSupportReadFromBridge).toList(growable: false), nextOffset: nullableU64(value.nextOffset, 'type support next offset'),
);
ModelTypeExclusionReadPage modelExclusionPageFromBridge(native.BridgeModelTypeExclusionReadPage value) => ModelTypeExclusionReadPage(
  listId: exactU64(value.listId, 'type exclusions list'), offset: exactU64(value.offset, 'type exclusions offset'), total: exactU64(value.total, 'type exclusions total'),
  items: value.items.map(modelExclusionReadFromBridge).toList(growable: false), nextOffset: nullableU64(value.nextOffset, 'type exclusions next offset'),
);
ConnectionModeReadPage connectionModePageFromBridge(native.BridgeConnectionModeReadPage value) => ConnectionModeReadPage(
  listId: exactU64(value.listId, 'connection modes list'), offset: exactU64(value.offset, 'connection modes offset'), total: exactU64(value.total, 'connection modes total'),
  items: value.items.map(connectionModeReadFromBridge).toList(growable: false), nextOffset: nullableU64(value.nextOffset, 'connection modes next offset'),
);
ModelInputCapabilityReadPage modelInputCapabilityPageFromBridge(native.BridgeModelInputCapabilityReadPage value) => ModelInputCapabilityReadPage(
  listId: exactU64(value.listId, 'input capabilities list'), offset: exactU64(value.offset, 'input capabilities offset'), total: exactU64(value.total, 'input capabilities total'),
  items: value.items.map(modelInputCapabilityReadFromBridge).toList(growable: false), nextOffset: nullableU64(value.nextOffset, 'input capabilities next offset'),
);
ModelInputSourceReadPage modelInputSourcePageFromBridge(native.BridgeModelInputSourceReadPage value) => ModelInputSourceReadPage(
  listId: exactU64(value.listId, 'input sources list'), offset: exactU64(value.offset, 'input sources offset'), total: exactU64(value.total, 'input sources total'),
  items: value.items.map(modelInputSourceReadFromBridge).toList(growable: false), nextOffset: nullableU64(value.nextOffset, 'input sources next offset'),
);
ModelModalityReadPage modelModalityPageFromBridge(native.BridgeModelModalityReadPage value) => ModelModalityReadPage(
  listId: exactU64(value.listId, 'modalities list'), offset: exactU64(value.offset, 'modalities offset'), total: exactU64(value.total, 'modalities total'),
  items: value.items.map(modelModalityReadFromBridge).toList(growable: false), nextOffset: nullableU64(value.nextOffset, 'modalities next offset'),
);
ModelPriceTierReadPage modelPriceTierPageFromBridge(native.BridgeModelPriceTierReadPage value) => ModelPriceTierReadPage(
  listId: exactU64(value.listId, 'price tiers list'), offset: exactU64(value.offset, 'price tiers offset'), total: exactU64(value.total, 'price tiers total'),
  items: value.items.map(modelPriceTierReadFromBridge).toList(growable: false), nextOffset: nullableU64(value.nextOffset, 'price tiers next offset'),
);
TextReadPage modelStringsPageFromBridge(primitive.BridgeTextReadPage value) => TextReadPage(
  listId: exactU64(value.listId, 'strings list'), offset: exactU64(value.offset, 'strings offset'), total: exactU64(value.total, 'strings total'),
  items: value.items.map((item) => TextReadItem(value: readTextFromBridge(item.value))).toList(growable: false),
  nextOffset: nullableU64(value.nextOffset, 'strings next offset'),
);
