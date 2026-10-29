import 'package:flutter/material.dart';

import '../../../../app/theme/studio_tokens.dart';
import '../../../../l10n/studio_l10n.dart';
import '../../../../shared/studio_driver_keys.dart';
import '../../composer/widgets/multiline_enter_shortcuts.dart';
import '../widgets/interaction_widgets.dart';

const _planActionMinHeight = 40.0;
const _planActionPadding = EdgeInsets.symmetric(horizontal: 14);
const _planActionVisualDensity = VisualDensity.standard;
const _planActionTapTargetSize = MaterialTapTargetSize.padded;

/// Plan confirmation presentation. It receives canonical availability and typed callbacks.
class PlanConfirmationView extends StatelessWidget {
  const PlanConfirmationView({
    required this.controller,
    required this.available,
    required this.enabled,
    required this.error,
    required this.onFeedbackChanged,
    required this.onSubmitRevision,
    required this.onApprove,
    this.trailing,
    super.key,
  });

  final TextEditingController controller;
  final bool available;
  final bool enabled;
  final String? error;
  final ValueChanged<String> onFeedbackChanged;
  final VoidCallback onSubmitRevision;
  final VoidCallback onApprove;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final hasFeedback = controller.text.trim().isNotEmpty;
    return InteractionDockShell(
      kind: InteractionDockKind.plan,
      trailing: trailing,
      title: context.l10n.interactionPlanConfirmTitle,
      subtitle: context.l10n.interactionPlanConfirmSubtitle,
      footerHint: context.l10n.interactionPlanFeedbackHint,
      footer: DockActions(
        children: [
          OutlinedButton.icon(
            key: StudioDriverKeys.planSubmitRevision,
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(0, _planActionMinHeight),
              padding: _planActionPadding,
              visualDensity: _planActionVisualDensity,
              tapTargetSize: _planActionTapTargetSize,
            ),
            icon: const Icon(Icons.send_outlined, size: 18),
            label: Text(context.l10n.interactionPlanAdjustSubmit),
            onPressed: available && hasFeedback ? onSubmitRevision : null,
          ),
          FilledButton.icon(
            key: StudioDriverKeys.planApprove,
            style: FilledButton.styleFrom(
              minimumSize: const Size(0, _planActionMinHeight),
              padding: _planActionPadding,
              visualDensity: _planActionVisualDensity,
              tapTargetSize: _planActionTapTargetSize,
            ),
            icon: const Icon(Icons.check, size: 18),
            label: Text(context.l10n.interactionPlanConfirmAction),
            onPressed: available ? onApprove : null,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          MultilineEnterShortcuts(
            controller: controller,
            onChanged: onFeedbackChanged,
            child: TextField(
              key: StudioDriverKeys.planFeedbackInput,
              controller: controller,
              enabled: enabled,
              minLines: 1,
              maxLines: 4,
              textInputAction: TextInputAction.send,
              onChanged: onFeedbackChanged,
              onEditingComplete: () {},
              onSubmitted: (_) => onSubmitRevision(),
              decoration: InputDecoration(
                labelText: context.l10n.interactionPlanAdjust,
                hintText: context.l10n.interactionPlanAdjustHint,
              ),
            ),
          ),
          if (error case final message?) ...[
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.error_outline,
                  size: 15,
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
          ],
        ],
      ),
    );
  }
}
