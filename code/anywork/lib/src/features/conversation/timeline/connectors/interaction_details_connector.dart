import 'dart:convert';

import 'package:anywork_client/models.dart';
import 'package:material_ui/material_ui.dart';

import '../../../../l10n/studio_l10n.dart';
import '../../interactions/widgets/interaction_widgets.dart';
import '../../interactions/widgets/question_step.dart';

class ReadOnlyInteractionDetails extends StatefulWidget {
  const ReadOnlyInteractionDetails({
    required this.id,
    required this.payload,
    super.key,
  });
  final String id;
  final InteractionPayload payload;
  @override
  State<ReadOnlyInteractionDetails> createState() =>
      _ReadOnlyInteractionDetailsState();
}

class _ReadOnlyInteractionDetailsState
    extends State<ReadOnlyInteractionDetails> {
  final _controllers = <String, TextEditingController>{};
  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => switch (widget.payload) {
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
                // existing option/field layout without duplicating the prompt.
                question: UserQuestionView(
                  id: question.id,
                  header: question.header,
                  question: '',
                  isOther: question.isOther,
                  isSecret: false,
                  options: question.options,
                ),
                questionKey: 'details:${widget.id}:${question.id}',
                isFirstQuestion: false,
                firstOptionKey: GlobalKey(),
                controller: _controllers.putIfAbsent(
                  question.id,
                  TextEditingController.new,
                ),
                selected: const {},
                onOptionChanged: (_, _) {},
                onTextChanged: (_) {},
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
