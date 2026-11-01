import 'dart:async';

import 'package:anywork_client/studio_client.dart';

/// Records actual SDK admissions and lets a test suspend the component boundary.
final class ControlledBatchConsumer implements ConversationBatchConsumer {
  final List<ChatBatch> batches = [];
  final Map<int, Completer<void>> _entered = {};
  Future<void> Function(ChatBatch batch)? onApply;

  Future<void> waitForCount(int count) => batches.length >= count
      ? Future.value()
      : (_entered[count] ??= Completer<void>()).future;

  @override
  Future<void> applyBatch(ChatBatch batch) async {
    batches.add(batch);
    _entered.remove(batches.length)?.complete();
    await onApply?.call(batch);
  }
}
