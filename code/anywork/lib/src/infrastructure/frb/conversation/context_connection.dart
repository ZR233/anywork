import 'package:anywork_client/conversation_ports.dart';

import '../../../rust/api/studio/conversation/context.dart' as wire;
import '../../../rust/api/studio/conversation/context_feed.dart' as native;
import 'context_converters.dart';
import 'identity_converters.dart';
import 'thread_feed_connection.dart';

/// The original Thread Context feed; no latest slot or second pending queue.
final class FrbThreadContextConnection
    extends
        FrbThreadFeedConnection<
          native.BridgeThreadContext,
          wire.BridgeContextFrame,
          ThreadContextFrame
        > {
  FrbThreadContextConnection.open({
    required this.threadId,
    required ThreadObservationMode mode,
  }) : super(
         resource: 'thread-context',
         diagnosticPrefix: 'thread-context-feed',
         facet: ThreadFacet.context,
         open: () => native.openThreadContext(
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
         convert: contextFrameFromBridge,
         frameIdentity: (frame) => switch (frame) {
           ThreadContextData(
             event: ThreadContextBaselineEvent(:final identity),
           ) =>
             identity,
           ThreadContextData(event: ThreadContextReplaceEvent()) => null,
           ThreadContextResyncRequired(:final identity) => identity,
           ThreadContextFailure(:final identity) => identity,
           ThreadContextClosed(:final identity) => identity,
         },
         frameStamp: (frame) => switch (frame) {
           ThreadContextData(event: ThreadContextBaselineEvent(:final stamp)) =>
             stamp,
           ThreadContextData(event: ThreadContextReplaceEvent(:final stamp)) =>
             stamp,
           _ => null,
         },
         failureFrame: (identity, failure) =>
             ThreadContextFrame.failure(identity: identity, error: failure),
         isTerminal: (frame) => frame is! ThreadContextData,
       );

  final String threadId;
}
