import '../../contracts/stamps.dart';
import '../../lifecycle/resource_budget.dart';

/// Logical draft and submitted payloads each retain their own attachment owner.
/// An old ACK can release only its submission's ownership, never a newer draft's.
final class AttachmentDraftStore {
  AttachmentDraftStore({ResourceBudget? budget})
    : budget = budget ?? ResourceBudget();

  final ResourceBudget budget;
  final Map<String, _AttachmentEntry> _entries = {};

  int get retainedCount => _entries.length;

  void adopt(String draftId, Iterable<String> attachmentIds) =>
      _retain('draft:$draftId', attachmentIds);

  void freeze(OperationId operationId, Iterable<String> attachmentIds) =>
      _retain('operation:${operationId.value}', attachmentIds);

  void _retain(String owner, Iterable<String> attachmentIds) {
    final ids = attachmentIds.toSet();
    if (ids.any((id) => id.isEmpty)) {
      throw ArgumentError('Attachment identities cannot be empty');
    }
    final acquired = <String, ResourcePermit>{};
    try {
      for (final id in ids) {
        if (!_entries.containsKey(id)) {
          acquired[id] = budget.acquire(ResourceKind.attachment, owner: id);
        }
      }
    } catch (_) {
      // Roll back only this synchronous reservation; no ownership was changed.
      for (final permit in acquired.values) {
        permit.release();
      }
      rethrow;
    }
    for (final id in ids) {
      final entry = _entries.putIfAbsent(
        id,
        () => _AttachmentEntry(acquired[id]!),
      );
      entry.owners.add(owner);
    }
  }

  List<String> detach(String draftId, Iterable<String> attachmentIds) =>
      _release('draft:$draftId', attachmentIds);

  List<String> discardDraft(String draftId) =>
      _release('draft:$draftId', List.of(_entries.keys));

  List<String> completeSubmission(OperationId operationId) =>
      _release('operation:${operationId.value}', List.of(_entries.keys));

  List<String> _release(String owner, Iterable<String> ids) {
    final released = <String>[];
    for (final id in ids.toSet()) {
      final entry = _entries[id];
      if (entry == null || !entry.owners.remove(owner)) continue;
      if (entry.owners.isEmpty) {
        _entries.remove(id);
        entry.permit.release();
        released.add(id);
      }
    }
    return List.unmodifiable(released);
  }
}

final class _AttachmentEntry {
  _AttachmentEntry(this.permit);
  final ResourcePermit permit;
  final Set<String> owners = {};
}
