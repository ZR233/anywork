import 'package:anywork_client/operations.dart';
import 'package:anywork_client/resources.dart';

import '../../../rust/api/studio/types/command.dart' as native;
import 'exact_numbers.dart';

CommitReceipt commitReceiptFromBridge(
  native.BridgeStudioCommandReceipt value,
) => CommitReceipt(
  operationId: OperationId(value.operationId),
  disposition: switch (value.disposition) {
    native.BridgeCommandDisposition.applied => CommitDisposition.applied,
    native.BridgeCommandDisposition.noChange => CommitDisposition.noChange,
  },
  targets: List<ObservationStamp>.unmodifiable([
    for (final target in value.targets)
      ResourceStamp(
        resourceKey: target.resourceKey,
        ownerEpoch: target.ownerEpoch,
        revision: exactU64(target.revision, 'command target revision'),
      ),
  ]),
  effect: switch (value.effect) {
    native.BridgeCommandEffectPoint.immediate => EffectPoint.immediate,
    native.BridgeCommandEffectPoint.nextTurn => EffectPoint.nextTurn,
    native.BridgeCommandEffectPoint.futureSession => EffectPoint.futureSession,
  },
  effective: value.effective,
  durable: value.durable,
  requiresIdentityObservation: value.requiresIdentityObservation,
);
