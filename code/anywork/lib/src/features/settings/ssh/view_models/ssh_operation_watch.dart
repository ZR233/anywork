import 'package:anywork_client/operations.dart';
import 'package:anywork_client/resources.dart';

import '../../state/settings_action.dart';

/// A bounded presentation observer, never an operation owner or command lane.
final class SshOperationWatch {
  Observation? _observation;
  void dispose() { _observation?.cancel(); _observation = null; }

  Future<({SettingsAction action, T? value})> run<T>({required int intent,
    required OperationTicket<T> Function() admit, required bool Function() owns,
    required void Function(SettingsAction) update}) async {
    OperationTicket<T> ticket;
    try { ticket = admit(); }
    on StudioFailure catch (error) {
      final action = SettingsAction(intent: intent, outcome: SettingsActionOutcome.rejected, error: error);
      if (owns()) update(action);
      return (action: action, value: null);
    }
    var action = SettingsAction(intent: intent, pending: true, operation: ticket.state.value);
    StudioFailure? observationError;
    if (owns()) {
      dispose();
      try {
        final watch = ticket.state.watchLatest((operation) {
          action = action.copyWith(operation: operation);
          if (owns()) update(action);
        });
        if (owns()) { _observation = watch.observation; action = action.copyWith(operation: watch.value); }
        else { watch.observation.cancel(); }
      } on StudioFailure catch (error) { observationError = error; }
      action = action.copyWith(observationError: observationError);
      if (owns()) update(action);
    }
    final result = await ticket.result;
    action = settledSettingsAction(intent, result, operation: ticket.state.value)
      .copyWith(observationError: observationError);
    if (owns()) update(action);
    // Explicit-result SSH actions have no product observation receipt to keep
    // watching after settlement; unknown work still belongs to the Repository.
    if (owns()) dispose();
    return (action: action, value: switch (result) {
      CommittedCommandResult<T>(:final value) || AcknowledgedCommandResult<T>(:final value) => value,
      _ => null,
    });
  }
}
