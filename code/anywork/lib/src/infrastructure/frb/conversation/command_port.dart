import 'package:anywork_client/conversation_ports.dart';
import 'package:anywork_client/drafts.dart';
import 'package:anywork_client/operations_ports.dart';
import 'package:anywork_client/resources.dart';

import '../../../rust/api/studio/conversation/commands.dart' as native;
import '../../../rust/api/studio/handlers/prompt.dart' as queries;
import '../../../rust/api/studio/handlers/thread.dart' as threads;
import '../../../rust/api/studio/types/attachment.dart' as attachment;
import '../../../rust/api/studio/types/command.dart' as command;
import '../../../rust/api/studio/types/error.dart' as errors;
import '../../../rust/api/studio/types/thread_stream.dart' as stream;
import '../shared/adapter_failure.dart';
import '../shared/bridge_failure.dart';
import '../shared/exact_numbers.dart';
import '../shared/receipt_converters.dart';
import 'command_interaction_converters.dart';
import 'command_runtime_converters.dart';
import 'command_settings_converters.dart';
import 'input_converters.dart';

part 'thread_commands.dart';

/// Frozen command/query transport only. Drafts, permits, accepted work and
/// input evidence observation remain owned by their SDK repositories.
final class FrbConversationCommandPort
    with _ThreadCommands
    implements ConversationCommandPort {
  FrbConversationCommandPort();

  // This associates an unusable native success with the very domain failure
  // retained by its original operation owner. It contains only completed reply
  // evidence/cause, never a handle, task or cleanup responsibility. GC is not
  // used to prove cancellation/join or to release a resource permit.
  final _unusableReplies = Expando<_UnusableSubmitReply>(
    'native-submit-evidence',
  );
  final _unusableInterruptReplies = Expando<_UnusableInterruptReply>(
    'native-interrupt-evidence',
  );

  @override
  Future<InterruptTurnReply> interruptTurn(
    String threadId,
    String turnId, {
    required OperationId operationId,
  }) async {
    final command.BridgeInterruptTurnCommandReply reply;
    try {
      reply = await queries.interruptTurn(
        operationId: operationId.value,
        threadId: threadId,
        turnId: turnId,
      );
    } on Object catch (error, stack) {
      // Even InvalidArgument can follow partial cancellation in the mailbox.
      // A transport error provides no typed proof that the call was rejected.
      Error.throwWithStackTrace(
        CommandDispatchFailure.unknownOutcome(
          failure: _interruptFailure(error),
        ),
        stack,
      );
    }
    CommitReceipt? receipt;
    try {
      receipt = commitReceiptFromBridge(reply.receipt);
      return InterruptTurnReply(
        threadId: reply.threadId,
        turnId: reply.turnId,
        interrupted: reply.interrupted,
        receipt: receipt,
      );
    } on Object catch (error, stack) {
      final failure = _interruptFailure(error);
      _unusableInterruptReplies[failure] = _UnusableInterruptReply(
        reply,
        error,
        stack,
      );
      if (receipt != null &&
          receipt.operationId == operationId &&
          reply.threadId == threadId &&
          reply.turnId == turnId) {
        // The SDK still checks the original receipt's full effect/observation contract.
        Error.throwWithStackTrace(
          CommandDispatchFailure.committedButUnobserved(
            receipt: receipt,
            failure: failure,
          ),
          stack,
        );
      }
      Error.throwWithStackTrace(
        CommandDispatchFailure.confirmedWithoutUsableReceipt(failure: failure),
        stack,
      );
    }
  }

  @override
  Future<SubmitPromptReceipt> submitPrompt(
    String threadId,
    StudioPromptInput input, {
    required int expectedModelRouteRevision,
  }) {
    final attachment.BridgeStudioPromptInput request;
    final BigInt routeRevision;
    try {
      routeRevision = nativeU64(
        expectedModelRouteRevision,
        'expected model route revision',
      );
      request = attachment.BridgeStudioPromptInput(
        inputId: input.inputId,
        text: input.text,
        attachmentDraftIds: List<String>.unmodifiable(input.attachmentDraftIds),
      );
    } on Object catch (error) {
      // Conversion/admission failed before the native call was invoked.
      throw CommandDispatchFailure.rejected(failure: _failure(error));
    }
    return _submit(threadId, request, routeRevision);
  }

  Future<SubmitPromptReceipt> _submit(
    String threadId,
    attachment.BridgeStudioPromptInput request,
    BigInt routeRevision,
  ) async {
    final native.BridgeSubmitPromptOutcome outcome;
    try {
      outcome = await native.submitPrompt(
        threadId: threadId,
        input: request,
        expectedModelRouteRevision: routeRevision,
      );
    } on Object catch (error, stack) {
      // Native invocation may have dispatched. Neither code nor retryability
      // proves a negative result when the typed outcome itself did not arrive.
      Error.throwWithStackTrace(
        CommandDispatchFailure.unknownOutcome(failure: _failure(error)),
        stack,
      );
    }
    switch (outcome) {
      case native.BridgeSubmitPromptOutcome_Returned(:final value):
        try {
          final receipt = submitReceiptFromBridge(value);
          if (receipt.threadId != threadId ||
              receipt.inputId != request.inputId) {
            throw adapterProtocol('submit-reply-target');
          }
          return receipt;
        } on Object catch (error, stack) {
          _confirmedWithoutUsable(outcome, error, stack);
        }
      case native.BridgeSubmitPromptOutcome_Rejected(:final error):
        throw CommandDispatchFailure.rejected(failure: _failure(error));
      case native.BridgeSubmitPromptOutcome_UnknownOutcome(:final error):
        throw CommandDispatchFailure.unknownOutcome(failure: _failure(error));
      case native.BridgeSubmitPromptOutcome_CommittedButUnobserved(
        :final receipt,
        :final error,
      ):
        final CommitReceipt mappedReceipt;
        try {
          mappedReceipt = commitReceiptFromBridge(receipt);
        } on Object catch (mappingError, stack) {
          _confirmedWithoutUsable(outcome, mappingError, stack);
        }
        throw CommandDispatchFailure.committedButUnobserved(
          receipt: mappedReceipt,
          failure: _failure(error),
        );
      case native.BridgeSubmitPromptOutcome_ConfirmedWithoutReceipt(
        :final error,
      ):
        throw CommandDispatchFailure.confirmedWithoutUsableReceipt(
          failure: _failure(error),
        );
    }
  }

  Never _confirmedWithoutUsable(
    native.BridgeSubmitPromptOutcome outcome,
    Object error,
    StackTrace stack,
  ) {
    final failure = _failure(error);
    _unusableReplies[failure] = _UnusableSubmitReply(outcome, error, stack);
    Error.throwWithStackTrace(
      CommandDispatchFailure.confirmedWithoutUsableReceipt(failure: failure),
      stack,
    );
  }

  @override
  Future<InputAcceptanceEvidence?> readInputAcceptance(
    String threadId,
    String inputId,
  ) => bridgeQuery(() async {
    final evidence = await queries.readInputAcceptance(
      threadId: threadId,
      inputId: inputId,
    );
    return evidence == null ? null : inputAcceptanceFromBridge(evidence);
  });
}

StudioFailure _failure(Object error) {
  try {
    return bridgeFailure(error);
  } on Object catch (mappingError) {
    return adapterFailure(mappingError, operation: 'submit-error-conversion');
  }
}

final class _UnusableSubmitReply {
  _UnusableSubmitReply(this.outcome, this.cause, this.stack);
  final native.BridgeSubmitPromptOutcome outcome;
  final Object cause;
  final StackTrace stack;
}

StudioFailure _interruptFailure(Object error) {
  try {
    return bridgeFailure(error);
  } on Object catch (mappingError) {
    return adapterFailure(
      mappingError,
      operation: 'interrupt-error-conversion',
    );
  }
}

final class _UnusableInterruptReply {
  _UnusableInterruptReply(this.reply, this.cause, this.stack);
  final command.BridgeInterruptTurnCommandReply reply;
  final Object cause;
  final StackTrace stack;
}
