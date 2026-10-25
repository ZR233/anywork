import 'package:anywork_client/conversation_ports.dart';

import '../../../rust/api/studio/conversation/configuration.dart' as wire;
import '../../../rust/api/studio/conversation/configuration_feed.dart'
    as native;
import 'configuration_converters.dart';
import 'identity_converters.dart';
import 'thread_feed_connection.dart';

/// The original Thread Configuration feed; no latest slot or second pending queue.
final class FrbThreadConfigurationConnection
    extends
        FrbThreadFeedConnection<
          native.BridgeThreadConfiguration,
          wire.BridgeThreadConfigurationFrame,
          ThreadConfigurationFrame
        > {
  FrbThreadConfigurationConnection.open({
    required this.threadId,
    required ThreadObservationMode mode,
  }) : super(
         resource: 'thread-configuration',
         diagnosticPrefix: 'thread-configuration-feed',
         facet: ThreadFacet.configuration,
         open: () => native.openThreadConfiguration(
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
         convert: configurationFrameFromBridge,
         frameIdentity: (frame) => switch (frame) {
           ThreadConfigurationData(
             event: ThreadConfigurationBaselineEvent(:final identity),
           ) =>
             identity,
           ThreadConfigurationData(event: ThreadConfigurationReplaceEvent()) =>
             null,
           ThreadConfigurationResyncRequired(:final identity) => identity,
           ThreadConfigurationFailure(:final identity) => identity,
           ThreadConfigurationClosed(:final identity) => identity,
         },
         frameStamp: (frame) => switch (frame) {
           ThreadConfigurationData(
             event: ThreadConfigurationBaselineEvent(:final stamp),
           ) =>
             stamp,
           ThreadConfigurationData(
             event: ThreadConfigurationReplaceEvent(:final stamp),
           ) =>
             stamp,
           _ => null,
         },
         failureFrame: (identity, failure) => ThreadConfigurationFrame.failure(
           identity: identity,
           error: failure,
         ),
         isTerminal: (frame) => frame is! ThreadConfigurationData,
       );

  final String threadId;
}
