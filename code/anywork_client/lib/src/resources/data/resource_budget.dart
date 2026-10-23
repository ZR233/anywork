import '../domain/budgets.dart';
import '../domain/failures.dart';
import '../domain/observation.dart';
import 'latest_value.dart';

final class ResourceBudgetExceeded implements Exception {
  const ResourceBudgetExceeded(this.kind, this.capacity);

  final ResourceKind kind;
  final int capacity;

  StudioFailure get failure => StudioFailure(
    code: StudioFailureCode.overloaded,
    message: 'The resource budget is exhausted.',
    retryable: true,
    correlationId: '',
    details: StudioFailureDetails.resourceLimit(
      resource: kind.name,
      capacity: capacity,
    ),
  );

  @override
  String toString() => 'ResourceBudgetExceeded(${kind.name}, $capacity)';
}

/// Opening, retiring and unresolved resources keep their original permit.
final class ResourceBudget {
  ResourceBudget({
    Map<ResourceKind, int> capacities = const {
      ResourceKind.chatHandle: 2,
      ResourceKind.pendingOperation: 64,
      ResourceKind.draft: 64,
      ResourceKind.attachment: 256,
      ResourceKind.observer: 1024,
      ResourceKind.readModel: 256,
    },
  }) : capacities = Map.unmodifiable(capacities) {
    if (capacities.values.any((value) => value < 0)) {
      throw ArgumentError('Resource capacities cannot be negative');
    }
  }

  final Map<ResourceKind, int> capacities;
  final Set<ResourcePermit> _permits = {};
  final Map<ResourceKind, LatestValue<int>> _releases = {};

  Observation watchAvailability(ResourceKind kind, void Function() listener) =>
      _releases.putIfAbsent(kind, () => LatestValue(0)).watch((_) {
        if (used(kind) < (capacities[kind] ?? 0)) listener();
      });

  ResourcePermit acquire(
    ResourceKind kind, {
    required String owner,
    ResourcePhase phase = ResourcePhase.active,
  }) {
    final capacity = capacities[kind] ?? 0;
    if (used(kind) >= capacity) throw ResourceBudgetExceeded(kind, capacity);
    final permit = ResourcePermit._(this, kind, owner, phase);
    _permits.add(permit);
    return permit;
  }

  int used(ResourceKind kind) =>
      _permits.where((permit) => permit.kind == kind).length;

  List<ResourceUsage> get usage => List.unmodifiable([
    for (final permit in _permits)
      ResourceUsage(kind: permit.kind, owner: permit.owner, phase: permit.phase),
  ]);

  void _release(ResourcePermit permit) {
    if (!_permits.remove(permit)) return;
    final source = _releases[permit.kind];
    if (source != null) source.publish(source.value + 1);
  }
}

final class ResourcePermit {
  ResourcePermit._(this._budget, this.kind, this.owner, this._phase);

  final ResourceBudget _budget;
  final ResourceKind kind;
  final String owner;
  ResourcePhase _phase;
  bool _released = false;

  ResourcePhase get phase => _phase;
  bool get isReleased => _released;

  void mark(ResourcePhase next) {
    if (_released) throw StateError('A released permit cannot change phase');
    _phase = next;
  }

  void release() {
    if (_released) return;
    _released = true;
    _budget._release(this);
  }
}
