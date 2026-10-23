import 'package:anywork_client/conversation.dart';
import 'package:anywork_client/resources.dart';

import '../../../rust/api/studio/conversation/read/interaction.dart' as native;
import '../../../rust/api/studio/types/thread_stream.dart' as legacy;
import '../shared/exact_numbers.dart';
import '../shared/read_converters.dart';
import 'identity_converters.dart';

InteractionReadHeader interactionHeaderFromBridge(
  native.BridgeInteractionReadHeader value, {
  required ReadScopeIdentity expectedScope,
}) => InteractionReadHeader(
  scope: checkedReadScope(value.scope, expectedScope),
  interactionId: readTextFromBridge(value.interactionId),
  threadId: readTextFromBridge(value.threadId),
  turnId: readTextFromBridge(value.turnId),
  itemId: nullableReadText(value.itemId),
  toolId: nullableReadText(value.toolId),
  agentPath: nullableReadText(value.agentPath),
  revision: exactU64(value.revision, 'interaction revision'),
  purpose: switch (value.purpose) {
    native.BridgeInteractionReadPurpose_General() => const InteractionPurposeRead.general(),
    native.BridgeInteractionReadPurpose_PlanConfirmation(:final expectedRevision, :final operationId, :final argumentHash, :final planHash) =>
      InteractionPurposeRead.planConfirmation(
        expectedRevision: exactU64(expectedRevision, 'Plan confirmation revision'),
        operationId: readTextFromBridge(operationId),
        argumentHash: readTextFromBridge(argumentHash),
        planHash: readTextFromBridge(planHash),
      ),
  },
  continuation: value.continuation == null ? null : _continuation(value.continuation!),
  createdAt: exactI64(value.createdAt, 'interaction created Unix seconds'),
  updatedAt: exactI64(value.updatedAt, 'interaction updated Unix seconds'),
  content: switch (value.content) {
    native.BridgeInteractionReadContent_UserInput(:final questionCount) =>
      InteractionContentRead.userInput(questionCount: exactU64(questionCount, 'question count')),
    native.BridgeInteractionReadContent_ToolApproval(:final name, :final arguments, :final workingDirectory, :final parentAgentId) =>
      InteractionContentRead.toolApproval(name: readTextFromBridge(name), arguments: readTextFromBridge(arguments), workingDirectory: nullableReadText(workingDirectory), parentAgentId: nullableReadText(parentAgentId)),
  },
  state: switch (value.state) {
    native.BridgeInteractionReadState_Pending(:final operationId) =>
      InteractionStateRead.pending(operationId: readTextFromBridge(operationId)),
    native.BridgeInteractionReadState_UserInputResolved(:final operationId, :final resolvedAt, :final answerEntryCount) =>
      InteractionStateRead.userInputResolved(operationId: readTextFromBridge(operationId), resolvedAt: exactI64(resolvedAt, 'interaction resolved Unix seconds'), answerEntryCount: exactU64(answerEntryCount, 'answer entry count')),
    native.BridgeInteractionReadState_ApprovalResolved(:final operationId, :final resolvedAt, :final decision, :final reason) =>
      InteractionStateRead.approvalResolved(operationId: readTextFromBridge(operationId), resolvedAt: exactI64(resolvedAt, 'approval resolved Unix seconds'), decision: switch (decision) {
        legacy.BridgeToolApprovalResolution.approved => ToolApprovalDecision.approved,
        legacy.BridgeToolApprovalResolution.denied => ToolApprovalDecision.denied,
      }, reason: nullableReadText(reason)),
    native.BridgeInteractionReadState_Cancelled(:final operationId, :final cancelledAt, :final reason) =>
      InteractionStateRead.cancelled(operationId: readTextFromBridge(operationId), cancelledAt: exactI64(cancelledAt, 'interaction cancelled Unix seconds'), reason: readTextFromBridge(reason)),
    native.BridgeInteractionReadState_Expired(:final operationId, :final expiredAt) =>
      InteractionStateRead.expired(operationId: readTextFromBridge(operationId), expiredAt: exactI64(expiredAt, 'interaction expired Unix seconds')),
  },
);

InteractionContinuationRead _continuation(native.BridgeInteractionReadContinuation value) => switch (value) {
  native.BridgeInteractionReadContinuation_Resolution(:final presentation) =>
    InteractionContinuationRead.resolution(presentation: _presentation(presentation)),
  native.BridgeInteractionReadContinuation_Question(:final questionId, :final presentation) =>
    InteractionContinuationRead.question(questionId: readTextFromBridge(questionId), presentation: _presentation(presentation)),
};

InteractionPresentation _presentation(native.BridgeInteractionPresentation value) => switch (value) {
  native.BridgeInteractionPresentation.visible => InteractionPresentation.visible,
  native.BridgeInteractionPresentation.hidden => InteractionPresentation.hidden,
};

QuestionPage questionPageFromBridge(native.BridgeQuestionPage value, {required ReadScopeIdentity expectedScope}) => QuestionPage(
  scope: checkedReadScope(value.scope, expectedScope),
  offset: exactU64(value.offset, 'question page offset'),
  total: exactU64(value.total, 'question page total'),
  items: List.unmodifiable([
    for (final item in value.items) QuestionReadItem(
      index: exactU64(item.index, 'question index'),
      id: readTextFromBridge(item.id),
      header: readTextFromBridge(item.header),
      question: readTextFromBridge(item.question),
      isOther: item.isOther,
      isSecret: item.isSecret,
      optionsCount: nullableU64(item.optionsCount, 'question options count'),
    ),
  ]),
  nextOffset: nullableU64(value.nextOffset, 'next question page offset'),
);

OptionPage optionPageFromBridge(native.BridgeOptionPage value, {required ReadScopeIdentity expectedScope}) => OptionPage(
  scope: checkedReadScope(value.scope, expectedScope),
  offset: exactU64(value.offset, 'option page offset'),
  total: exactU64(value.total, 'option page total'),
  items: List.unmodifiable([
    for (final item in value.items) OptionReadItem(
      index: exactU64(item.index, 'option index'), label: readTextFromBridge(item.label), description: readTextFromBridge(item.description),
    ),
  ]),
  nextOffset: nullableU64(value.nextOffset, 'next option page offset'),
);

AnswerEntryPage answerEntryPageFromBridge(native.BridgeAnswerEntryPage value, {required ReadScopeIdentity expectedScope}) => AnswerEntryPage(
  scope: checkedReadScope(value.scope, expectedScope),
  offset: exactU64(value.offset, 'answer entry page offset'),
  total: exactU64(value.total, 'answer entry page total'),
  items: List.unmodifiable([
    for (final item in value.items) AnswerEntryReadItem(
      index: exactU64(item.index, 'answer entry index'), questionId: readTextFromBridge(item.questionId), answerCount: exactU64(item.answerCount, 'answer count'),
    ),
  ]),
  nextOffset: nullableU64(value.nextOffset, 'next answer entry page offset'),
);

AnswerValuePage answerValuePageFromBridge(native.BridgeAnswerValuePage value, {required ReadScopeIdentity expectedScope}) => AnswerValuePage(
  scope: checkedReadScope(value.scope, expectedScope),
  offset: exactU64(value.offset, 'answer value page offset'),
  total: exactU64(value.total, 'answer value page total'),
  items: List.unmodifiable([
    for (final item in value.items) AnswerValueReadItem(index: exactU64(item.index, 'answer value index'), value: readTextFromBridge(item.value)),
  ]),
  nextOffset: nullableU64(value.nextOffset, 'next answer value page offset'),
);
