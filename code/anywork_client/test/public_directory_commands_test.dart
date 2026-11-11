import 'package:anywork_client/studio_client.dart';
import 'package:test/test.dart';

import 'support/timeline_transport.dart';

const _epoch = 'public-directory-owner';
const _native = NativeAgentBackendView(
  config: NativeAgentConfigView(),
  status: ThreadStatusView.idle,
);
const _acp = AcpAgentBackendView(
  reference: AcpSessionReferenceView(
    accountId: 'account',
    acpSessionId: 'remote',
    cwd: '/project',
  ),
);

SessionDirectoryRow _row(
  AgentBackendView backend, {
  String suffix = 'root',
  String? parentAgentId,
  String? sessionId,
  bool archived = false,
}) => SessionDirectoryRow(
  sessionId: sessionId ?? 'session-$suffix',
  agentId: 'agent-$suffix',
  parentAgentId: parentAgentId,
  threadId: 'thread-$suffix',
  workspaceId: 'project',
  title: suffix,
  mode: backend is NativeAgentBackendView && parentAgentId == null
      ? ThreadModeId.simple
      : null,
  delegationMode: DelegationMode.profile,
  delegationPreference: DelegationPreference.balanced,
  workspacePath: '/project',
  backend: backend,
  updatedAt: DateTime.utc(2026),
  archived: archived,
);

StudioCommandReceipt _receipt(OperationId id, int revision) =>
    StudioCommandReceipt(
      operationId: id,
      disposition: CommitDisposition.applied,
      targets: [
        ResourceStamp(
          resourceKey: 'thread-directory',
          ownerEpoch: _epoch,
          revision: revision,
        ),
      ],
      effect: EffectPoint.immediate,
      effective: true,
      durable: true,
    );

final class _Transport extends TestConversationTransport {
  _Transport() {
    directoryOwnerEpoch = _epoch;
  }

  late SessionDirectoryRow restored;
  late SessionDirectoryRow renamed;
  SessionDirectoryRow? nextRoot;
  final restores = <String>[];
  final renames = <(String, String)>[];
  final archives = <String>[];
  final deletes = <String>[];
  List<String> removed = [];
  OperationId? lastOperation;

  @override
  Future<SessionDirectoryRow> restoreThread(String threadId) async {
    restores.add(threadId);
    return restored;
  }

  @override
  Future<RenameThreadCommandReply> renameThread(
    String threadId,
    String title, {
    required OperationId operationId,
  }) async {
    renames.add((threadId, title));
    lastOperation = operationId;
    return RenameThreadCommandReply(
      thread: renamed,
      receipt: _receipt(operationId, 2),
    );
  }

  @override
  Future<ArchiveThreadCommandReply> archiveThread(
    String threadId, {
    required OperationId operationId,
  }) async {
    archives.add(threadId);
    lastOperation = operationId;
    return ArchiveThreadCommandReply(
      result: ArchiveThreadResult(
        archivedRootId: threadId,
        removedThreadIds: removed,
        nextRoot: nextRoot,
      ),
      receipt: _receipt(operationId, 2),
    );
  }

  @override
  Future<DeleteThreadCommandReply?> deleteThread(
    String threadId, {
    required OperationId operationId,
  }) async {
    deletes.add(threadId);
    lastOperation = operationId;
    return DeleteThreadCommandReply(
      result: DeleteThreadResult(
        deletedRootId: threadId,
        deletedThreadIds: removed,
        nextRoot: nextRoot,
      ),
      receipt: _receipt(operationId, 2),
    );
  }
}

AnyworkClient _client(_Transport port) {
  final client = AnyworkClient(transport: port, clientId: 'directory-client');
  addTearDown(() async {
    expect((await client.close()).complete, isTrue);
    await port.closeProductTopicStreams();
  });
  return client;
}

void main() {
  for (final backend in <AgentBackendView>[_native, _acp]) {
    final label = backend is NativeAgentBackendView ? 'Native' : 'ACP';

    test(
      '$label restore selects the actual directory thread, not session or agent ID',
      () async {
        final original = _row(backend, archived: true);
        final restored = original.copyWith(archived: false);
        final port = _Transport()
          ..seedThread(original)
          ..restored = restored;
        final client = _client(port);
        final metadata = client.threadDirectory.observeThread(
          original.threadId,
        );
        await metadata.state.waitFor((s) => s.frame != null);
        await client.directoryCommands.restoreThread(original.threadId);
        expect(port.restores, [original.threadId]);
        expect(client.selection.state.selectedProjectId, restored.workspaceId);
        expect(client.selection.state.selectedThreadId, restored.threadId);
        expect(
          client.threadDirectory.observedThread(original.threadId),
          same(original),
          reason: 'Command result must not create a second directory writer',
        );
        port.emitThread(restored, restored.threadId, revision: 2);
        await metadata.state.waitFor((s) => s.frame?.stamp.revision == 2);
        expect(metadata.state.value.frame!.row, same(restored));
        expect(restored.backend, same(backend));
        expect(
          restored.mode,
          backend is NativeAgentBackendView ? ThreadModeId.simple : isNull,
        );
        expect(restored.isRootRow, isTrue);
        await metadata.release();
      },
    );

    test(
      '$label rename returns the canonical row and only its real event changes metadata',
      () async {
        final original = _row(backend);
        final renamed = original.copyWith(title: 'Renamed');
        final unrelated = _row(backend, suffix: 'unrelated');
        final port = _Transport()
          ..seedThread(original)
          ..seedThread(unrelated)
          ..renamed = renamed;
        final client = _client(port);
        final metadata = client.threadDirectory.observeThread(
          original.threadId,
        );
        final other = client.threadDirectory.observeThread(unrelated.threadId);
        await metadata.state.waitFor((s) => s.frame != null);
        await other.state.waitFor((s) => s.frame != null);
        final result = await client.threadCommands.renameThread(
          original.threadId,
          'Renamed',
        );
        expect(result, same(renamed));
        expect(port.renames, [(original.threadId, 'Renamed')]);
        expect(metadata.state.value.frame!.row, same(original));
        expect(
          client.mutations.lookup(port.lastOperation!)!.state.value.observed,
          isFalse,
        );
        port.emitThread(renamed, original.threadId, revision: 2);
        await metadata.state.waitFor((s) => s.frame?.stamp.revision == 2);
        expect(metadata.state.value.frame!.row, same(result));
        expect(other.state.value.frame!.row, same(unrelated));
        expect(
          client.mutations.lookup(port.lastOperation!)!.state.value.observed,
          isTrue,
        );
        expect(result!.sessionId, original.sessionId);
        expect(result.agentId, original.agentId);
        expect(result.threadId, original.threadId);
        expect(result.parentAgentId, isNull);
        expect(result.backend, same(backend));
        if (backend is AcpAgentBackendView) expect(result.mode, isNull);
        await metadata.release();
        await other.release();
      },
    );

    for (final delete in [false, true]) {
      final command = delete ? 'delete' : 'archive';
      test(
        '$label $command follows actual next root and keeps child identity intact',
        () async {
          final root = _row(backend);
          final child = _row(
            backend,
            suffix: 'child',
            sessionId: root.sessionId,
            parentAgentId: root.agentId,
          );
          // Replacement can be another backend. No conversion through Native state.
          final next = _row(
            backend is AcpAgentBackendView ? _native : _acp,
            suffix: 'next',
          );
          final port = _Transport()
            ..seedThread(root)
            ..seedThread(child)
            ..seedThread(next)
            ..nextRoot = next
            ..removed = [root.threadId, child.threadId];
          final client = _client(port);
          final metadata = client.threadDirectory.observeThread(root.threadId);
          final childMetadata = client.threadDirectory.observeThread(
            child.threadId,
          );
          final nextMetadata = client.threadDirectory.observeThread(
            next.threadId,
          );
          await metadata.state.waitFor((s) => s.frame != null);
          await childMetadata.state.waitFor((s) => s.frame != null);
          await nextMetadata.state.waitFor((s) => s.frame != null);
          client.selection.selectThread(
            workspaceId: child.workspaceId,
            threadId: child.threadId,
          );
          if (delete) {
            await client.threadCommands.deleteThread(root.threadId);
          } else {
            await client.threadCommands.archiveThread(root.threadId);
          }
          expect(delete ? port.deletes : port.archives, [root.threadId]);
          expect(client.selection.state.selectedThreadId, next.threadId);
          expect(client.selection.state.selectedProjectId, next.workspaceId);
          expect(metadata.state.value.frame!.row, same(root));
          expect(
            childMetadata.state.value.frame!.row!.parentAgentId,
            root.agentId,
          );
          expect(child.isRootRow, isFalse);
          expect(child.mode, isNull);
          expect(childMetadata.state.value.frame!.row!.backend, same(backend));
          // The actual directory notification, not the command reply, merges removal.
          port.emitThread(null, root.threadId, revision: 2);
          port.emitThread(null, child.threadId, revision: 2);
          await metadata.state.waitFor((s) => s.frame?.stamp.revision == 2);
          await childMetadata.state.waitFor(
            (s) => s.frame?.stamp.revision == 2,
          );
          expect(metadata.state.value.frame!.row, isNull);
          expect(childMetadata.state.value.frame!.row, isNull);
          expect(nextMetadata.state.value.frame!.row, same(next));
          expect(
            client.mutations.lookup(port.lastOperation!)!.state.value.observed,
            isTrue,
          );
          await metadata.release();
          await childMetadata.release();
          await nextMetadata.release();
        },
      );
    }

    test(
      '$label child root-only operations use parentAgentId rather than ID equality',
      () async {
        final root = _row(backend);
        final child = _row(
          backend,
          suffix: 'child',
          sessionId: root.sessionId,
          parentAgentId: root.agentId,
        );
        final port = _Transport()
          ..seedThread(root)
          ..seedThread(child);
        final client = _client(port);
        expect(
          await client.threadCommands.renameThread(child.threadId, 'No'),
          isNull,
        );
        await client.threadCommands.archiveThread(child.threadId);
        expect(port.renames, isEmpty);
        expect(port.archives, isEmpty);
        expect(child.parentAgentId, root.agentId);
        expect(root.sessionId, isNot(root.threadId));
        expect(root.agentId, isNot(root.threadId));
      },
    );
  }
}
