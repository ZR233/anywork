import 'package:freezed_annotation/freezed_annotation.dart';

import '../../../resources.dart';
import '../domain/bot_values.dart';
import '../domain/bots_state.dart';

part 'bots_frames.freezed.dart';

/// Baseline consumes a Data delivery just like every subsequent publication.
@Freezed(toStringOverride: false)
sealed class BotsFrame with _$BotsFrame {
  const factory BotsFrame.data({
    required int deliverySequence,
    required BotsEvent event,
  }) = BotsData;
  const factory BotsFrame.resyncRequired({
    required ProductFeedIdentity identity,
    required ProductResyncReason reason,
  }) = BotsResyncRequired;
  const factory BotsFrame.failure({
    required ProductFeedIdentity identity,
    required StudioFailure error,
  }) = BotsFeedFailure;
  const factory BotsFrame.closed({
    required ProductFeedIdentity identity,
    required ProductFeedCloseReason reason,
  }) = BotsClosed;
}

/// Concrete Bots members of the product-topic event family. Source metadata
/// has its own revision; neither the transport stamp nor bot CAS replaces it.
@Freezed(toStringOverride: false)
sealed class BotsEvent with _$BotsEvent {
  const factory BotsEvent.baseline({
    required ProductFeedIdentity identity,
    required ProductProjectionStamp stamp,
    required BotsHeader header,
    required BotsStateSnapshot? state,
  }) = BotsBaseline;
  const factory BotsEvent.stateChanged({
    required ProductProjectionStamp stamp,
    required int baseRevision,
    required BotsHeader header,
    required BotsStateSnapshot? state,
  }) = BotsStateChangedPayload;
}
