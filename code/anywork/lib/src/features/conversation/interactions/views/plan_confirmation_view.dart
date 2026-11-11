import 'package:material_ui/material_ui.dart';

import '../../../../app/theme/studio_tokens.dart';
import '../../../../l10n/studio_l10n.dart';
import '../../../../shared/studio_driver_keys.dart';
import '../../composer/widgets/multiline_enter_shortcuts.dart';

/// Plan-only presentation. The view owns draft text and focus; the connector supplies actions.
class PlanConfirmationView extends StatefulWidget {
  const PlanConfirmationView({
    required this.interactionId,
    required this.available,
    required this.enabled,
    required this.error,
    required this.onSubmitRevision,
    required this.onApprove,
    this.initialFeedback = '',
    this.submitting = false,
    this.trailing,
    super.key,
  });

  final String interactionId;
  final bool available;
  final bool enabled;
  final bool submitting;
  final String? error;
  final ValueChanged<String> onSubmitRevision;
  final VoidCallback onApprove;
  final String initialFeedback;
  final Widget? trailing;

  @override
  State<PlanConfirmationView> createState() => _PlanConfirmationViewState();
}

class _PlanConfirmationViewState extends State<PlanConfirmationView> {
  late final TextEditingController _controller;
  final FocusNode _inputFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialFeedback)
      ..addListener(_handleFeedbackChanged);
  }

  @override
  void didUpdateWidget(covariant PlanConfirmationView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.interactionId != widget.interactionId) {
      _controller.clear();
    }
  }

  @override
  void dispose() {
    _controller
      ..removeListener(_handleFeedbackChanged)
      ..dispose();
    _inputFocus.dispose();
    super.dispose();
  }

  void _handleFeedbackChanged() {
    if (mounted) setState(() {});
  }

  /// Button and Enter share validation and the same feature action.
  void _submitRevision({bool fromKeyboard = false}) {
    if ((fromKeyboard &&
            (!_inputFocus.hasFocus || _controller.value.composing.isValid)) ||
        !widget.available ||
        !widget.enabled ||
        widget.submitting) {
      return;
    }
    final feedback = _controller.text.trim();
    if (feedback.isEmpty) return;
    widget.onSubmitRevision(feedback);
  }

  @override
  Widget build(BuildContext context) {
    final canDecide = widget.available && widget.enabled && !widget.submitting;
    final hasFeedback = _controller.text.trim().isNotEmpty;

    final actionStyle = ButtonStyle(
      textStyle: WidgetStatePropertyAll(context.text.labelLarge),
      minimumSize: const WidgetStatePropertyAll(Size(0, 40)),
      padding: const WidgetStatePropertyAll(
        EdgeInsets.symmetric(horizontal: 14),
      ),
      visualDensity: VisualDensity.standard,
      tapTargetSize: MaterialTapTargetSize.padded,
    );
    final statusStyle = context.text.labelSmall?.copyWith(
      color: context.colors.onSurfaceVariant,
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
          onPressed: canDecide && hasFeedback ? _submitRevision : null,
        ),
        FilledButton.icon(
          key: StudioDriverKeys.planApprove,
          style: actionStyle,
          icon: const Icon(Icons.check, size: 18),
          label: Text(context.l10n.interactionPlanConfirmAction),
          onPressed: canDecide ? widget.onApprove : null,
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
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (widget.trailing != null)
              Align(
                alignment: AlignmentDirectional.centerEnd,
                child: widget.trailing!,
              ),
            if (widget.trailing != null) const SizedBox(height: 8),
            Text(
              context.l10n.interactionPlanAdjust,
              style: context.text.bodySmall?.copyWith(
                color: context.colors.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 4),
            MultilineEnterShortcuts(
              controller: _controller,
              child: TextField(
                key: StudioDriverKeys.planFeedbackInput,
                controller: _controller,
                focusNode: _inputFocus,
                enabled: widget.enabled && !widget.submitting,
                minLines: 2,
                maxLines: 4,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => _submitRevision(fromKeyboard: true),
                onEditingComplete: () => _inputFocus.requestFocus(),
                decoration: InputDecoration(
                  hintText: context.l10n.interactionPlanAdjustHint,
                  contentPadding: const EdgeInsets.all(12),
                ),
              ),
            ),
            if (widget.error case final message?) ...[
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
            if (widget.submitting) const SizedBox(height: 4),
            LayoutBuilder(
              builder: (context, constraints) {
                Widget progress() => Row(
                  mainAxisSize: MainAxisSize.min,
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
                        style: statusStyle,
                      ),
                    ),
                  ],
                );

                if (!widget.submitting) {
                  return Align(
                    alignment: AlignmentDirectional.centerEnd,
                    child: actions,
                  );
                }

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
                final progressWidth =
                    textWidth(
                      context.l10n.planDecisionSubmitting,
                      statusStyle,
                    ) +
                    18;
                if (progressWidth + 16 + actionsWidth <= constraints.maxWidth) {
                  return Row(
                    children: [
                      Expanded(child: progress()),
                      const SizedBox(width: 16),
                      actions,
                    ],
                  );
                }
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    progress(),
                    const SizedBox(height: 4),
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
