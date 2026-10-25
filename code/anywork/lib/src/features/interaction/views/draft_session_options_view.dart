import 'package:anywork_client/configuration.dart';
import 'package:anywork_client/modes.dart';
import 'package:flutter/material.dart';

import '../../../diagnostics/studio_driver_keys.dart';
import '../../../l10n/studio_l10n.dart';
import '../../../ui/labels/delegation_labels.dart';

/// Controlled draft intent and canonical defaults. No repository or VM access.
class DraftSessionOptionsView extends StatelessWidget {
  const DraftSessionOptionsView({
    required this.defaults,
    required this.modeOverride,
    required this.preferenceOverride,
    required this.enabled,
    required this.defaultsPending,
    required this.onMode,
    required this.onPreference,
    required this.onDefaultMode,
    required this.onDefaultPreference,
    super.key,
  });

  final DelegationSettings? defaults;
  final DelegationMode? modeOverride;
  final DelegationPreference? preferenceOverride;
  final bool enabled;
  final bool defaultsPending;
  final ValueChanged<DelegationMode?> onMode;
  final ValueChanged<DelegationPreference?> onPreference;
  final ValueChanged<DelegationMode> onDefaultMode;
  final ValueChanged<DelegationPreference> onDefaultPreference;

  @override
  Widget build(BuildContext context) {
    final canonical = defaults;
    final effective = canonical == null
        ? null
        : DelegationSettings(
            mode: modeOverride ?? canonical.mode,
            preference: preferenceOverride ?? canonical.preference,
          );
    final summary = effective == null
        ? context.l10n.settingsMissing
        : context.delegationSummary(effective);
    final menuWidth = (MediaQuery.sizeOf(context).width - 32).clamp(0.0, 400.0);
    final style = MenuStyle(
      maximumSize: WidgetStatePropertyAll(
        Size(
          menuWidth,
          (MediaQuery.sizeOf(context).height - 64).clamp(0.0, 520.0),
        ),
      ),
    );
    Widget label(String value) => SizedBox(
      width: (menuWidth - 88).clamp(0.0, menuWidth),
      child: Text(value, maxLines: 3, overflow: TextOverflow.ellipsis),
    );
    return MenuAnchor(
      style: style,
      crossAxisUnconstrained: false,
      menuChildren: [
        MenuItemButton(child: label(summary)),
        MenuItemButton(
          child: label(
            modeOverride == null && preferenceOverride == null
                ? context.l10n.delegationInherited
                : context.l10n.delegationOverride,
          ),
        ),
        SubmenuButton(
          menuStyle: style,
          menuChildren: [
            for (final mode in <DelegationMode?>[
              null,
              ...DelegationMode.values,
            ])
              MenuItemButton(
                key: StudioDriverKeys.delegationModeOption('draft', mode),
                leadingIcon: Icon(modeOverride == mode ? Icons.check : null),
                onPressed: enabled ? () => onMode(mode) : null,
                child: label(
                  mode == null
                      ? context.l10n.delegationFollowDefault
                      : context.delegationModeLabel(mode),
                ),
              ),
          ],
          child: Text(context.l10n.delegationModeLabel),
        ),
        SubmenuButton(
          menuStyle: style,
          menuChildren: [
            for (final preference in <DelegationPreference?>[
              null,
              ...DelegationPreference.values,
            ])
              MenuItemButton(
                key: StudioDriverKeys.delegationPreferenceOption(
                  'draft',
                  preference,
                ),
                leadingIcon: Icon(
                  preferenceOverride == preference ? Icons.check : null,
                ),
                onPressed: enabled ? () => onPreference(preference) : null,
                child: label(
                  preference == null
                      ? context.l10n.delegationFollowDefault
                      : context.delegationPreferenceLabel(preference),
                ),
              ),
          ],
          child: Text(context.l10n.delegationPreferenceLabel),
        ),
        MenuItemButton(child: label(context.l10n.delegationOnlyAutomatic)),
        const Divider(),
        SubmenuButton(
          menuStyle: style,
          menuChildren: [
            for (final mode in DelegationMode.values)
              MenuItemButton(
                leadingIcon: Icon(canonical?.mode == mode ? Icons.check : null),
                onPressed: enabled && canonical != null && !defaultsPending
                    ? () => onDefaultMode(mode)
                    : null,
                child: label(context.delegationModeLabel(mode)),
              ),
          ],
          child: Text(context.l10n.delegationDefaultMode),
        ),
        SubmenuButton(
          menuStyle: style,
          menuChildren: [
            for (final preference in DelegationPreference.values)
              MenuItemButton(
                leadingIcon: Icon(
                  canonical?.preference == preference ? Icons.check : null,
                ),
                onPressed: enabled && canonical != null && !defaultsPending
                    ? () => onDefaultPreference(preference)
                    : null,
                child: label(context.delegationPreferenceLabel(preference)),
              ),
          ],
          child: Text(context.l10n.delegationDefaultPreference),
        ),
      ],
      builder: (context, controller, child) => IconButton(
        key: StudioDriverKeys.sessionSettings,
        tooltip: '${context.l10n.delegationSessionSettings} · $summary',
        onPressed: enabled
            ? () => controller.isOpen ? controller.close() : controller.open()
            : null,
        icon: defaultsPending
            ? const SizedBox.square(
                dimension: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.tune, size: 20),
      ),
    );
  }
}
