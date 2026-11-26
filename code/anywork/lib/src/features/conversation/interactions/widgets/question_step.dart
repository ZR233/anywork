import 'package:material_ui/material_ui.dart';

import '../../../../app/theme/studio_tokens.dart';
import '../../../../domain/models/studio_models.dart';
import '../../../../l10n/studio_l10n.dart';
import '../../../../shared/studio_driver_keys.dart';

class QuestionStep extends StatelessWidget {
  const QuestionStep({
    super.key,
    required this.question,
    required this.questionKey,
    this.isFirstQuestion = false,
    this.firstOptionKey,
    this.controller,
    this.selected = const {},
    this.onOptionChanged,
    this.onTextChanged,
    required this.enabled,
  });

  final UserQuestionView question;
  final String questionKey;
  final bool isFirstQuestion;
  final GlobalKey? firstOptionKey;
  final TextEditingController? controller;
  final Set<String> selected;
  final void Function(String label, bool selected)? onOptionChanged;
  final ValueChanged<String>? onTextChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final changeOption = enabled ? onOptionChanged : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          question.header.isEmpty
              ? context.l10n.interactionQuestionFallback
              : question.header,
          style: Theme.of(context).textTheme.labelLarge,
        ),
        if (question.question.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(question.question),
        ],
        if (question.options.isNotEmpty) ...[
          const SizedBox(height: 10),
          for (final (optionIndex, option) in question.options.indexed)
            Padding(
              key: optionIndex == 0 && isFirstQuestion
                  ? StudioDriverKeys.userInputFirstOption
                  : StudioDriverKeys.userInputOption(questionKey, optionIndex),
              padding: const EdgeInsets.only(bottom: 7),
              child: KeyedSubtree(
                key: optionIndex == 0 && isFirstQuestion
                    ? firstOptionKey
                    : null,
                child: _QuestionOptionRow(
                  option: option,
                  selected: selected.contains(option.label),
                  onChanged: changeOption == null
                      ? null
                      : (value) => changeOption(option.label, value),
                ),
              ),
            ),
        ],
        if (controller case final draft?) ...[
          const SizedBox(height: 8),
          TextField(
            key: isFirstQuestion
                ? StudioDriverKeys.userInputFirstText
                : StudioDriverKeys.userInputText(questionKey),
            controller: draft,
            enabled: enabled,
            obscureText: question.isSecret,
            minLines: 1,
            maxLines: question.isSecret ? 1 : 4,
            decoration: InputDecoration(
              labelText: question.options.isEmpty
                  ? context.l10n.interactionAnswerLabel
                  : context.l10n.interactionCustomAnswerLabel,
              hintText: question.isSecret
                  ? context.l10n.interactionSecretHint
                  : context.l10n.interactionTextHint,
              prefixIcon: Icon(
                question.isSecret
                    ? Icons.password_outlined
                    : Icons.short_text_outlined,
              ),
            ),
            onChanged: onTextChanged,
          ),
        ],
      ],
    );
  }
}

class _QuestionOptionRow extends StatelessWidget {
  const _QuestionOptionRow({
    required this.option,
    required this.selected,
    required this.onChanged,
  });

  final UserQuestionOptionView option;
  final bool selected;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected
          ? context.colors.primaryContainer
          : context.colors.surfaceContainerLowest,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(StudioRadii.sm),
        side: selected
            ? BorderSide(color: context.colors.primary)
            : BorderSide.none,
      ),
      clipBehavior: Clip.antiAlias,
      child: CheckboxListTile(
        value: selected,
        onChanged: onChanged == null
            ? null
            : (value) {
                if (value != null) onChanged!(value);
              },
        controlAffinity: ListTileControlAffinity.leading,
        contentPadding: const EdgeInsets.fromLTRB(10, 0, 12, 0),
        title: Text(option.label, style: context.text.labelLarge),
        subtitle: option.description.isEmpty
            ? null
            : Text(option.description, style: context.text.bodySmall),
      ),
    );
  }
}
