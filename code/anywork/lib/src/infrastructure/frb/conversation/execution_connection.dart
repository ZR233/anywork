import 'package:anywork_client/conversation_ports.dart';

import '../../../rust/api/studio/conversation/execution.dart' as wire;
import '../../../rust/api/studio/conversation/execution_feed.dart' as native;
import 'execution_converters.dart';
import 'identity_converters.dart';
import 'thread_feed_connection.dart';

/// One original native FIFO/window. ACK is exclusively the SDK consumer's
/// actual prefix; this adapter neither coalesces Data nor queues replay work.
final class FrbThreadExecutionConnection
    extends
        FrbThreadFeedConnection<
          native.BridgeThreadExecution,
          wire.BridgeExecutionFrame,
          ThreadExecutionFrame
        > {
  FrbThreadExecutionConnection.open({
    required String threadId,
    required ThreadObservationMode mode,
  }) : this._(
         threadId: threadId,
         open: () => native.openThreadExecution(
           threadId: threadId,
           mode: observationModeToBridge(mode),
         ),
       );

  /// Adopts the actual pinned native feed without reopening by Thread ID.
  FrbThreadExecutionConnection.fromHandle({
    required String threadId,
    required native.BridgeThreadExecution handle,
  }) : this._(threadId: threadId, open: () async => handle);

  FrbThreadExecutionConnection._({required this.threadId, required super.open})
    : super(
        resource: 'thread-execution',
        diagnosticPrefix: 'execution-feed',
        facet: ThreadFacet.execution,
        identityOf: (handle) => handle.identity(),
        openNativeStream: (handle) => handle.stream(),
        acknowledgeNative: (handle, sequence) =>
            handle.ackThrough(deliverySequence: sequence),
        requestNativeClose: (handle) => handle.requestClose(),
        closeNative: (handle) => handle.close(),
        retryNativeClose: (handle) => handle.retryClose(),
        disposeNative: (handle) => handle.dispose(),
        convert: executionFrameFromBridge,
        frameIdentity: (frame) => switch (frame) {
          ThreadExecutionData(
            event: ThreadExecutionBaselineEvent(:final identity),
          ) =>
            identity,
          ThreadExecutionData(event: ThreadExecutionChangeEvent()) => null,
          ThreadExecutionResyncRequired(:final identity) => identity,
          ThreadExecutionFailure(:final identity) => identity,
          ThreadExecutionClosed(:final identity) => identity,
        },
        frameStamp: (frame) => switch (frame) {
          ThreadExecutionData(
            event: ThreadExecutionBaselineEvent(:final stamp),
          ) =>
            stamp,
          ThreadExecutionData(
            event: ThreadExecutionChangeEvent(:final stamp),
          ) =>
            stamp,
          _ => null,
        },
        failureFrame: (identity, failure) =>
            ThreadExecutionFrame.failure(identity: identity, error: failure),
        isTerminal: (frame) => frame is! ThreadExecutionData,
      );

  final String threadId;
}
