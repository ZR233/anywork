import 'package:anywork_client/bots_ports.dart';

import '../../../../rust/api/studio/products/read/bots.dart' as feed;
import '../../../../rust/api/studio/types/bots.dart' as native;
import '../../shared/bridge_failure.dart';
import '../../shared/exact_numbers.dart';
import '../identity_converters.dart';
import '../source_converters.dart';
import 'bot_values.dart';
import 'registration_values.dart';

BotsStateSnapshot botsStateFromBridge(native.BridgeBotsStateSnapshot value) =>
    BotsStateSnapshot(
      revision: exactU64(value.revision, 'bots domain revision'),
      updatedAt: exactI64(
        BigInt.from(value.updatedAt),
        'bots updated Unix seconds',
      ),
      bots: List.unmodifiable(value.bots.map(botSnapshotFromBridge)),
      registration: value.registration == null
          ? null
          : botRegistrationFromBridge(value.registration!),
      pendingCredentialOperations: List.unmodifiable([
        for (final pending in value.pendingCredentialOperations)
          BotPendingCredentialOperation(
            botId: pending.botId,
            credentialOperation: botCredentialOperationFromBridge(
              pending.credentialOperation,
            ),
            diagnostic: pending.diagnostic == null
                ? null
                : botDiagnosticFromBridge(pending.diagnostic!),
          ),
      ]),
    );

BotsHeader botsHeaderFromBridge(feed.BridgeBotsHeader value) => BotsHeader(
  source: observedHeaderFromBridge(value.source),
  botsRevision: value.botsRevision == null
      ? null
      : exactU64(value.botsRevision!, 'bots header revision'),
  updatedAt: value.updatedAt == null
      ? null
      : exactI64(
          BigInt.from(value.updatedAt!),
          'bots header updated Unix seconds',
        ),
);

BotsEvent botsEventFromBridge(feed.BridgeBotsEvent value) => switch (value) {
  feed.BridgeBotsEvent_Baseline(
    :final identity,
    :final stamp,
    :final header,
    :final state,
  ) =>
    BotsEvent.baseline(
      identity: productFeedIdentityFromBridge(identity),
      stamp: productStampFromBridge(stamp),
      header: botsHeaderFromBridge(header),
      state: state == null ? null : botsStateFromBridge(state),
    ),
  feed.BridgeBotsEvent_StateChanged(
    :final stamp,
    :final baseRevision,
    :final header,
    :final state,
  ) =>
    BotsEvent.stateChanged(
      stamp: productStampFromBridge(stamp),
      baseRevision: exactU64(baseRevision, 'bots base revision'),
      header: botsHeaderFromBridge(header),
      state: state == null ? null : botsStateFromBridge(state),
    ),
};

BotsFrame botsFrameFromBridge(feed.BridgeBotsFrame value) => switch (value) {
  feed.BridgeBotsFrame_Data(:final deliverySequence, :final event) =>
    BotsFrame.data(
      deliverySequence: exactU64(deliverySequence, 'bots delivery sequence'),
      event: botsEventFromBridge(event),
    ),
  feed.BridgeBotsFrame_ResyncRequired(:final identity, :final reason) =>
    BotsFrame.resyncRequired(
      identity: productFeedIdentityFromBridge(identity),
      reason: productResyncFromBridge(reason),
    ),
  feed.BridgeBotsFrame_Failure(:final identity, :final error) =>
    BotsFrame.failure(
      identity: productFeedIdentityFromBridge(identity),
      error: bridgeFailure(error),
    ),
  feed.BridgeBotsFrame_Closed(:final identity, :final reason) =>
    BotsFrame.closed(
      identity: productFeedIdentityFromBridge(identity),
      reason: productClosedFromBridge(reason),
    ),
};
