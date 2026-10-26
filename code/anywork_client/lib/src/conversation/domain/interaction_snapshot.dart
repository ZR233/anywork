import 'package:freezed_annotation/freezed_annotation.dart';

import 'execution_values.dart';
import 'interaction_values.dart';
import 'thread_content_questions.dart' show UserQuestionOptionView;

part 'interaction_snapshot.freezed.dart';

@Freezed(toStringOverride: false)
final class InteractionSnapshot with _$InteractionSnapshot {
  const InteractionSnapshot({
    required this.interactionId,
    required this.scope,
    required this.revision,
    required this.content,
    required this.createdAt,
    required this.updatedAt,
  });
  final String interactionId;
  final InteractionScope scope;
  final int revision;
  final InteractionSnapshotContent content;
  final int createdAt;
  final int updatedAt;
}

/// Business identity, not a native ReadScopeIdentity or a resource handle.
@Freezed(toStringOverride: false)
final class InteractionScope with _$InteractionScope {
  const InteractionScope({
    required this.threadId,
    required this.turnId,
    required this.itemId,
    required this.toolId,
    required this.agentPath,
  });
  final String threadId;
  final String turnId;
  final String? itemId;
  final String? toolId;
  final String? agentPath;
}

@Freezed(toStringOverride: false)
sealed class InteractionSnapshotContent with _$InteractionSnapshotContent {
  const InteractionSnapshotContent._();
  InteractionStatus get status;
  factory InteractionSnapshotContent.userInput({
    required List<InteractionQuestion> questions,
    required UserInputInteractionState state,
  }) = UserInputInteractionContent;
  const factory InteractionSnapshotContent.toolApproval({
    required String name,
    required String arguments,
    required String? workingDirectory,
    required String? parentAgentId,
    required ToolApprovalInteractionState state,
  }) = ToolApprovalInteractionContent;
}

@Freezed(toStringOverride: false)
final class UserInputInteractionContent extends InteractionSnapshotContent
    with _$UserInputInteractionContent {
  UserInputInteractionContent({
    required List<InteractionQuestion> questions,
    required this.state,
  }) : questions = List.unmodifiable(questions),
       super._();
  final List<InteractionQuestion> questions;
  final UserInputInteractionState state;
  @override
  InteractionStatus get status => state.status;
}

@Freezed(toStringOverride: false)
final class ToolApprovalInteractionContent extends InteractionSnapshotContent
    with _$ToolApprovalInteractionContent {
  const ToolApprovalInteractionContent({
    required this.name,
    required this.arguments,
    required this.workingDirectory,
    required this.parentAgentId,
    required this.state,
  }) : super._();
  final String name;

  /// The original opaque tool argument text; the SDK never parses it as JSON.
  final String arguments;
  final String? workingDirectory;
  final String? parentAgentId;
  final ToolApprovalInteractionState state;
  @override
  InteractionStatus get status => state.status;
}

@Freezed(toStringOverride: false)
final class InteractionQuestion with _$InteractionQuestion {
  InteractionQuestion({
    required this.id,
    required this.header,
    required this.question,
    required this.isOther,
    required this.isSecret,
    required List<UserQuestionOptionView>? options,
  }) : options = options == null ? null : List.unmodifiable(options);
  final String id;
  final String header;
  final String question;
  final bool isOther;
  final bool isSecret;
  // None and Some(empty) are distinct native facts.
  final List<UserQuestionOptionView>? options;
}

@Freezed(toStringOverride: false)
sealed class UserInputInteractionState with _$UserInputInteractionState {
  const UserInputInteractionState._();
  const factory UserInputInteractionState.pending({
    required String operationId,
  }) = PendingUserInputInteraction;
  factory UserInputInteractionState.resolved({
    required String operationId,
    required int resolvedAt,
    required List<UserInputAnswerCommand> answers,
  }) = ResolvedUserInputInteraction;
  const factory UserInputInteractionState.cancelled({
    required String operationId,
    required int cancelledAt,
    required String reason,
  }) = CancelledUserInputInteraction;
  const factory UserInputInteractionState.expired({
    required String operationId,
    required int expiredAt,
  }) = ExpiredUserInputInteraction;
  InteractionStatus get status => switch (this) {
    PendingUserInputInteraction() => InteractionStatus.pending,
    ResolvedUserInputInteraction() => InteractionStatus.resolved,
    CancelledUserInputInteraction() => InteractionStatus.cancelled,
    ExpiredUserInputInteraction() => InteractionStatus.expired,
  };
}

@Freezed(toStringOverride: false)
final class ResolvedUserInputInteraction extends UserInputInteractionState
    with _$ResolvedUserInputInteraction {
  ResolvedUserInputInteraction({
    required this.operationId,
    required this.resolvedAt,
    required List<UserInputAnswerCommand> answers,
  }) : answers = List.unmodifiable(answers),
       super._();
  final String operationId;
  final int resolvedAt;
  final List<UserInputAnswerCommand> answers;
}

@Freezed(toStringOverride: false)
sealed class ToolApprovalInteractionState with _$ToolApprovalInteractionState {
  const ToolApprovalInteractionState._();
  const factory ToolApprovalInteractionState.pending({
    required String operationId,
  }) = PendingToolApprovalInteraction;
  const factory ToolApprovalInteractionState.resolved({
    required String operationId,
    required int resolvedAt,
    required ToolApprovalDecision decision,
    required String? reason,
  }) = ResolvedToolApprovalInteraction;
  const factory ToolApprovalInteractionState.cancelled({
    required String operationId,
    required int cancelledAt,
    required String reason,
  }) = CancelledToolApprovalInteraction;
  const factory ToolApprovalInteractionState.expired({
    required String operationId,
    required int expiredAt,
  }) = ExpiredToolApprovalInteraction;
  InteractionStatus get status => switch (this) {
    PendingToolApprovalInteraction() => InteractionStatus.pending,
    ResolvedToolApprovalInteraction() => InteractionStatus.resolved,
    CancelledToolApprovalInteraction() => InteractionStatus.cancelled,
    ExpiredToolApprovalInteraction() => InteractionStatus.expired,
  };
}
