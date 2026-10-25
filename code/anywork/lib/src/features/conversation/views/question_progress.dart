import 'package:flutter/material.dart';

import '../../../l10n/studio_l10n.dart';

/// Horizontal question progress: "3 / 7", one dot per loaded question and the
/// answered count. Geometry and 140ms dot animation are the pre-refactor
/// `interaction/question_progress.dart`; only the data adapter differs, because
/// questions arrive page by page.
class QuestionProgress extends StatelessWidget {
  const QuestionProgress({
    required this.total,
    required this.currentIndex,
    required this.answeredCount,
    required this.indices,
    required this.answered,
    required this.onSelected,
    super.key,
  });

  /// Canonical question count of this interaction, not the loaded page size.
  final int total;
  final int currentIndex;
  final int answeredCount;

  /// Loaded question indices, in read order. A dot only exists for a question
  /// the reader can actually select.
  final List<int> indices;
  final bool Function(int index) answered;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          Text(
            context.l10n.interactionQuestionProgress(currentIndex + 1, total),
            style: Theme.of(context).textTheme.labelMedium
                ?.copyWith(color: colors.onSurfaceVariant),
          ),
          const SizedBox(width: 10),
          for (final (position, index) in indices.indexed)
            Padding(
              padding: EdgeInsets.only(
                right: position == indices.length - 1 ? 0 : 6,
              ),
              child: _ProgressDot(
                index: index,
                active: index == currentIndex,
                answered: answered(index),
                onPressed: () => onSelected(index),
              ),
            ),
          const SizedBox(width: 10),
          Text(
            context.l10n.interactionAnsweredCount(answeredCount),
            style: Theme.of(context).textTheme.labelSmall
                ?.copyWith(color: colors.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

class _ProgressDot extends StatelessWidget {
  const _ProgressDot({
    required this.index,
    required this.active,
    required this.answered,
    required this.onPressed,
  });

  final int index;
  final bool active;
  final bool answered;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final background = active
        ? colors.primary
        : answered
        ? colors.primary.withValues(alpha: 0.42)
        : colors.surfaceContainerHighest;
    return Tooltip(
      message: context.l10n.interactionQuestionTooltip(index + 1),
      child: InkResponse(
        onTap: onPressed,
        radius: 12,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          width: active ? 18 : 8,
          height: 8,
          decoration: BoxDecoration(
            color: background,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: colors.outlineVariant),
          ),
        ),
      ),
    );
  }
}
