import 'dart:convert';

import 'package:anywork_client/models.dart';
import 'package:material_ui/material_ui.dart';

import '../../../../l10n/studio_l10n.dart';
import '../../interactions/widgets/interaction_widgets.dart';
import '../../interactions/widgets/question_step.dart';

class ReadOnlyInteractionDetails extends StatelessWidget {
  const ReadOnlyInteractionDetails({
    required this.id,
    required this.payload,
    super.key,
  });
  final String id;
  final InteractionPayload payload;
  @override
  Widget build(BuildContext context) => switch (payload) {
    UserInputInteractionPayload(:final questions) => InteractionDockShell(
      kind: InteractionDockKind.question,
      title: context.l10n.interactionDetailsQuestionDetailsReadOnly,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (questions.any(
            (question) => !question.isSecret && question.question.isNotEmpty,
          ))
            SelectableText(
              questions
                  .where((question) => !question.isSecret)
                  .map((question) => question.question)
                  .where((text) => text.isNotEmpty)
                  .join('\n'),
            ),
          for (final question in questions)
            if (question.isSecret)
              Text(context.l10n.interactionDetailsSecretQuestionHidden)
            else
              QuestionStep(
                // The selectable public prompt above owns this text. Reuse the
                // existing option layout without duplicating the prompt.
                question: UserQuestionView(
                  id: question.id,
                  header: question.header,
                  question: '',
                  isSecret: false,
                  options: question.options,
                ),
                questionKey: 'details:$id:${question.id}',
                enabled: false,
              ),
        ],
      ),
    ),
    ToolApprovalInteractionPayload(
      :final toolName,
      :final arguments,
      :final workingDirectory,
    ) =>
      InteractionDockShell(
        kind: InteractionDockKind.permission,
        title: context.l10n.interactionDetailsApprovalDetailsReadOnly,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            InfoChip(icon: Icons.build_outlined, label: toolName),
            if (workingDirectory.isNotEmpty)
              InfoChip(icon: Icons.folder_outlined, label: workingDirectory),
            InteractionCodeBlock(
              text: const JsonEncoder.withIndent('  ').convert(arguments),
            ),
          ],
        ),
      ),
    UnknownInteractionPayload() => Text(
      context.l10n.interactionDetailsInvalidFormat,
    ),
  };
}
