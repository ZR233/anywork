import 'package:flutter/material.dart';

import '../../l10n/studio_l10n.dart';
import '../menus/quiet_selector_menu.dart';
import '../menus/studio_menu_label.dart';

/// Renders supplied candidates verbatim. Null stays the model default, not the
/// first candidate; an unavailable selection is never normalized by the View.
class EffortSelector extends StatelessWidget {
  EffortSelector({
    required List<String> efforts,
    required this.selected,
    required this.onSelected,
    this.allowDefault = false,
    this.enabled = true,
    this.pending = false,
    this.blockedReason,
    this.onExplain,
    super.key,
  }) : efforts = List.unmodifiable(efforts);

  final List<String> efforts;
  final String? selected;
  final ValueChanged<String?> onSelected;
  final bool allowDefault;
  final bool enabled;
  final bool pending;
  final String? blockedReason;
  final ValueChanged<String>? onExplain;

  @override
  Widget build(BuildContext context) {
    final selectionEnabled =
        enabled && (allowDefault || efforts.isNotEmpty) && blockedReason == null;
    final label = selected == null
        ? context.l10n.settingsAgentProfileEffortDefault
        : efforts.contains(selected)
        ? selected!
        : context.l10n.settingsAgentRouteUnavailable(selected!);
    final reason = blockedReason;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (pending)
          const Padding(
            padding: EdgeInsets.only(right: 6),
            child: SizedBox.square(
              dimension: 12,
              child: CircularProgressIndicator(strokeWidth: 1.5),
            ),
          ),
        QuietSelectorMenu<String?>(
          key: const ValueKey<String>('reasoning-effort-selector'),
          tooltip: reason ?? context.l10n.statusReasoningEffort,
          enabled: selectionEnabled,
          onBlockedTap: enabled && reason != null && onExplain != null
              ? () => onExplain!(reason)
              : null,
          onSelected: onSelected,
          items: [
            if (allowDefault)
              QuietSelectorMenuItem<String?>(
                value: null,
                selected: selected == null,
                itemKey: const ValueKey<String>('default-reasoning-effort-option'),
                child: Text(context.l10n.settingsAgentProfileEffortDefault),
              ),
            for (final effort in efforts)
              QuietSelectorMenuItem<String?>(
                value: effort,
                selected: effort == selected,
                itemKey: ValueKey<String>('reasoning-effort-$effort'),
                child: Text(effort),
              ),
          ],
          child: StudioMenuLabel(
            key: const ValueKey<String>('reasoning-effort-label'),
            label: label,
            enabled: selectionEnabled,
            maxWidth: 140,
          ),
        ),
      ],
    );
  }
}
