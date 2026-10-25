import 'package:anywork_client/operations.dart';
import 'package:anywork_client/resources_ports.dart';

import '../domain/directory_values.dart';
import 'workspace_access.dart';
import 'workspace_commands.dart';
import 'workspace_directories.dart';

/// Canonical values still enter through directory feeds, never command replies.
final class WorkspaceMutations {
  WorkspaceMutations(this.directories, this.commands, this.access);
  final WorkspaceDirectories directories;
  final WorkspaceCommands commands;
  final WorkspaceAccess access;

  OperationTicket<ProjectRecord> renameProject(
    String id,
    String raw,
  ) => commands.run(
    label: 'workspace-rename-project',
    key: (kind: WorkspaceWriteKind.project, id: id, path: null),
    action: (scope) async {
      // Native owns trim/Unicode-length validation and returns canonical text.
      access.project(id);
      final value = await scope.invoke(
        () => directories.port.renameProject(id, raw),
      );
      scope.confirm();
      if (value.id != id)
        throw resourceProtocol('Project rename returned another target.');
      scope.confirm(value: value);
      return value;
    },
  );

  OperationTicket<WorkspaceThreadRecord> renameThread(String id, String raw) =>
      commands.run(
        label: 'workspace-rename-thread',
        key: (kind: WorkspaceWriteKind.thread, id: id, path: null),
        action: (scope) async {
          return await directories.withThread(id, (owner, original) async {
            if (!original.isRoot || original.archived)
              throw const StudioFailure(
                code: StudioFailureCode.invalidArgument,
                message: 'Only an unarchived root Thread can be renamed.',
                retryable: false,
                correlationId: 'workspace',
              );
            access.thread(id);
            final epoch = owner.mirror.current?.origin.ownerEpoch;
            if (epoch == null)
              throw const StudioFailure(
                code: StudioFailureCode.unavailable,
                message: 'The original Thread directory source is unavailable.',
                retryable: true,
                correlationId: 'workspace',
              );
            final reply = await scope.invoke(
              () => directories.port.renameThread(
                id,
                raw,
                operationId: scope.operationId,
              ),
            );
            scope.confirm();
            if (reply.thread.id != id ||
                reply.thread.projectId != original.projectId)
              throw resourceProtocol('Thread rename returned another target.');
            scope.confirm(value: reply.thread, receipt: reply.receipt);
            final targets = reply.receipt.targets;
            if (targets.length != 1 ||
                targets.single is! ResourceStamp ||
                reply.receipt.requiresIdentityObservation) {
              throw resourceProtocol(
                'Thread rename has an unexpected observation contract.',
              );
            }
            final target = targets.single as ResourceStamp;
            if (target.resourceKey != 'thread-directory' ||
                target.ownerEpoch != epoch ||
                target.revision < 0) {
              throw resourceProtocol(
                'Thread rename receipt belongs to another directory source.',
              );
            }
            await owner.mirror.source.waitFor((state) {
              owner.lifetime.admit();
              if (state.projection.sync.phase == ResourceSyncPhase.failed)
                throw state.projection.sync.error!;
              final stamp = state.projection.stamp;
              if (stamp != null && stamp.ownerEpoch != epoch)
                throw const StudioFailure(
                  code: StudioFailureCode.superseded,
                  message: 'The original rename directory owner was replaced.',
                  retryable: true,
                  correlationId: 'workspace',
                );
              final revision = state.projection.header?.directoryRevision;
              return state.projection.sync.phase == ResourceSyncPhase.ready &&
                  revision != null &&
                  revision >= target.revision;
            });
            return reply.thread;
          });
        },
      );
}
