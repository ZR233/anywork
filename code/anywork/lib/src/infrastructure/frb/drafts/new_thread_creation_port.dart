import 'dart:async';

import 'package:anywork_client/conversation_ports.dart';
import 'package:anywork_client/drafts.dart';
import 'package:anywork_client/drafts_ports.dart';
import 'package:anywork_client/operations_ports.dart';
import 'package:anywork_client/resources_ports.dart';

import '../../../rust/api/studio/draft_commands/commands.dart' as commands;
import '../../../rust/api/studio/draft_commands/handles.dart' as native;
import '../../../rust/api/studio/draft_commands/types.dart' as wire;
import '../../../rust/api/studio/types/thread_preparation.dart' as preparation;
import '../conversation/execution_connection.dart';
import '../conversation/identity_converters.dart' show feedIdentityFromBridge;
import '../conversation/input_converters.dart' show submitReceiptFromBridge;
import '../shared/adapter_failure.dart';
import '../shared/close_converters.dart';
import '../shared/exact_numbers.dart';
import '../shared/resource_owner.dart';
import 'draft_command_failures.dart';
import 'draft_command_values.dart';

part 'thread_creation_job.dart';
part 'creation_progress.dart';
part 'created_input_execution_source.dart';

/// The actual native creation leaf. No application composition, generic
/// ConversationObservationPort or substitute live/cold execution opener.
final class FrbNewThreadCreationPort implements NewThreadCreationPort {
  const FrbNewThreadCreationPort();

  @override
  Future<NewThreadCreation> begin(
    OperationId id,
    NewThreadCreationRequest request,
  ) {
    final preparation.BridgeStartNewThreadRequest frozen;
    try {
      frozen = creationRequestToBridge(request);
    } on Object catch (error, stack) {
      Error.throwWithStackTrace(
        CommandDispatchFailure.rejected(failure: draftCommandFailure(error)),
        stack,
      );
    }
    final creation = _FrbThreadCreation(
      id,
      projectId: request.projectId,
      inputId: request.input.inputId,
      isBegin: true,
      open: () =>
          commands.beginThreadCreation(operationId: id.value, request: frozen),
    );
    return creation.opened.then((_) => creation);
  }

  @override
  Future<NewThreadCreation?> find(OperationId id) {
    final creation = _FrbThreadCreation(
      id,
      open: () => commands.findThreadCreation(operationId: id.value),
    );
    return creation.opened.then((found) => found ? creation : null);
  }
}
