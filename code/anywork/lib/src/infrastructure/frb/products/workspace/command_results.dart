import 'package:anywork_client/operations_ports.dart';
import 'package:anywork_client/resources.dart';
import 'package:anywork_client/workspace_ports.dart';

import '../../../../rust/api/studio/types/command.dart' as native;
import '../../../../rust/api/studio/types/response.dart' as response;
import '../../drafts/draft_command_values.dart' show createdThreadFromBridge;
import '../../shared/adapter_failure.dart';
import '../../shared/bridge_failure.dart';
import '../../shared/receipt_converters.dart';

StudioFailure workspaceCommandFailure(Object error) {
  if (error case CommandDispatchFailure(:final failure)) return failure;
  try {
    return bridgeFailure(error);
  } on Object catch (mappingError) {
    return adapterFailure(mappingError, operation: 'workspace-command-error');
  }
}

/// Invocation cannot infer rejection from a BridgeError. A returned native
/// value is stronger evidence, retained separately from a failed conversion.
Future<T> invokeWorkspaceCommand<N, T>(
  Future<N> Function() invoke,
  T Function(N) convert,
) async {
  final N value;
  try {
    value = await invoke();
  } on Object catch (error, stack) {
    Error.throwWithStackTrace(
      CommandDispatchFailure.unknownOutcome(
        failure: workspaceCommandFailure(error),
      ),
      stack,
    );
  }
  try {
    return convert(value);
  } on CommandDispatchFailure {
    rethrow;
  } on Object catch (error, stack) {
    Error.throwWithStackTrace(
      CommandDispatchFailure.confirmedWithoutUsableReceipt(
        failure: workspaceCommandFailure(error),
      ),
      stack,
    );
  }
}

CommitReceipt _receipt(
  native.BridgeStudioCommandReceipt value,
  OperationId operation,
) {
  try {
    if (operation.value.isEmpty || value.operationId != operation.value) {
      throw adapterProtocol('workspace-command-operation');
    }
    final receipt = commitReceiptFromBridge(value);
    if (receipt.requiresIdentityObservation) {
      throw adapterProtocol('workspace-command-receipt');
    }
    if (receipt.targets
        case [ResourceStamp(:final resourceKey, :final ownerEpoch)]
        when resourceKey == 'thread-directory' && ownerEpoch.isNotEmpty) {
      return receipt;
    }
    throw adapterProtocol('workspace-command-target');
  } on Object catch (error, stack) {
    Error.throwWithStackTrace(
      CommandDispatchFailure.confirmedWithoutUsableReceipt(
        failure: workspaceCommandFailure(error),
      ),
      stack,
    );
  }
}

RenameThreadCommandReply renameThreadReplyFromBridge(
  native.BridgeRenameThreadCommandReply value,
  String threadId,
  OperationId operation,
) {
  final receipt = _receipt(value.receipt, operation);
  try {
    final thread = createdThreadFromBridge(value.thread);
    if (thread.id != threadId) {
      throw adapterProtocol('workspace-rename-thread-target');
    }
    return RenameThreadCommandReply(thread: thread, receipt: receipt);
  } on Object catch (error, stack) {
    Error.throwWithStackTrace(
      CommandDispatchFailure.committedButUnobserved(
        receipt: receipt,
        failure: workspaceCommandFailure(error),
      ),
      stack,
    );
  }
}

ArchiveThreadCommandReply archiveThreadReplyFromBridge(
  native.BridgeArchiveThreadCommandReply value,
  String threadId,
  OperationId operation,
) {
  final receipt = _receipt(value.receipt, operation);
  try {
    final result = _archiveResult(value.result);
    if (result.archivedRootId != threadId ||
        !result.removedThreadIds.contains(threadId)) {
      throw adapterProtocol('workspace-archive-thread-target');
    }
    return ArchiveThreadCommandReply(result: result, receipt: receipt);
  } on Object catch (error, stack) {
    Error.throwWithStackTrace(
      CommandDispatchFailure.committedButUnobserved(
        receipt: receipt,
        failure: workspaceCommandFailure(error),
      ),
      stack,
    );
  }
}

ArchiveThreadResult _archiveResult(response.ArchiveThreadResult value) =>
    ArchiveThreadResult(
      archivedRootId: value.archivedRootId,
      removedThreadIds: List<String>.unmodifiable(value.removedThreadIds),
      nextRoot: value.nextRoot == null
          ? null
          : createdThreadFromBridge(value.nextRoot!),
    );
