import 'package:freezed_annotation/freezed_annotation.dart';

import '../../../resources.dart';
import 'execution_values.dart';

part 'interaction_values.freezed.dart';

enum InteractionPresentation { visible, hidden }
enum ToolApprovalDecision { approved, denied }

@Freezed(toStringOverride: false)
sealed class InteractionPurposeRead with _$InteractionPurposeRead {
  const factory InteractionPurposeRead.general() = GeneralInteractionPurposeRead;
  const factory InteractionPurposeRead.planConfirmation({required int expectedRevision, required ReadText operationId, required ReadText argumentHash, required ReadText planHash}) = PlanConfirmationPurposeRead;
}

@Freezed(toStringOverride: false)
sealed class InteractionContinuationRead with _$InteractionContinuationRead {
  const factory InteractionContinuationRead.resolution({required InteractionPresentation presentation}) = ResolutionContinuationRead;
  const factory InteractionContinuationRead.question({required ReadText questionId, required InteractionPresentation presentation}) = QuestionContinuationRead;
}

@Freezed(toStringOverride: false)
sealed class InteractionContentRead with _$InteractionContentRead {
  const factory InteractionContentRead.userInput({required int questionCount}) = UserInputContentRead;
  const factory InteractionContentRead.toolApproval({required ReadText name, required ReadText arguments, required ReadText? workingDirectory, required ReadText? parentAgentId}) = ToolApprovalContentRead;
}

@Freezed(toStringOverride: false)
sealed class InteractionStateRead with _$InteractionStateRead {
  const factory InteractionStateRead.pending({required ReadText operationId}) = PendingInteractionRead;
  const factory InteractionStateRead.userInputResolved({required ReadText operationId, required int resolvedAt, required int answerEntryCount}) = ResolvedUserInputRead;
  const factory InteractionStateRead.approvalResolved({required ReadText operationId, required int resolvedAt, required ToolApprovalDecision decision, required ReadText? reason}) = ResolvedApprovalRead;
  const factory InteractionStateRead.cancelled({required ReadText operationId, required int cancelledAt, required ReadText reason}) = CancelledInteractionRead;
  const factory InteractionStateRead.expired({required ReadText operationId, required int expiredAt}) = ExpiredInteractionRead;
}

@Freezed(toStringOverride: false)
abstract class InteractionReadHeader with _$InteractionReadHeader {
  const factory InteractionReadHeader({
    required ReadScopeIdentity scope,
    required ReadText interactionId,
    required ReadText threadId,
    required ReadText turnId,
    required ReadText? itemId,
    required ReadText? toolId,
    required ReadText? agentPath,
    required int revision,
    required InteractionPurposeRead purpose,
    required InteractionContinuationRead? continuation,
    required int createdAt,
    required int updatedAt,
    required InteractionContentRead content,
    required InteractionStateRead state,
  }) = _InteractionReadHeader;
}

@Freezed(toStringOverride: false)
abstract class QuestionReadItem with _$QuestionReadItem {
  const factory QuestionReadItem({
    required int index,
    required ReadText id,
    required ReadText header,
    required ReadText question,
    required bool isOther,
    required bool isSecret,
    required int? optionsCount,
  }) = _QuestionReadItem;
}

@Freezed(toStringOverride: false)
abstract class OptionReadItem with _$OptionReadItem {
  const factory OptionReadItem({required int index, required ReadText label, required ReadText description}) = _OptionReadItem;
}

@Freezed(toStringOverride: false)
abstract class AnswerEntryReadItem with _$AnswerEntryReadItem {
  const factory AnswerEntryReadItem({required int index, required ReadText questionId, required int answerCount}) = _AnswerEntryReadItem;
}

@Freezed(toStringOverride: false)
abstract class AnswerValueReadItem with _$AnswerValueReadItem {
  const factory AnswerValueReadItem({required int index, required ReadText value}) = _AnswerValueReadItem;
}

@Freezed(toStringOverride: false)
final class QuestionPage with _$QuestionPage {
  QuestionPage({required this.scope, required this.offset, required this.total,
    required List<QuestionReadItem> items, required this.nextOffset})
      : items = List.unmodifiable(items);
  final ReadScopeIdentity scope;
  final int offset;
  final int total;
  final List<QuestionReadItem> items;
  final int? nextOffset;
}

@Freezed(toStringOverride: false)
final class OptionPage with _$OptionPage {
  OptionPage({required this.scope, required this.offset, required this.total,
    required List<OptionReadItem> items, required this.nextOffset})
      : items = List.unmodifiable(items);
  final ReadScopeIdentity scope;
  final int offset;
  final int total;
  final List<OptionReadItem> items;
  final int? nextOffset;
}

@Freezed(toStringOverride: false)
final class AnswerEntryPage with _$AnswerEntryPage {
  AnswerEntryPage({required this.scope, required this.offset, required this.total,
    required List<AnswerEntryReadItem> items, required this.nextOffset})
      : items = List.unmodifiable(items);
  final ReadScopeIdentity scope;
  final int offset;
  final int total;
  final List<AnswerEntryReadItem> items;
  final int? nextOffset;
}

@Freezed(toStringOverride: false)
final class AnswerValuePage with _$AnswerValuePage {
  AnswerValuePage({required this.scope, required this.offset, required this.total,
    required List<AnswerValueReadItem> items, required this.nextOffset})
      : items = List.unmodifiable(items);
  final ReadScopeIdentity scope;
  final int offset;
  final int total;
  final List<AnswerValueReadItem> items;
  final int? nextOffset;
}

@freezed
abstract class InteractionIndexReadHeader with _$InteractionIndexReadHeader {
  const factory InteractionIndexReadHeader({required ReadScopeIdentity scope, required int total, required int pending}) = _InteractionIndexReadHeader;
}

@freezed
final class InteractionBriefPage with _$InteractionBriefPage {
  InteractionBriefPage({required this.scope, required this.offset, required this.total,
    required List<InteractionBrief> items, required this.nextOffset})
      : items = List.unmodifiable(items);
  final ReadScopeIdentity scope;
  final int offset;
  final int total;
  final List<InteractionBrief> items;
  final int? nextOffset;
}

// Answers and approval reasons have no printable/JSON representation.
@Freezed(toStringOverride: false)
final class UserInputAnswerCommand with _$UserInputAnswerCommand {
  UserInputAnswerCommand({required this.questionId, required List<String> answers})
      : answers = List.unmodifiable(answers);
  final String questionId;
  final List<String> answers;
}

@Freezed(toStringOverride: false)
sealed class InteractionResolutionCommand with _$InteractionResolutionCommand {
  const InteractionResolutionCommand._();
  factory InteractionResolutionCommand.userInput({required List<UserInputAnswerCommand> answers}) = UserInputResolutionCommand;
  const factory InteractionResolutionCommand.toolApproval({required ToolApprovalDecision decision, required String? reason}) = ToolApprovalResolutionCommand;
}

@Freezed(toStringOverride: false)
final class UserInputResolutionCommand extends InteractionResolutionCommand with _$UserInputResolutionCommand {
  UserInputResolutionCommand({required List<UserInputAnswerCommand> answers})
      : answers = List.unmodifiable(answers), super._();
  final List<UserInputAnswerCommand> answers;
}
