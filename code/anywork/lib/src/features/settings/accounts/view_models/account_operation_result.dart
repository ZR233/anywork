import 'dart:async';

import 'package:anywork_client/studio_client.dart'
    show OperationState, OperationPhase, Observation;
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../../presentation/providers/account_operation_observation.dart';
import 'account_projection.dart';

void trackAccountOperation(
  Ref ref,
  OperationState result,
  List<Observation> subscriptions,
  void Function(OperationState) update,
) {
  final source = ref.read(accountOperationObservationProvider)(result.id);
  if (source == null) {
    update(result);
    return;
  }
  Observation? observation;
  void deliver(OperationState value) {
    if (!ref.mounted) return;
    update(value);
    if (operationSaved(value) ||
        value.failurePhase == OperationPhase.rejected) {
      observation?.cancel();
      subscriptions.remove(observation);
    }
  }

  observation = source.watch(deliver);
  subscriptions.add(observation);
  deliver(source.value);
}

/// Await only the already admitted operation, never issue a replacement id.
/// Disposing this display wait does not cancel the SDK's accepted work.
Future<OperationState?> observeAccountOperation(
  Ref ref,
  OperationState result,
) async {
  final source = ref.read(accountOperationObservationProvider)(result.id);
  final current = source?.value ?? result;
  if (operationSaved(current) ||
      current.failurePhase != null ||
      source == null) {
    return current;
  }
  final completion = Completer<OperationState?>();
  Observation? observation;
  void settle(OperationState next) {
    if (completion.isCompleted ||
        (!operationSaved(next) && next.failurePhase == null)) {
      return;
    }
    observation?.cancel();
    completion.complete(next);
  }

  observation = source.watch(settle);
  ref.onDispose(() {
    observation?.cancel();
    if (!completion.isCompleted) completion.complete(null);
  });
  settle(source.value);
  return completion.future;
}
