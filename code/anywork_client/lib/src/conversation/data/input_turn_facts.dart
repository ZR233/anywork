import '../../../models.dart';
import '../../lifecycle/resource_budget.dart';
import '../../observation/latest_value.dart';

/// Internal evidence only: no body, descriptor, feed demand or history mirror.
final class InputTurnFact {
  const InputTurnFact({
    required this.threadId,
    required this.inputId,
    required this.itemId,
    required this.turnId,
    required this.status,
    required this.saved,
  });
  final String threadId;
  final String inputId;
  final String? itemId;
  final String? turnId;
  final StudioTurnStatus status;

  /// Null means the completion stream did not establish durability.
  final bool? saved;
}

abstract interface class InputTurnFacts {
  Observation watchInputFacts({
    required String inputId,
    String? expectedThreadId,
    required void Function(InputTurnFact) onFact,
  });
}

/// Only explicitly registered inputs have extra observations, bounded by the
/// existing observer budget. Registration never creates a session or feed.
final class InputFactRegistry implements InputTurnFacts {
  InputFactRegistry(this.budget, {required this.seed});
  final ResourceBudget budget;
  final void Function(String, void Function(InputTurnFact)) seed;
  final Map<String, Set<_FactObservation>> _inputs = {};
  bool get hasObservers => _inputs.isNotEmpty;
  bool isWatching(String inputId) => _inputs[inputId]?.isNotEmpty ?? false;

  @override
  Observation watchInputFacts({
    required String inputId,
    String? expectedThreadId,
    required void Function(InputTurnFact) onFact,
  }) {
    final permit = budget.acquire(
      ResourceKind.observer,
      owner: 'input:$inputId',
    );
    final observation = _FactObservation(this, inputId, permit, onFact);
    (_inputs[inputId] ??= {}).add(observation);
    try {
      // Do not filter by expectedThreadId here: the submission owner must see
      // a conflicting thread for this input and report a synchronization error.
      seed(inputId, observation.deliver);
      return observation;
    } catch (_) {
      observation.cancel();
      rethrow;
    }
  }

  void publish(InputTurnFact fact) {
    for (final observer in List<_FactObservation>.of(
      _inputs[fact.inputId] ?? const <_FactObservation>{},
    )) {
      observer.deliver(fact);
    }
  }
}

final class _FactObservation implements Observation {
  _FactObservation(this.registry, this.inputId, this.permit, this.callback);
  final InputFactRegistry registry;
  final String inputId;
  final ResourcePermit permit;
  final void Function(InputTurnFact) callback;
  @override
  bool isCancelled = false;
  @override
  bool isPaused = false;
  void deliver(InputTurnFact fact) {
    if (!isCancelled && !isPaused) callback(fact);
  }

  @override
  void pause() => isPaused = true;
  @override
  void resume() => isPaused = false;
  @override
  void cancel() {
    if (isCancelled) return;
    isCancelled = true;
    final observers = registry._inputs[inputId];
    observers?.remove(this);
    if (observers?.isEmpty ?? false) registry._inputs.remove(inputId);
    permit.release();
  }
}
