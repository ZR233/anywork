import 'package:freezed_annotation/freezed_annotation.dart';

import '../../../resources.dart';
import 'bot_values.dart';
import 'bot_conversation_values.dart';

part 'bots_state.freezed.dart';

@freezed
abstract class BotsHeader with _$BotsHeader {
  const factory BotsHeader({
    required ObservedHeader source,
    required int? botsRevision,
    required int? updatedAt,
  }) = _BotsHeader;
}

/// Transport and source availability are independent. A retained snapshot
/// keeps its original owner/version during reconnect; a new header without a
/// business value never relabels that snapshot as new-current evidence.
@Freezed(toStringOverride: false)
abstract class BotsState with _$BotsState {
  const factory BotsState({
    required ProductProjection<BotsHeader> projection,
    required ReadValue<ProductSourceStatus, ProductSourceStatusRef>?
    sourceStatus,
    required Materialized<BotsStateSnapshot, ResourceStamp>? snapshot,
  }) = _BotsState;
}

/// Unknown page and continuation remain null/unknown until an actual read.
@Freezed(toStringOverride: false)
abstract class BotConversationsState with _$BotConversationsState {
  const factory BotConversationsState({
    required String botId,
    required BotConversationPage? page,
    required CollectionContinuation continuation,
    required bool loading,
    required StudioFailure? error,
    required bool closed,
  }) = _BotConversationsState;
}
