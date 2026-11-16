import 'package:material_ui/material_ui.dart';

import '../app/theme/studio_tokens.dart';
import '../l10n/studio_l10n.dart';
import 'studio_driver_keys.dart';
import 'studio_panel.dart';

/// Shared child-session chrome; backend-specific facts stay in the caller.
class StudioChildReadOnlyPanel extends StatelessWidget {
  const StudioChildReadOnlyPanel({
    super.key,
    this.children = const [],
    this.showScopeTooltip = false,
  });

  final List<Widget> children;
  final bool showScopeTooltip;

  @override
  Widget build(BuildContext context) {
    final icon = Icon(
      Icons.lock_outline,
      size: 18,
      color: context.colors.onSurfaceVariant,
    );
    return StudioPanel(
      key: StudioDriverKeys.agentReadOnlyPanel,
      backgroundColor: context.colors.surfaceContainer,
      borderColor: context.colors.outlineVariant,
      radius: StudioRadii.lg,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (showScopeTooltip)
                Tooltip(
                  message: context.l10n.composerAgentReadOnlyScope,
                  child: icon,
                )
              else
                icon,
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  context.l10n.composerAgentReadOnlyTitle,
                  style: context.text.bodyMedium?.copyWith(
                    color: context.colors.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
          ...children,
        ],
      ),
    );
  }
}
