import 'package:anywork_client/resources_ports.dart';

import '../domain/recovery_values.dart';
import 'recovery_port.dart';
import 'recovery_reads.dart';

final class RecoveryReader {
  RecoveryReader(this.scope)
    : _readText = ((field, offset) =>
          scope.text(field, offset: offset, maxBytes: 65536));
  final RecoveryReadConnection scope;
  final Future<TextChunk> Function(int fieldId, int offset) _readText;

  Future<RecoveryIssue> issue(RecoveryIssueRead value) async => RecoveryIssue(
    id: await materializeReadText(value.id, read: _readText),
    scope: value.scope,
    category: value.category,
    availableActions: List.unmodifiable(value.availableActions),
    projectId: value.projectId == null
        ? null
        : await materializeReadText(value.projectId!, read: _readText),
    threadId: value.threadId == null
        ? null
        : await materializeReadText(value.threadId!, read: _readText),
    message: await materializeReadText(value.message, read: _readText),
    worktree: value.worktree == null ? null : await worktree(value.worktree!),
  );

  Future<WorktreeRecoveryPreview> worktree(
    WorktreeRecoveryPreviewRead value,
  ) async => WorktreeRecoveryPreview(
    inspection: value.inspection,
    ownerKind: value.ownerKind,
    ownerThreadId: await materializeReadText(
      value.ownerThreadId,
      read: _readText,
    ),
    leaseRevision: value.leaseRevision,
    state: await materializeReadText(value.state, read: _readText),
    repositoryRoot: await materializeReadText(
      value.repositoryRoot,
      read: _readText,
    ),
    path: await materializeReadText(value.path, read: _readText),
    branch: await materializeReadText(value.branch, read: _readText),
    baseCommit: await materializeReadText(value.baseCommit, read: _readText),
    headCommit: value.headCommit == null
        ? null
        : await materializeReadText(value.headCommit!, read: _readText),
    dirty: value.dirty,
    changedFiles: value.changedFiles == null
        ? null
        : await changedFiles(value.changedFiles!),
  );

  Future<List<String>> changedFiles(TypedListRef reference) async {
    if (reference.total < 0)
      throw resourceProtocol('Invalid recovery list length.');
    var offset = 0;
    final values = <String>[];
    while (offset < reference.total) {
      final page = await scope.changedFiles(reference.listId, offset: offset);
      final items = List.of(page.items);
      final end = offset + items.length;
      if (page.listId != reference.listId ||
          page.offset != offset ||
          page.total != reference.total ||
          items.length > 32 ||
          end > reference.total ||
          items.isEmpty ||
          page.nextOffset != (end == reference.total ? null : end)) {
        throw resourceProtocol(
          'Recovery changed-files page identity mismatch.',
        );
      }
      for (final item in items) {
        values.add(await materializeReadText(item.value, read: _readText));
      }
      offset = end;
    }
    return List.unmodifiable(values);
  }
}
