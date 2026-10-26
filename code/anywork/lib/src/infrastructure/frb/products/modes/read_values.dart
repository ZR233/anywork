import 'package:anywork_client/modes_ports.dart';

import '../../../../rust/api/studio/products/read/modes.dart' as native;
import '../../shared/exact_numbers.dart';
import '../../shared/read_converters.dart';
import '../identity_converters.dart';

ThreadModeDescriptorRead modeDescriptorFromBridge(
  native.BridgeThreadModeDescriptorRead value,
) => ThreadModeDescriptorRead(
  id: ThreadModeId(value.id),
  displayName: readTextFromBridge(value.displayName),
  description: readTextFromBridge(value.description),
  order: value.order,
  hasWorkflow: value.hasWorkflow,
  readOnly: value.readOnly,
);

ModeCatalogEntryPage modeEntriesFromBridge(
  native.BridgeModeCatalogEntryPage value,
) => ModeCatalogEntryPage(
  collection: collectionRefFromBridge(value.collection),
  offset: exactU64(value.offset, 'Mode catalog entry offset'),
  items: List.unmodifiable(value.items.map(entityRefFromBridge)),
  nextOffset: nullableU64(value.nextOffset, 'Mode catalog next entry offset'),
);

ThreadModeDescriptorReadPage modeDescriptorsFromBridge(
  native.BridgeThreadModeDescriptorReadPage value,
) => ThreadModeDescriptorReadPage(
  listId: exactU64(value.listId, 'Mode catalog list identity'),
  offset: exactU64(value.offset, 'Mode catalog list offset'),
  total: exactU64(value.total, 'Mode catalog list total'),
  items: List.unmodifiable(value.items.map(modeDescriptorFromBridge)),
  nextOffset: nullableU64(value.nextOffset, 'Mode catalog next list offset'),
);
