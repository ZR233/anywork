import 'package:anywork_client/conversation.dart';

import '../../../rust/api/studio/types/thread_stream.dart' as native;
import '../shared/exact_numbers.dart';

native.BridgeInteractionResolution interactionResolutionToBridge(
  InteractionResolutionCommand value,
) => switch (value) {
  UserInputResolutionCommand(:final answers) =>
    native.BridgeInteractionResolution.userInput(
      answers: List.unmodifiable([
        for (final answer in answers)
          native.BridgeUserInputAnswer(
            questionId: answer.questionId,
            answers: List.unmodifiable(answer.answers),
          ),
      ]),
    ),
  ToolApprovalResolutionCommand(:final decision, :final reason) =>
    native.BridgeInteractionResolution.toolApproval(
      decision: switch (decision) {
        ToolApprovalDecision.approved =>
          native.BridgeToolApprovalResolution.approved,
        ToolApprovalDecision.denied =>
          native.BridgeToolApprovalResolution.denied,
      },
      reason: reason,
    ),
};

InteractionSnapshot commandInteractionFromBridge(
  native.BridgeInteractionRequest value,
) => InteractionSnapshot(
  interactionId: value.interactionId,
  scope: InteractionScope(
    threadId: value.scope.threadId,
    turnId: value.scope.turnId,
    itemId: value.scope.itemId,
    toolId: value.scope.toolId,
    agentPath: value.scope.agentPath,
  ),
  revision: exactU64(value.revision, 'command interaction revision'),
  content: switch (value.content) {
    native.BridgeInteractionContent_UserInput(:final questions, :final state) =>
      UserInputInteractionContent(
        questions: [
          for (final question in questions)
            InteractionQuestion(
              id: question.id,
              header: question.header,
              question: question.question,
              isOther: question.isOther,
              isSecret: question.isSecret,
              options: question.options == null
                  ? null
                  : [
                      for (final option in question.options!)
                        UserQuestionOptionView(
                          label: option.label,
                          description: option.description,
                        ),
                    ],
            ),
        ],
        state: commandUserInputStateFromBridge(state),
      ),
    native.BridgeInteractionContent_ToolApproval(
      :final name,
      :final argumentsJson,
      :final workingDirectory,
      :final parentAgentId,
      :final state,
    ) =>
      ToolApprovalInteractionContent(
        name: name,
        arguments: argumentsJson,
        workingDirectory: workingDirectory,
        parentAgentId: parentAgentId,
        state: commandApprovalStateFromBridge(state),
      ),
  },
  createdAt: exactI64(
    BigInt.from(value.createdAt),
    'command interaction created Unix seconds',
  ),
  updatedAt: exactI64(
    BigInt.from(value.updatedAt),
    'command interaction updated Unix seconds',
  ),
);

UserInputInteractionState commandUserInputStateFromBridge(
  native.BridgeUserInputInteractionState value,
) => switch (value) {
  native.BridgeUserInputInteractionState_Pending(:final operationId) =>
    UserInputInteractionState.pending(operationId: operationId),
  native.BridgeUserInputInteractionState_Resolved(
    :final operationId,
    :final resolvedAt,
    :final answers,
  ) =>
    ResolvedUserInputInteraction(
      operationId: operationId,
      resolvedAt: exactI64(
        BigInt.from(resolvedAt),
        'command interaction resolved Unix seconds',
      ),
      answers: [
        for (final answer in answers)
          UserInputAnswerCommand(
            questionId: answer.questionId,
            answers: answer.answers,
          ),
      ],
    ),
  native.BridgeUserInputInteractionState_Cancelled(
    :final operationId,
    :final cancelledAt,
    :final reason,
  ) =>
    UserInputInteractionState.cancelled(
      operationId: operationId,
      cancelledAt: exactI64(
        BigInt.from(cancelledAt),
        'command interaction cancelled Unix seconds',
      ),
      reason: reason,
    ),
  native.BridgeUserInputInteractionState_Expired(
    :final operationId,
    :final expiredAt,
  ) =>
    UserInputInteractionState.expired(
      operationId: operationId,
      expiredAt: exactI64(
        BigInt.from(expiredAt),
        'command interaction expired Unix seconds',
      ),
    ),
};

ToolApprovalInteractionState commandApprovalStateFromBridge(
  native.BridgeToolApprovalInteractionState value,
) => switch (value) {
  native.BridgeToolApprovalInteractionState_Pending(:final operationId) =>
    ToolApprovalInteractionState.pending(operationId: operationId),
  native.BridgeToolApprovalInteractionState_Resolved(
    :final operationId,
    :final resolvedAt,
    :final decision,
    :final reason,
  ) =>
    ToolApprovalInteractionState.resolved(
      operationId: operationId,
      resolvedAt: exactI64(
        BigInt.from(resolvedAt),
        'command approval resolved Unix seconds',
      ),
      decision: switch (decision) {
        native.BridgeToolApprovalResolution.approved =>
          ToolApprovalDecision.approved,
        native.BridgeToolApprovalResolution.denied =>
          ToolApprovalDecision.denied,
      },
      reason: reason,
    ),
  native.BridgeToolApprovalInteractionState_Cancelled(
    :final operationId,
    :final cancelledAt,
    :final reason,
  ) =>
    ToolApprovalInteractionState.cancelled(
      operationId: operationId,
      cancelledAt: exactI64(
        BigInt.from(cancelledAt),
        'command approval cancelled Unix seconds',
      ),
      reason: reason,
    ),
  native.BridgeToolApprovalInteractionState_Expired(
    :final operationId,
    :final expiredAt,
  ) =>
    ToolApprovalInteractionState.expired(
      operationId: operationId,
      expiredAt: exactI64(
        BigInt.from(expiredAt),
        'command approval expired Unix seconds',
      ),
    ),
};
