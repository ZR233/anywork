import 'package:anywork_client/statistics_ports.dart';

import '../../../../rust/api/studio/products/read/statistics.dart' as native;
import '../../shared/exact_numbers.dart';
import '../../shared/read_converters.dart';
import '../identity_converters.dart';
import 'read_values.dart';

PerformanceSummariesEntryPage summariesEntriesFromBridge(
  native.BridgePerformanceSummariesEntryPage value,
) => PerformanceSummariesEntryPage(
  collection: collectionRefFromBridge(value.collection),
  offset: exactU64(value.offset, 'performance summaries entries offset'),
  items: value.items.map(entityRefFromBridge).toList(growable: false),
  nextOffset: nullableU64(
    value.nextOffset,
    'performance summaries entries next offset',
  ),
);

PerformanceSummariesEntityRead summariesEntityFromBridge(
  native.BridgePerformanceSummariesEntityRead value,
) => PerformanceSummariesEntityRead(
  reference: entityRefFromBridge(value.reference),
  value: summaryReadFromBridge(value.value),
);

PerformanceHistoryEntryPage historyEntriesFromBridge(
  native.BridgePerformanceHistoryEntryPage value,
) => PerformanceHistoryEntryPage(
  collection: collectionRefFromBridge(value.collection),
  offset: exactU64(value.offset, 'performance history entries offset'),
  items: value.items.map(entityRefFromBridge).toList(growable: false),
  nextOffset: nullableU64(
    value.nextOffset,
    'performance history entries next offset',
  ),
);

PerformanceHistoryEntityRead historyEntityFromBridge(
  native.BridgePerformanceHistoryEntityRead value,
) => PerformanceHistoryEntityRead(
  reference: entityRefFromBridge(value.reference),
  value: sampleReadFromBridge(value.value),
);

PerformanceSummaryReadPage summariesPageFromBridge(
  native.BridgePerformanceSummaryReadPage value,
) => PerformanceSummaryReadPage(
  listId: exactU64(value.listId, 'performance summaries list'),
  offset: exactU64(value.offset, 'performance summaries offset'),
  total: exactU64(value.total, 'performance summaries total'),
  items: value.items.map(summaryReadFromBridge).toList(growable: false),
  nextOffset: nullableU64(
    value.nextOffset,
    'performance summaries next offset',
  ),
);

PerformanceEffortReadPage effortsPageFromBridge(
  native.BridgePerformanceEffortReadPage value,
) => PerformanceEffortReadPage(
  listId: exactU64(value.listId, 'performance efforts list'),
  offset: exactU64(value.offset, 'performance efforts offset'),
  total: exactU64(value.total, 'performance efforts total'),
  items: value.items.map(effortReadFromBridge).toList(growable: false),
  nextOffset: nullableU64(value.nextOffset, 'performance efforts next offset'),
);

PerformanceSampleReadPage samplesPageFromBridge(
  native.BridgePerformanceSampleReadPage value,
) => PerformanceSampleReadPage(
  listId: exactU64(value.listId, 'performance samples list'),
  offset: exactU64(value.offset, 'performance samples offset'),
  total: exactU64(value.total, 'performance samples total'),
  items: value.items.map(sampleReadFromBridge).toList(growable: false),
  nextOffset: nullableU64(value.nextOffset, 'performance samples next offset'),
);
