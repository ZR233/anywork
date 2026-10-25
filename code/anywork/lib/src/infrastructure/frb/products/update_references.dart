import 'package:anywork_client/updates.dart';

import '../../../rust/api/studio/products/references.dart' as native;
import '../shared/exact_numbers.dart';
import 'identity_converters.dart';

UpdatesReadRef updatesReadRefFromBridge(native.BridgeUpdatesReadRef value) =>
    UpdatesReadRef(
      entry: exactU64(value.entry, 'updates read entry'),
      revision: exactU64(value.revision, 'updates read revision'),
    );
UpdateSummaryReadRef updateSummaryRefFromBridge(
  native.BridgeUpdateSummaryReadRef value,
) => UpdateSummaryReadRef(
  entry: exactU64(value.entry, 'update summary entry'),
  revision: exactU64(value.revision, 'update summary revision'),
);
UpdateOperationReadRef updateOperationRefFromBridge(
  native.BridgeUpdateOperationReadRef value,
) => UpdateOperationReadRef(
  entry: exactU64(value.entry, 'update operation entry'),
  revision: exactU64(value.revision, 'update operation revision'),
);
UpdateErrorReadRef updateErrorRefFromBridge(
  native.BridgeUpdateErrorReadRef value,
) => UpdateErrorReadRef(
  entry: exactU64(value.entry, 'update error entry'),
  revision: exactU64(value.revision, 'update error revision'),
);
UpdateDetailsReadRef updateDetailsRefFromBridge(
  native.BridgeUpdateDetailsReadRef value,
) => UpdateDetailsReadRef(
  entry: exactU64(value.entry, 'update details entry'),
  revision: exactU64(value.revision, 'update details revision'),
);

native.BridgeUpdatesReadRef updatesReadRefToBridge(UpdatesReadRef value) =>
    native.BridgeUpdatesReadRef(
      entry: nativeU64(value.entry, 'updates read entry'),
      revision: nativeU64(value.revision, 'updates read revision'),
    );
native.BridgeUpdateSummaryReadRef updateSummaryRefToBridge(
  UpdateSummaryReadRef value,
) => native.BridgeUpdateSummaryReadRef(
  entry: nativeU64(value.entry, 'update summary entry'),
  revision: nativeU64(value.revision, 'update summary revision'),
);
native.BridgeUpdateOperationReadRef updateOperationRefToBridge(
  UpdateOperationReadRef value,
) => native.BridgeUpdateOperationReadRef(
  entry: nativeU64(value.entry, 'update operation entry'),
  revision: nativeU64(value.revision, 'update operation revision'),
);
native.BridgeUpdateErrorReadRef updateErrorRefToBridge(
  UpdateErrorReadRef value,
) => native.BridgeUpdateErrorReadRef(
  entry: nativeU64(value.entry, 'update error entry'),
  revision: nativeU64(value.revision, 'update error revision'),
);
native.BridgeUpdateDetailsReadRef updateDetailsRefToBridge(
  UpdateDetailsReadRef value,
) => native.BridgeUpdateDetailsReadRef(
  entry: nativeU64(value.entry, 'update details entry'),
  revision: nativeU64(value.revision, 'update details revision'),
);

UpdatesReadTarget updatesTargetFromBridge(
  native.BridgeUpdatesReadTarget value,
) => UpdatesReadTarget(
  origin: productOriginFromBridge(value.origin),
  reference: updatesReadRefFromBridge(value.reference),
);
