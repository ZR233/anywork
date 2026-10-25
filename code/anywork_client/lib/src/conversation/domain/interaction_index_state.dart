import 'package:freezed_annotation/freezed_annotation.dart';

import '../../../resources.dart';
import 'execution_values.dart';
import 'thread_identity.dart';

part 'interaction_index_state.freezed.dart';

@Freezed(toStringOverride: false)
abstract class InteractionListItem with _$InteractionListItem {
  const factory InteractionListItem({
    required InteractionReadRef reference,
    required String interactionId,
    required int revision,
    required InteractionKind kind,
    required InteractionStatus status,
    required int createdAt,
    required int updatedAt,
  }) = _InteractionListItem;
}

@Freezed(toStringOverride: false)
final class InteractionIndexReadSnapshot with _$InteractionIndexReadSnapshot {
  InteractionIndexReadSnapshot({
    required this.origin,
    required this.index,
    required List<InteractionListItem> items,
    required this.nextOffset,
    required this.complete,
  }) : items = List.unmodifiable(items);
  final ThreadFacetStamp origin;
  final InteractionIndexHeader index;
  final List<InteractionListItem> items;
  final int? nextOffset;
  final bool complete;
}

@Freezed(toStringOverride: false)
abstract class InteractionIndexReadState with _$InteractionIndexReadState {
  const factory InteractionIndexReadState({
    InteractionIndexReadSnapshot? current,
    InteractionIndexReadSnapshot? lastKnown,
    @Default(false) bool loading,
    StudioFailure? error,
  }) = _InteractionIndexReadState;
}

@Freezed(toStringOverride: false)
sealed class ConversationRecoveryAccess with _$ConversationRecoveryAccess {
  const factory ConversationRecoveryAccess.allowed() =
      AllowedConversationRecovery;
  const factory ConversationRecoveryAccess.blocked({
    required StudioFailure error,
  }) = BlockedConversationRecovery;
  const factory ConversationRecoveryAccess.unknown({StudioFailure? error}) =
      UnknownConversationRecovery;
}
