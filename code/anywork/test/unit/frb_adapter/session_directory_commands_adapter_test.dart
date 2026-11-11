import 'package:anywork/src/infrastructure/frb/studio_api.dart';
import 'package:anywork/src/rust/api/studio/types/command.dart' as c;
import 'package:anywork/src/rust/api/studio/types/delegation.dart' as d;
import 'package:anywork/src/rust/api/studio/types/response.dart' as r;
import 'package:anywork/src/rust/api/studio/types/session_directory.dart' as b;
import 'package:anywork/src/rust/api/studio/types/thread_stream.dart' as t;
import 'package:anywork/src/rust/frb_generated.dart' show RustLib, RustLibApi;
import 'package:anywork_client/studio_client.dart';
import 'package:flutter_test/flutter_test.dart';

b.BridgeSessionDirectoryRow _row({bool native = false, String? parent}) =>
    b.BridgeSessionDirectoryRow(
      sessionId: 'session',
      agentId: 'agent',
      parentAgentId: parent,
      threadId: 'thread',
      workspaceId: 'workspace',
      title: 'directory title',
      mode: native && parent == null ? 'mode.simple' : null,
      delegationMode: d.BridgeDelegationMode.profile,
      delegationPreference: d.BridgeDelegationPreference.economy,
      workspaceMode: 'worktree',
      workspacePath: '/worktree',
      role: 'profile',
      backend: native
          ? const b.BridgeAgentBackend.native(
              config: b.BridgeNativeAgentConfig(
                systemInstructions: 'instructions',
              ),
              status: t.BridgeThreadStatus.running,
            )
          : const b.BridgeAgentBackend.acp(
              reference: b.BridgeAcpSessionReference(
                accountId: 'acp-account',
                acpSessionId: 'remote-session',
                cwd: '/remote',
              ),
            ),
      createdAt: 1,
      updatedAt: 3,
      lastUserMessageAt: 2,
      archived: false,
    );
c.BridgeStudioCommandReceipt _receipt(String id) =>
    c.BridgeStudioCommandReceipt(
      operationId: id,
      disposition: c.BridgeCommandDisposition.applied,
      targets: [
        c.BridgeResourceStamp(
          resourceKey: 'directory',
          ownerEpoch: 'epoch',
          revision: BigInt.from(5),
        ),
      ],
      effect: c.BridgeCommandEffectPoint.immediate,
      effective: true,
      durable: true,
      requiresIdentityObservation: true,
    );

// Supplies generated replies only. The actual FrbStudioTransport must preserve
// the directory union instead of requiring or inventing Native thread fields.
final class _DirectoryApi implements RustLibApi {
  b.BridgeSessionDirectoryRow row = _row();
  bool nextRootPresent = true;
  bool deletePresent = true;
  final calls =
      <
        ({String command, String threadId, String? operationId, String? title})
      >[];

  @override
  Future<b.BridgeSessionDirectoryRow>
  crateApiStudioHandlersThreadRestoreThread({required String threadId}) async {
    calls.add((
      command: 'restore',
      threadId: threadId,
      operationId: null,
      title: null,
    ));
    return row;
  }

  @override
  Future<c.BridgeRenameThreadCommandReply>
  crateApiStudioHandlersThreadRenameThread({
    required String operationId,
    required String threadId,
    required String title,
  }) async {
    calls.add((
      command: 'rename',
      threadId: threadId,
      operationId: operationId,
      title: title,
    ));
    return c.BridgeRenameThreadCommandReply(
      thread: row,
      receipt: _receipt(operationId),
    );
  }

  @override
  Future<c.BridgeArchiveThreadCommandReply>
  crateApiStudioHandlersThreadArchiveThread({
    required String operationId,
    required String threadId,
  }) async {
    calls.add((
      command: 'archive',
      threadId: threadId,
      operationId: operationId,
      title: null,
    ));
    return c.BridgeArchiveThreadCommandReply(
      result: r.ArchiveThreadResult(
        archivedRootId: 'archived-root',
        removedThreadIds: const ['archived-root', 'archived-child'],
        nextRoot: nextRootPresent ? row : null,
      ),
      receipt: _receipt(operationId),
    );
  }

  @override
  Future<c.BridgeDeleteThreadCommandReply?>
  crateApiStudioHandlersThreadDeleteThread({
    required String operationId,
    required String threadId,
  }) async {
    calls.add((
      command: 'delete',
      threadId: threadId,
      operationId: operationId,
      title: null,
    ));
    return deletePresent
        ? c.BridgeDeleteThreadCommandReply(
            result: r.DeleteThreadResult(
              deletedRootId: 'deleted-root',
              deletedThreadIds: const ['deleted-root', 'deleted-child'],
              nextRoot: nextRootPresent ? row : null,
            ),
            receipt: _receipt(operationId),
          )
        : null;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('Unexpected ${invocation.memberName}');
}

void _expectAcpRow(SessionDirectoryRow value) {
  expect(value.sessionId, 'session');
  expect(value.agentId, 'agent');
  expect(value.threadId, 'thread');
  expect(value.parentAgentId, isNull);
  expect(value.workspaceId, 'workspace');
  expect(value.title, 'directory title');
  expect(value.mode, isNull, reason: 'ACP root has no Native mode default');
  expect(value.workspaceMode, ThreadWorkspaceMode.worktree);
  expect(value.workspacePath, '/worktree');
  expect(value.role, 'profile');
  expect(value.createdAt, DateTime.fromMillisecondsSinceEpoch(1000));
  expect(value.updatedAt, DateTime.fromMillisecondsSinceEpoch(3000));
  expect(value.lastUserMessageAt, DateTime.fromMillisecondsSinceEpoch(2000));
  expect(value.archived, false);
  final reference = (value.backend as AcpAgentBackendView).reference;
  expect(reference.accountId, 'acp-account');
  expect(reference.acpSessionId, 'remote-session');
  expect(reference.cwd, '/remote');
}

void main() {
  late _DirectoryApi api;
  late FrbStudioTransport transport;
  setUp(() {
    api = _DirectoryApi();
    RustLib.initMock(api: api);
    FrbStudioTransport.debugOverrideInitialization(() async {});
    transport = FrbStudioTransport();
  });
  tearDown(() {
    FrbStudioTransport.debugOverrideInitialization(null);
    RustLib.dispose();
  });

  test('restore/rename/archive/delete return ACP directory rows without Native projection', () async {
    _expectAcpRow(await transport.restoreThread('restored'));
    final renamed = await transport.renameThread(
      'renamed',
      'New title',
      operationId: const OperationId('rename-op'),
    );
    _expectAcpRow(renamed.thread);
    expect(renamed.receipt.operationId, const OperationId('rename-op'));
    expect(renamed.receipt.targets.single.revision, 5);
    final archived = await transport.archiveThread(
      'archived',
      operationId: const OperationId('archive-op'),
    );
    _expectAcpRow(archived.result.nextRoot!);
    expect(archived.result.archivedRootId, 'archived-root');
    expect(archived.result.removedThreadIds, [
      'archived-root',
      'archived-child',
    ]);
    expect(archived.receipt.operationId, const OperationId('archive-op'));
    final deleted = (await transport.deleteThread(
      'deleted',
      operationId: const OperationId('delete-op'),
    ))!;
    _expectAcpRow(deleted.result.nextRoot!);
    expect(deleted.result.deletedRootId, 'deleted-root');
    expect(deleted.result.deletedThreadIds, ['deleted-root', 'deleted-child']);
    expect(deleted.receipt.operationId, const OperationId('delete-op'));
    expect(api.calls, [
      (
        command: 'restore',
        threadId: 'restored',
        operationId: null,
        title: null,
      ),
      (
        command: 'rename',
        threadId: 'renamed',
        operationId: 'rename-op',
        title: 'New title',
      ),
      (
        command: 'archive',
        threadId: 'archived',
        operationId: 'archive-op',
        title: null,
      ),
      (
        command: 'delete',
        threadId: 'deleted',
        operationId: 'delete-op',
        title: null,
      ),
    ]);
  });

  test('missing next root and idempotent missing delete remain null', () async {
    api.nextRootPresent = false;
    expect(
      (await transport.archiveThread(
        'root',
        operationId: const OperationId('archive'),
      )).result.nextRoot,
      isNull,
    );
    expect(
      (await transport.deleteThread(
        'root',
        operationId: const OperationId('delete'),
      ))!.result.nextRoot,
      isNull,
    );
    api.deletePresent = false;
    expect(
      await transport.deleteThread(
        'missing',
        operationId: const OperationId('delete-missing'),
      ),
      isNull,
    );
  });

  test('existing directory mapper preserves Native root mode and never supplies a child default', () async {
    api.row = _row(native: true);
    final root = await transport.restoreThread('native-root');
    expect(root.mode, ThreadModeId.simple);
    expect(
      (root.backend as NativeAgentBackendView).status,
      ThreadStatusView.running,
    );
    expect(
      (root.backend as NativeAgentBackendView).config.systemInstructions,
      'instructions',
    );
    api.row = _row(native: true, parent: 'parent-agent');
    final child = (await transport.renameThread(
      'native-child',
      'Child',
      operationId: const OperationId('child-rename'),
    )).thread;
    expect(child.parentAgentId, 'parent-agent');
    expect(child.mode, isNull);
  });
}
