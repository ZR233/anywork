import 'package:flutter/material.dart';

import '../../../app/theme/studio_tokens.dart';
import 'interaction_dock_shell.dart';

/// One question's vertical rhythm (header → 4 → body → 10 → options → 8 →
/// input), as the pre-refactor `interaction/question_step.dart` laid it out.
/// Text slots accept widgets because a paged read may still be materializing.
class QuestionStep extends StatelessWidget {
  const QuestionStep({
    required this.header,
    required this.options,
    this.question,
    this.input,
    super.key,
  });

  final Widget header;
  final Widget? question;
  final List<Widget> options;
  final Widget? input;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        header,
        if (question != null) ...[const SizedBox(height: 4), question!],
        if (options.isNotEmpty) ...[const SizedBox(height: 10), ...options],
        if (input != null) ...[const SizedBox(height: 8), input!],
      ],
    );
  }
}

/// A selectable option row with the shared square mark. Disabled rows keep their
/// geometry and only fade, so a read-only dock never reflows.
class QuestionOptionRow extends StatelessWidget {
  const QuestionOptionRow({
    required this.label,
    required this.selected,
    required this.onPressed,
    this.description,
    super.key,
  });

  final String label;
  final Widget? description;
  final bool selected;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      ignoring: onPressed == null,
      child: Opacity(
        opacity: onPressed == null ? 0.55 : 1,
        child: DockOptionRow(
          title: label,
          subtitle: description,
          selected: selected,
          onPressed: () => onPressed?.call(),
          leading: _OptionMark(selected: selected),
        ),
      ),
    );
  }
}

class _OptionMark extends StatelessWidget {
  const _OptionMark({required this.selected});

  final bool selected;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 140),
      width: 20,
      height: 20,
      margin: const EdgeInsets.only(top: 1),
      decoration: BoxDecoration(
        color: selected ? context.colors.primary : context.colors.surface,
        borderRadius: BorderRadius.circular(5),
        border: Border.all(
          color: selected ? context.colors.primary : context.colors.outline,
          width: 2,
        ),
      ),
      child: selected
          ? Icon(Icons.check, size: 13, color: context.colors.onPrimary)
          : null,
    );
  }
}
