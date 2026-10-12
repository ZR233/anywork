import 'dart:convert';

import '../../domain/models/studio_models.dart';

class InteractionPayloadSnapshot {
  const InteractionPayloadSnapshot({
    required this.rawBody,
    required this.summary,
    required this.toolName,
    required this.formattedArguments,
    required this.workingDirectory,
    required this.questions,
  });

  final String rawBody;
  final String summary;
  final String toolName;
  final String formattedArguments;
  final String workingDirectory;
  final List<UserQuestionView> questions;

  static InteractionPayloadSnapshot from(PendingInteraction interaction) {
    return switch (interaction.payload) {
      UserInputInteractionPayload(:final questions) =>
        InteractionPayloadSnapshot(
          rawBody: interaction.body,
          summary: interaction.body,
          toolName: '',
          formattedArguments: '',
          workingDirectory: '',
          questions: questions,
        ),
      ToolApprovalInteractionPayload(
        :final toolName,
        :final arguments,
        :final workingDirectory,
      ) =>
        InteractionPayloadSnapshot(
          rawBody: interaction.body,
          summary: interaction.body,
          toolName: toolName.isEmpty ? interaction.title : toolName,
          formattedArguments: _formatJson(arguments),
          workingDirectory: workingDirectory,
          questions: const [],
        ),
      UnknownInteractionPayload() => InteractionPayloadSnapshot(
        rawBody: interaction.body,
        summary: interaction.body,
        toolName: interaction.title,
        formattedArguments: '',
        workingDirectory: '',
        questions: const [],
      ),
    };
  }
}

String _formatJson(Object? value) {
  if (value == null) {
    return '';
  }
  try {
    return const JsonEncoder.withIndent('  ').convert(value);
  } on JsonUnsupportedObjectError {
    return value.toString();
  }
}

/// 与命令层一致：priority 最小的 pending interaction 是当前可解析目标。
PendingInteraction? activePendingInteraction(
  List<PendingInteraction> interactions,
) {
  if (interactions.isEmpty) return null;
  final ranked = [...interactions]
    ..sort(
      (left, right) =>
          interactionPriority(left.kind)
              .compareTo(interactionPriority(right.kind)),
    );
  return ranked.first;
}

/// 当前可解析目标是否仍是界面正在展示的 interaction。
bool pendingInteractionIsActive(
  List<PendingInteraction> interactions,
  String interactionId,
) {
  return activePendingInteraction(interactions)?.id == interactionId;
}
