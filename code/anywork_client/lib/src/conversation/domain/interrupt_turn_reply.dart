import 'package:freezed_annotation/freezed_annotation.dart';

import '../../../operations.dart';

part 'interrupt_turn_reply.freezed.dart';

/// Native cancellation acceptance, not proof that the original Turn stopped.
@Freezed(toStringOverride: false)
abstract class InterruptTurnReply with _$InterruptTurnReply {
  const factory InterruptTurnReply({
    required String threadId,
    required String turnId,
    required bool interrupted,
    required CommitReceipt receipt,
  }) = _InterruptTurnReply;
}
