import 'dart:async';

import 'package:anywork_client/studio_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/studio_l10n.dart';
import '../../presentation/providers/client_provider.dart';
import '../../presentation/providers/settings_store.dart';
import '../../shared/delegation_labels.dart';
import '../../shared/studio_driver_keys.dart';
import 'settings_common.dart';

class DelegationDefaultsPanel extends ConsumerWidget {
  const DelegationDefaultsPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final store = ref.watch(settingsStoreProvider);
    final defaults = store.canonical?.delegation;
    if (defaults == null) return const SizedBox.shrink();
    final commands = ref.read(anyworkClientProvider).settingsCommands;
    final modeCommand = store.commands['delegation:mode'];
    final preferenceCommand = store.commands['delegation:preference'];
    return SettingsSectionPanel(
      title: context.l10n.delegationSettingsTitle,
      children: [
        Text(context.l10n.delegationDefaultMode),
        DropdownButton<DelegationMode>(
          key: StudioDriverKeys.defaultDelegationMode,
          isExpanded: true,
          value: defaults.mode,
          items: [
            for (final mode in DelegationMode.values)
              DropdownMenuItem(
                value: mode,
                key: StudioDriverKeys.delegationModeOption('default', mode),
                child: Text(context.delegationModeLabel(mode)),
              ),
          ],
          onChanged: (mode) {
            if (mode != null) {
              unawaited(
                commands
                    .applySettingsField(DelegationModeCommand(mode))
                    .then<void>((_) {}, onError: (Object _, StackTrace _) {}),
              );
            }
          },
        ),
        if (modeCommand?.isPending == true)
          Text(context.l10n.settingsModelSaving),
        if (modeCommand?.error case final failure?)
          SettingsInlineError(message: failure.message),
        const SizedBox(height: 12),
        Text(context.l10n.delegationDefaultPreference),
        DropdownButton<DelegationPreference>(
          key: StudioDriverKeys.defaultDelegationPreference,
          isExpanded: true,
          value: defaults.preference,
          items: [
            for (final preference in DelegationPreference.values)
              DropdownMenuItem(
                value: preference,
                key: StudioDriverKeys.delegationPreferenceOption(
                  'default',
                  preference,
                ),
                child: Text(context.delegationPreferenceLabel(preference)),
              ),
          ],
          onChanged: (preference) {
            if (preference != null) {
              unawaited(
                commands
                    .applySettingsField(DelegationPreferenceCommand(preference))
                    .then<void>((_) {}, onError: (Object _, StackTrace _) {}),
              );
            }
          },
        ),
        Text(context.l10n.delegationOnlyAutomatic),
        const SizedBox(height: 4),
        Text(context.delegationPreferenceHint(defaults.preference)),
        if (preferenceCommand?.isPending == true)
          Text(context.l10n.settingsModelSaving),
        if (preferenceCommand?.error case final failure?)
          SettingsInlineError(message: failure.message),
      ],
    );
  }
}
