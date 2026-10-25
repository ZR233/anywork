import 'package:anywork_client/configuration.dart';
import 'package:anywork_client/modes.dart'
    show DelegationMode, DelegationPreference;
import 'package:anywork_client/resources.dart';
import 'package:flutter/material.dart';

import '../../../../diagnostics/studio_driver_keys.dart';
import '../../../../l10n/studio_l10n.dart';
import '../../../../ui/feedback/studio_messages.dart';
import '../../../../ui/labels/delegation_labels.dart';
import '../../state/settings_action.dart';
import '../../widgets/settings_pane.dart';
import '../state/general_settings_state.dart';

/// Default values for future roots, not a Start draft or a Thread override.
class DelegationDefaultsSection extends StatelessWidget {
  const DelegationDefaultsSection({
    required this.state,
    required this.readError,
    required this.modeErrors,
    required this.preferenceErrors,
    required this.onMode,
    required this.onPreference,
    required this.onRetry,
    super.key,
  });

  final GeneralSettingsViewState state;
  final String? readError;
  final List<String> modeErrors;
  final List<String> preferenceErrors;
  final ValueChanged<DelegationMode> onMode;
  final ValueChanged<DelegationPreference> onPreference;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final read = state.source.delegation;
    final material = switch (read) {
      ReadyReadValue<DelegationSettings, ConfigurationReadRef>(
        :final current,
      ) =>
        current,
      LoadingReadValue<DelegationSettings, ConfigurationReadRef>(
        :final previous,
      ) ||
      FailedReadValue<DelegationSettings, ConfigurationReadRef>(
        :final previous,
      ) => previous,
      _ => null,
    };
    final current =
        read is ReadyReadValue<DelegationSettings, ConfigurationReadRef> &&
        state.source.projection.stamp?.origin != null &&
        state.source.projection.header?.reference != null &&
        material?.origin == state.source.projection.stamp?.origin &&
        material?.reference == state.source.projection.header?.reference;
    final defaults = state.delegation;
    final modeAction = state.actions[GeneralSettingAction.delegationMode];
    final preferenceAction =
        state.actions[GeneralSettingAction.delegationPreference];
    final loading = state.delegationReadPending || read is LoadingReadValue;
    return SettingsSection(
      title: context.l10n.delegationSettingsTitle,
      children: [
        if (material != null && !current)
          Text(
            '${context.l10n.resourceSourceLastKnown} · ${material.origin.ownerEpoch}/${material.origin.incarnation} · r${material.reference.revision}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        if (loading)
          Text(context.l10n.resourceSourceLoading)
        else if (defaults == null)
          Text(
            readError == null
                ? context.l10n.resourceSourceUninitialized
                : context.l10n.toolStatusFailed,
          ),
        if (read case FailedReadValue<DelegationSettings, ConfigurationReadRef>(
          :final origin,
          :final reference,
        ))
          if (origin != state.source.projection.stamp?.origin ||
              reference != state.source.projection.header?.reference)
            Text(
              '${context.l10n.resourceSourceLastKnown} · ${origin.ownerEpoch}/${origin.incarnation} · r${reference.revision}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
        if (readError != null) _failure(context, readError!),
        Text(context.l10n.delegationDefaultMode),
        DropdownButton<DelegationMode>(
          key: StudioDriverKeys.defaultDelegationMode,
          isExpanded: true,
          value: defaults?.mode,
          hint: const Text('—'),
          items: [
            for (final mode in DelegationMode.values)
              DropdownMenuItem(
                value: mode,
                key: StudioDriverKeys.delegationModeOption('default', mode),
                child: Text(
                  context.delegationModeLabel(mode),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
          onChanged: !current || (modeAction?.preventsResubmission ?? false)
              ? null
              : (value) {
                  if (value != null) onMode(value);
                },
        ),
        _DelegationActionStatus(action: modeAction, errors: modeErrors),
        const SizedBox(height: 12),
        Text(context.l10n.delegationDefaultPreference),
        DropdownButton<DelegationPreference>(
          key: StudioDriverKeys.defaultDelegationPreference,
          isExpanded: true,
          value: defaults?.preference,
          hint: const Text('—'),
          items: [
            for (final preference in DelegationPreference.values)
              DropdownMenuItem(
                value: preference,
                key: StudioDriverKeys.delegationPreferenceOption(
                  'default',
                  preference,
                ),
                child: Text(
                  context.delegationPreferenceLabel(preference),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
          onChanged:
              !current || (preferenceAction?.preventsResubmission ?? false)
              ? null
              : (value) {
                  if (value != null) onPreference(value);
                },
        ),
        Text(context.l10n.delegationOnlyAutomatic),
        if (defaults != null) ...[
          const SizedBox(height: 4),
          Text(context.delegationPreferenceHint(defaults.preference)),
        ],
        _DelegationActionStatus(
          action: preferenceAction,
          errors: preferenceErrors,
        ),
        if (!current || readError != null)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: loading ? null : onRetry,
              child: Text(context.l10n.sidebarRetry),
            ),
          ),
      ],
    );
  }
}

class _DelegationActionStatus extends StatelessWidget {
  const _DelegationActionStatus({required this.action, required this.errors});
  final SettingsAction? action;
  final List<String> errors;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      if (action?.pending ?? false) Text(context.l10n.settingsModelSaving),
      if (action?.uncertain ?? false) Text(context.l10n.modelDetailUnknown),
      if (action?.operation case final operation?)
        SelectableText(
          operation.id.value,
          style: Theme.of(context).textTheme.bodySmall,
        ),
      for (final error in errors) _failure(context, error),
    ],
  );
}

Widget _failure(BuildContext context, String message) => StudioInlineMessage(
  icon: Icons.error_outline,
  message: message,
  color: Theme.of(context).colorScheme.error,
);
