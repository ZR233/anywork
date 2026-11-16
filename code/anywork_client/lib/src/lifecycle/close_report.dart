import '../contracts/stamps.dart';
import 'client_resource.dart';

/// A resource lifecycle stage that can remain pending or fail during close.
enum ClientClosePhase {
  opening,
  consumer,
  closeRequest,
  close,
  leaseRelease,
  observation,
}

/// A diagnostic for one owner's stage of a resource's cleanup.
final class ClientResourceStage {
  const ClientResourceStage({
    required this.owner,
    required this.phase,
    this.ownership,
    this.scopePath = const [],
    this.pending = false,
    this.error,
    this.stackTrace,
  });

  final String owner;
  final ClientClosePhase phase;
  final ClientOwnership? ownership;
  final List<String> scopePath;
  final bool pending;
  final Object? error;
  final StackTrace? stackTrace;

  bool get complete => !pending && error == null;
}

/// A resource whose cleanup or consumer completion is not yet confirmed.
///
/// Reports preserve the original owner, error and stages while identifying the
/// actual resource consistently across proxy and owner paths.
final class UnresolvedResource {
  const UnresolvedResource({
    required this.owner,
    required this.attemptId,
    required this.reason,
    required this.resourceId,
    this.ownership,
    this.stages = const [],
  });

  final ClientResourceId resourceId;
  final String owner;
  final AttemptId attemptId;
  final Object reason;
  final ClientOwnership? ownership;
  final List<ClientResourceStage> stages;
}

/// The deduplicated unresolved resources from a bounded cleanup wait.
///
/// Entries with the same resource identity merge their owner and proxy stages;
/// a native acknowledgement does not erase an unfinished consumer stage.
final class CloseReport {
  CloseReport({Iterable<UnresolvedResource> unresolved = const []})
    : unresolved = _merge(unresolved);

  final List<UnresolvedResource> unresolved;
  bool get complete => unresolved.isEmpty;
}

List<UnresolvedResource> _merge(Iterable<UnresolvedResource> resources) {
  final result = <UnresolvedResource>[];
  final positions = <ClientResourceId, int>{};
  for (final resource in resources) {
    final id = resource.resourceId;
    final position = positions[id];
    if (position == null) {
      positions[id] = result.length;
      result.add(_combine(resource, null));
    } else {
      result[position] = _combine(result[position], resource);
    }
  }
  return List.unmodifiable(result);
}

UnresolvedResource _combine(
  UnresolvedResource first,
  UnresolvedResource? second,
) {
  final stages = <ClientResourceStage>[];
  for (final resource in [first, if (second != null) second]) {
    final source = resource.stages.isEmpty
        ? [
            ClientResourceStage(
              owner: resource.owner,
              phase: ClientClosePhase.close,
              ownership: resource.ownership,
              error: resource.reason,
            ),
          ]
        : resource.stages;
    for (final stage in source) {
      if (!stages.any(
        (previous) =>
            previous.owner == stage.owner &&
            previous.phase == stage.phase &&
            previous.ownership == stage.ownership &&
            _samePath(previous.scopePath, stage.scopePath) &&
            previous.pending == stage.pending &&
            identical(previous.error, stage.error),
      )) {
        stages.add(stage);
      }
    }
  }
  var primary = first;
  if (second != null &&
      second.ownership == ClientOwnership.owned &&
      first.ownership != ClientOwnership.owned &&
      (second.stages.isEmpty ||
          second.stages.any((stage) => !stage.complete))) {
    primary = second;
  }
  ClientResourceStage? actualFailure;
  for (final stage in stages) {
    if (stage.ownership == ClientOwnership.owned && stage.error != null) {
      actualFailure ??= stage;
      if (stage.phase == ClientClosePhase.close) {
        actualFailure = stage;
        break;
      }
    }
  }
  return UnresolvedResource(
    resourceId: first.resourceId,
    owner: actualFailure?.owner ?? primary.owner,
    attemptId: primary.attemptId,
    reason: actualFailure?.error ?? primary.reason,
    ownership: actualFailure?.ownership ?? primary.ownership,
    stages: List.unmodifiable(stages),
  );
}

bool _samePath(List<String> first, List<String> second) {
  if (first.length != second.length) return false;
  for (var index = 0; index < first.length; index++) {
    if (first[index] != second[index]) return false;
  }
  return true;
}
