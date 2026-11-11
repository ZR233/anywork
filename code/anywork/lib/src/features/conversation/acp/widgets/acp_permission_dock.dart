import 'package:material_ui/material_ui.dart';

import '../../../../app/theme/studio_tokens.dart';
import '../../../../l10n/studio_l10n.dart';
import '../../../../shared/studio_chrome.dart';
import '../../interactions/widgets/interaction_widgets.dart';
import '../../timeline/widgets/timeline_patch_diff_view.dart';
import '../state/acp_view_state.dart';

/// Docked permission approval card anchored directly above the composer so
/// pending requests never scroll out of view during long conversations.
///
/// Renders every server-provided option in its exact server order without
/// coercing into binary approve/reject buttons.
class AcpPermissionDock extends StatelessWidget {
  const AcpPermissionDock({
    super.key,
    required this.state,
    required this.onSelectOption,
    required this.onCancel,
  });

  final AcpPermissionDockViewState state;
  final void Function(String permissionId, String optionId) onSelectOption;
  final ValueChanged<String> onCancel;

  @override
  Widget build(BuildContext context) {
    final request = state.activeRequest;
    if (request == null) return const SizedBox.shrink();
    final l10n = context.l10n;
    final locked = request.submitting;

    return Padding(
      key: ValueKey(AcpViewKeyValues.permissionDock(request.id)),
      padding: const EdgeInsets.only(bottom: 8),
      child: InteractionDockShell(
        kind: InteractionDockKind.permission,
        title: l10n.acpPermissionTitle,
        subtitle: request.title,
        trailing: state.pendingCount > 1
            ? StudioPill(
                label: l10n.acpPermissionQueueBadge(state.pendingCount),
                tone: StudioTone.warning,
              )
            : null,
        footerHint: locked
            ? l10n.acpPermissionSubmitting
            : l10n.interactionPermissionFooterHint,
        footer: DockActions(
          children: [
            TextButton(
              key: ValueKey(AcpViewKeyValues.permissionCancel(request.id)),
              onPressed: locked ? null : () => onCancel(request.id),
              child: Text(l10n.acpPermissionCancel),
            ),
            for (final option in request.options)
              _PermissionOptionButton(
                key: ValueKey(
                  AcpViewKeyValues.permissionOption(
                    request.id,
                    option.optionId,
                  ),
                ),
                option: option,
                enabled: !locked,
                onPressed: () => onSelectOption(request.id, option.optionId),
              ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (request.kindLabel != null || request.locations.isNotEmpty) ...[
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  if (request.kindLabel case final kind?)
                    StudioPill(label: kind, tone: StudioTone.brand),
                  for (final loc in request.locations)
                    StudioCompactChip(
                      icon: Icons.place_outlined,
                      label: loc,
                      tooltip: loc,
                      maxWidth: 300,
                    ),
                ],
              ),
              const SizedBox(height: 8),
            ],
            if (request.diffs.isNotEmpty)
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 160),
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (var i = 0; i < request.diffs.length; i++) ...[
                        if (i > 0) const SizedBox(height: 6),
                        DecoratedBox(
                          decoration: BoxDecoration(
                            color: context.colors.surfaceContainerLow,
                            borderRadius: BorderRadius.circular(StudioRadii.sm),
                            border: Border.all(
                              color: context.colors.outlineVariant,
                            ),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 6),
                            child: TimelinePatchDiffView(
                              document: request.diffs[i],
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              )
            else if (request.argumentsPreview case final args?)
              StudioCodeBlock(text: args, maxHeight: 110),
            if (state.errorMessage case final error?) ...[
              const SizedBox(height: 8),
              StudioInlineMessage(
                icon: Icons.error_outline_rounded,
                message: error,
                color: context.colors.error,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _PermissionOptionButton extends StatelessWidget {
  const _PermissionOptionButton({
    super.key,
    required this.option,
    required this.enabled,
    required this.onPressed,
  });

  final AcpPermissionOptionPresentation option;
  final bool enabled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => switch (option.tone) {
    AcpPermissionOptionTone.allowOnce => FilledButton(
      onPressed: enabled ? onPressed : null,
      child: Text(option.name),
    ),
    AcpPermissionOptionTone.allowAlways => FilledButton.tonal(
      onPressed: enabled ? onPressed : null,
      child: Text(option.name),
    ),
    AcpPermissionOptionTone.rejectOnce ||
    AcpPermissionOptionTone.rejectAlways ||
    AcpPermissionOptionTone.other => OutlinedButton(
      onPressed: enabled ? onPressed : null,
      child: Text(option.name),
    ),
  };
}
