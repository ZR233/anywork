import 'package:anywork_client/account_usage_ports.dart';

import '../../../../rust/api/studio/products/read/statistics.dart' as native;
import '../../shared/read_converters.dart';

/// Root-session cost read materials. They stay in this adapter because the
/// costs domain owns their scope; statistics never reads them.
SessionCostsReadHeader costsReadHeaderFromBridge(
  native.BridgeSessionCostsReadHeader value,
) => SessionCostsReadHeader(
  cost: value.cost == null ? null : sessionCostReadFromBridge(value.cost!),
);

SessionCostRead sessionCostReadFromBridge(native.BridgeSessionCostRead value) =>
    SessionCostRead(
      rootThreadId: readTextFromBridge(value.rootThreadId),
      purposeCosts: typedListFromBridge(value.purposeCosts),
      estimatedCosts: typedListFromBridge(value.estimatedCosts),
      hasUnpricedUsage: value.hasUnpricedUsage,
    );

PurposeCostRead purposeCostReadFromBridge(native.BridgePurposeCostRead value) =>
    PurposeCostRead(
      purpose: nullableReadText(value.purpose),
      estimatedCosts: typedListFromBridge(value.estimatedCosts),
      hasUnpricedUsage: value.hasUnpricedUsage,
    );

RuntimeCostRead runtimeCostReadFromBridge(native.BridgeRuntimeCostRead value) =>
    RuntimeCostRead(
      currency: readTextFromBridge(value.currency),
      amount: value.amount,
    );
