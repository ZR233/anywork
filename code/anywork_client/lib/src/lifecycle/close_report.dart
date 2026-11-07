import '../contracts/stamps.dart';

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
