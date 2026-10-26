import 'package:anywork_client/account_usage_ports.dart';

import '../../../../rust/api/studio/products/read/statistics.dart' as native;
import '../../shared/exact_numbers.dart';
import '../../shared/read_converters.dart';
import 'session_costs_read_values.dart';

PurposeCostReadPage purposesPageFromBridge(
  native.BridgePurposeCostReadPage value,
) => PurposeCostReadPage(
  listId: exactU64(value.listId, 'cost purposes list'),
  offset: exactU64(value.offset, 'cost purposes offset'),
  total: exactU64(value.total, 'cost purposes total'),
  items: value.items.map(purposeCostReadFromBridge).toList(growable: false),
  nextOffset: nullableU64(value.nextOffset, 'cost purposes next offset'),
);

RuntimeCostReadPage amountsPageFromBridge(
  native.BridgeRuntimeCostReadPage value,
) => RuntimeCostReadPage(
  listId: exactU64(value.listId, 'cost amounts list'),
  offset: exactU64(value.offset, 'cost amounts offset'),
  total: exactU64(value.total, 'cost amounts total'),
  items: value.items.map(runtimeCostReadFromBridge).toList(growable: false),
  nextOffset: nullableU64(value.nextOffset, 'cost amounts next offset'),
);
