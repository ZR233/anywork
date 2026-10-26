import 'package:anywork_client/modes.dart'
    show ThreadModeDescriptor, ThreadModeId;
import 'package:flutter/material.dart';

import '../../l10n/studio_l10n.dart';
import '../menus/quiet_selector_menu.dart';
import '../menus/studio_menu_label.dart';

/// Controlled Mode catalog selector. A missing selection stays visible without
/// adding selectable built-in defaults to an empty or incomplete catalog.
class ModeSelector extends StatelessWidget {
  ModeSelector({
    required List<ThreadModeDescriptor> modes,
    required this.selected,
    required this.onSelected,
    this.enabled = true,
    this.onBlockedTap,
    this.lockedHint,
    this.snapshotDisplayName,
    this.usesSnapshot = false,
    super.key,
  }) : modes = List.unmodifiable(modes);

  final List<ThreadModeDescriptor> modes;
  final ThreadModeId selected;
  final ValueChanged<ThreadModeId> onSelected;
  final bool enabled;
  final VoidCallback? onBlockedTap;
  final String? lockedHint;
  final String? snapshotDisplayName;
  final bool usesSnapshot;

  @override
  Widget build(BuildContext context) {
    final current = modes.where((mode) => mode.id == selected).firstOrNull;
    final deleted = current == null;
    final label =
        current?.displayName ??
        (usesSnapshot
            ? '${snapshotDisplayName ?? context.compileModeLabel(selected)} · ${context.l10n.modeSnapshotBadge}'
            : '${context.compileModeLabel(selected)} · ${context.l10n.modeDeletedBadge}');
    final defaultTooltip = deleted
        ? (usesSnapshot
              ? context.l10n.modeDeletedUsingSnapshot
              : context.l10n.modeDeletedChooseAnother)
        : enabled
        ? context.l10n.statusSessionMode
        : context.l10n.statusSessionModeLocked;
    return QuietSelectorMenu<ThreadModeId>(
      key: const ValueKey<String>('session-mode-selector'),
      tooltip: (!enabled ? lockedHint : null) ?? defaultTooltip,
      enabled: enabled,
      onBlockedTap: onBlockedTap,
      onSelected: onSelected,
      items: [
        for (final mode in modes)
          QuietSelectorMenuItem<ThreadModeId>(
            value: mode.id,
            selected: mode.id == selected,
            itemKey: ValueKey<String>('session-mode-${mode.id.id}'),
            child: Row(
              children: [
                Icon(sessionModeIcon(mode.id), size: 18),
                const SizedBox(width: 10),
                Flexible(
                  child: Text(
                    mode.displayName,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
      ],
      child: StudioMenuLabel(
        key: const ValueKey<String>('session-mode-label'),
        label: label,
        enabled: enabled && modes.isNotEmpty,
        maxWidth: 96,
      ),
    );
  }
}

IconData sessionModeIcon(ThreadModeId mode) =>
    mode == ThreadModeId.simple ? Icons.flash_on : Icons.route_outlined;
