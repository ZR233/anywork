import 'package:anywork_client/conversation_ports.dart';

import '../../../rust/api/studio/conversation/authoring.dart' as wire;
import '../../../rust/api/studio/conversation/authoring_feed.dart' as native;
import 'authoring_converters.dart';
import 'identity_converters.dart';
import 'thread_feed_connection.dart';

/// Only the original Authoring feed; no latest slot, body cache or extra FIFO.
final class FrbThreadAuthoringConnection
    extends
        FrbThreadFeedConnection<
          native.BridgeThreadAuthoring,
          wire.BridgeAuthoringFrame,
          ThreadAuthoringFrame
        > {
  FrbThreadAuthoringConnection.open({
    required this.threadId,
    required ThreadObservationMode mode,
  }) : super(
         resource: 'thread-authoring',
         diagnosticPrefix: 'authoring-feed',
         facet: ThreadFacet.authoring,
         open: () => native.openThreadAuthoring(
           threadId: threadId,
           mode: observationModeToBridge(mode),
         ),
         identityOf: (handle) => handle.identity(),
         openNativeStream: (handle) => handle.stream(),
         acknowledgeNative: (handle, sequence) =>
             handle.ackThrough(deliverySequence: sequence),
         requestNativeClose: (handle) => handle.requestClose(),
         closeNative: (handle) => handle.close(),
         retryNativeClose: (handle) => handle.retryClose(),
         disposeNative: (handle) => handle.dispose(),
         convert: authoringFrameFromBridge,
         frameIdentity: (frame) => switch (frame) {
           ThreadAuthoringData(
             event: ThreadAuthoringBaselineEvent(:final identity),
           ) =>
             identity,
           ThreadAuthoringData(event: ThreadAuthoringChangeEvent()) => null,
           ThreadAuthoringResyncRequired(:final identity) => identity,
           ThreadAuthoringFailure(:final identity) => identity,
           ThreadAuthoringClosed(:final identity) => identity,
         },
         frameStamp: (frame) => switch (frame) {
           ThreadAuthoringData(
             event: ThreadAuthoringBaselineEvent(:final stamp),
           ) =>
             stamp,
           ThreadAuthoringData(
             event: ThreadAuthoringChangeEvent(:final stamp),
           ) =>
             stamp,
           _ => null,
         },
         failureFrame: (identity, failure) =>
             ThreadAuthoringFrame.failure(identity: identity, error: failure),
         isTerminal: (frame) => frame is! ThreadAuthoringData,
       );

  final String threadId;
}
