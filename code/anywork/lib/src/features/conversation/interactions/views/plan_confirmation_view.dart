import 'package:flutter/material.dart';

import '../../../../app/theme/studio_tokens.dart';
import '../../../../l10n/studio_l10n.dart';
import '../../../../shared/studio_driver_keys.dart';
import '../../composer/widgets/multiline_enter_shortcuts.dart';

/// Plan-only presentation; the Connector owns availability and decisions.
class PlanConfirmationView extends StatelessWidget {
  const PlanConfirmationView({
    required this.controller,
    required this.available,
    required this.enabled,
    required this.error,
    required this.onFeedbackChanged,
    required this.onSubmitRevision,
    required this.onApprove,
    this.submitting = false,
    this.trailing,
    super.key,
  });

  final TextEditingController controller;
  final bool available;
  final bool enabled;
  final bool submitting;
  final String? error;
  final ValueChanged<String> onFeedbackChanged;
  final VoidCallback onSubmitRevision;
  final VoidCallback onApprove;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final canDecide = available && enabled && !submitting;
    final hasFeedback = controller.text.trim().isNotEmpty;
    void submitRevision() {
      if (canDecide && hasFeedback) onSubmitRevision();
    }

    final actionStyle = ButtonStyle(
      textStyle: WidgetStatePropertyAll(context.text.labelLarge),
      minimumSize: const WidgetStatePropertyAll(Size(0, 40)),
      padding: const WidgetStatePropertyAll(
        EdgeInsets.symmetric(horizontal: 14),
      ),
      visualDensity: VisualDensity.standard,
      tapTargetSize: MaterialTapTargetSize.padded,
    );
    final hintStyle = context.text.labelSmall?.copyWith(
      color: context.colors.onSurfaceVariant,
    );
    final hint = Stack(
      alignment: AlignmentDirectional.centerStart,
      children: [
        // Keep the idle hint's footprint during submission so the actions
        // do not move between rows when this shorter message appears.
        Visibility(
          visible: !submitting,
          maintainSize: true,
          maintainAnimation: true,
          maintainState: true,
          child: Text(
            context.l10n.interactionPlanFeedbackHint,
            style: hintStyle,
          ),
        ),
        if (submitting)
          Positioned.fill(
            child: Row(
              children: [
                const SizedBox(
                  width: 12,
                  height: 12,
                  child: CircularProgressIndicator(strokeWidth: 1.5),
                ),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    context.l10n.planDecisionSubmitting,
                    style: hintStyle,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
    final actions = Wrap(
      alignment: WrapAlignment.end,
      spacing: 8,
      runSpacing: 8,
      children: [
        OutlinedButton.icon(
          key: StudioDriverKeys.planSubmitRevision,
          style: actionStyle,
          icon: const Icon(Icons.send_outlined, size: 18),
          label: Text(context.l10n.interactionPlanAdjustSubmit),
          onPressed: canDecide && hasFeedback ? submitRevision : null,
        ),
        FilledButton.icon(
          key: StudioDriverKeys.planApprove,
          style: actionStyle,
          icon: const Icon(Icons.check, size: 18),
          label: Text(context.l10n.interactionPlanConfirmAction),
          onPressed: canDecide ? onApprove : null,
        ),
      ],
    );
    return DecoratedBox(
      decoration: BoxDecoration(
        color: context.colors.surfaceContainerLowest,
        border: Border.all(color: context.colors.outlineVariant),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                const Icon(Icons.check, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    context.l10n.interactionPlanConfirmTitle,
                    style: context.text.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if (trailing != null) ...[const SizedBox(width: 8), trailing!],
              ],
            ),
            const SizedBox(height: 4),
            Text(
              context.l10n.interactionPlanConfirmSubtitle,
              style: context.text.bodySmall?.copyWith(
                color: context.colors.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              context.l10n.interactionPlanAdjust,
              style: context.text.bodySmall?.copyWith(
                color: context.colors.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 6),
            MultilineEnterShortcuts(
              controller: controller,
              onChanged: onFeedbackChanged,
              child: TextField(
                key: StudioDriverKeys.planFeedbackInput,
                controller: controller,
                enabled: enabled && !submitting,
                minLines: 2,
                maxLines: 4,
                textInputAction: TextInputAction.send,
                onChanged: onFeedbackChanged,
                onEditingComplete: () {},
                onSubmitted: (_) => submitRevision(),
                decoration: InputDecoration(
                  hintText: context.l10n.interactionPlanAdjustHint,
                  contentPadding: const EdgeInsets.all(16),
                ),
              ),
            ),
            if (error case final message?) ...[
              const SizedBox(height: 8),
              Semantics(
                liveRegion: true,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.error_outline,
                      size: 16,
                      color: context.colors.error,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        message,
                        key: StudioDriverKeys.planFeedbackError,
                        style: context.text.bodySmall?.copyWith(
                          color: context.colors.error,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 8),
            LayoutBuilder(
              builder: (context, constraints) {
                double textWidth(String text, TextStyle? style) {
                  final painter = TextPainter(
                    text: TextSpan(text: text, style: style),
                    textDirection: Directionality.of(context),
                    textScaler: MediaQuery.textScalerOf(context),
                    locale: Localizations.localeOf(context),
                  )..layout();
                  final width = painter.width;
                  painter.dispose();
                  return width;
                }

                // Measure the actual localized labels and text scale rather
                // than reserving a fixed fraction of the footer for actions.
                // Each button adds 28 padding + 18 icon + 8 icon gap.
                final actionsWidth =
                    textWidth(
                      context.l10n.interactionPlanAdjustSubmit,
                      context.text.labelLarge,
                    ) +
                    textWidth(
                      context.l10n.interactionPlanConfirmAction,
                      context.text.labelLarge,
                    ) +
                    2 * (28 + 18 + 8) +
                    8;
                final hintWidth = textWidth(
                  context.l10n.interactionPlanFeedbackHint,
                  hintStyle,
                );
                if (hintWidth + 16 + actionsWidth <= constraints.maxWidth) {
                  return Row(
                    children: [
                      Expanded(child: hint),
                      const SizedBox(width: 16),
                      actions,
                    ],
                  );
                }
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    hint,
                    const SizedBox(height: 8),
                    Align(
                      alignment: AlignmentDirectional.centerEnd,
                      child: actions,
                    ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
