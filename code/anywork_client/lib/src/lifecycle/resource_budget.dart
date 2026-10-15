import '../contracts/stamps.dart';
import '../observation/latest_value.dart';

enum ResourceKind {
  chatHandle,
  pendingOperation,
  draft,
  attachment,
  observer,
  readModel,
}

enum ResourcePhase { opening, active, retiring, unresolved }

final class ResourceBudgetExceeded implements Exception {
  const ResourceBudgetExceeded(this.kind, this.capacity);
  final ResourceKind kind;
  final int capacity;

  @override
  String toString() => 'Resource budget exhausted: $kind ($capacity)';
}

/// Permits remain held while resources are opening, retiring or unresolved.
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
  final LatestValue<ResourceKind?> _releases = LatestValue(null);

  /// Capacity changes only when a real owner releases its permit. Registration
  /// and a failed acquire occur in the same isolate, so no timer or polling is
  /// needed to resume an observation blocked behind retiring native resources.
  Observation watchAvailability(ResourceKind kind, void Function() listener) =>
      _releases.watch((released) {
        if (released == kind && used(kind) < (capacities[kind] ?? 0)) {
          listener();
        }
      });

  void _release(ResourcePermit permit) {
    if (_permits.remove(permit)) _releases.publish(permit.kind);
  }

  ResourcePermit acquire(
    ResourceKind kind, {
    required String owner,
    ResourcePhase phase = ResourcePhase.active,
  }) {
    final capacity = capacities[kind] ?? 0;
    if (used(kind) >= capacity) {
      throw ResourceBudgetExceeded(kind, capacity);
    }
    final permit = ResourcePermit._(this, kind, owner, phase);
    _permits.add(permit);
    return permit;
  }

  int used(ResourceKind kind) =>
      _permits.where((permit) => permit.kind == kind).length;

  List<ResourceUsage> get usage => List.unmodifiable([
    for (final permit in _permits)
      ResourceUsage(
        kind: permit.kind,
        owner: permit.owner,
        phase: permit.phase,
      ),
  ]);
}

final class ResourcePermit {
  ResourcePermit._(this._budget, this.kind, this.owner, this.phase);
  final ResourceBudget _budget;
  final ResourceKind kind;
  final String owner;
  ResourcePhase phase;
  bool _released = false;

  bool get isReleased => _released;

  void mark(ResourcePhase next) {
    if (_released) throw StateError('A released permit cannot change phase');
    phase = next;
  }

  void release() {
    if (_released) return;
    _released = true;
    _budget._release(this);
  }
}

final class ResourceUsage {
  const ResourceUsage({
    required this.kind,
    required this.owner,
    required this.phase,
  });
  final ResourceKind kind;
  final String owner;
  final ResourcePhase phase;
}

final class UnresolvedResource {
  const UnresolvedResource({
    required this.owner,
    required this.attemptId,
    required this.reason,
  });
  final String owner;
  final AttemptId attemptId;
  final Object reason;
}

final class CloseReport {
  CloseReport({Iterable<UnresolvedResource> unresolved = const []})
    : unresolved = List.unmodifiable(unresolved);

  final List<UnresolvedResource> unresolved;
  bool get complete => unresolved.isEmpty;
}
