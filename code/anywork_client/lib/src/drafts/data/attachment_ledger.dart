import '../../contracts/stamps.dart';

/// Logical draft and submitted payloads each retain their own attachment owner.
/// An old ACK can release only its submission's ownership, never a newer draft's.
final class AttachmentDraftStore {
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
    for (final id in ids) {
      final entry = _entries.putIfAbsent(id, () => _AttachmentEntry());
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
        released.add(id);
      }
    }
    return List.unmodifiable(released);
  }
}

final class _AttachmentEntry {
  final Set<String> owners = {};
}
