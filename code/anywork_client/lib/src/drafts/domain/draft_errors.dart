/// Cleanup has not joined all actual native drafts, admissions or staging files.
/// Ownership and permits remain held until explicit cleanup succeeds.
final class AttachmentCleanupUnresolved implements Exception {
  AttachmentCleanupUnresolved(
    Iterable<String> draftIds, {
    Iterable<String> admissionOwners = const [],
    Iterable<String> stagingPaths = const [],
  }) : draftIds = List.unmodifiable(draftIds),
       admissionOwners = List.unmodifiable(admissionOwners),
       stagingPaths = List.unmodifiable(stagingPaths);
  final List<String> draftIds;
  final List<String> admissionOwners;
  final List<String> stagingPaths;
  @override
  String toString() =>
      'Attachment resources unresolved: ${[...draftIds, ...admissionOwners, ...stagingPaths].join(', ')}';
}
