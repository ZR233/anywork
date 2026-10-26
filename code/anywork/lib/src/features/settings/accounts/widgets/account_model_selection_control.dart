import 'package:anywork_client/models.dart';
import 'package:flutter/material.dart';

import '../../../../diagnostics/studio_driver_keys.dart';
import '../../../../l10n/studio_l10n.dart';
import '../../../../ui/selectors/model_labels.dart';
import '../../state/settings_action.dart';
import '../state/model_limits_state.dart';

class AccountModelSelectionControl extends StatelessWidget {
  const AccountModelSelectionControl({
    required this.accountId,
    required this.model,
    required this.onDetails,
    this.action,
    this.onEnabled,
    this.errors = const [],
    super.key,
  });

  final String accountId;
  final ModelDescriptor model;
  final AccountModelEnabledAction? action;
  final ValueChanged<bool>? onEnabled;
  final VoidCallback onDetails;
  final List<String> errors;

  @override
  Widget build(BuildContext context) {
    final operation = action?.action;
    final blocked =
        operation?.uncertain == true ||
        operation?.outcome == SettingsActionOutcome.synchronizationFailed;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SwitchListTile(
          key: StudioDriverKeys.modelEnabled(accountId, model.modelId),
          contentPadding: const EdgeInsets.symmetric(horizontal: 12),
          title: Text(
            context.l10n.settingsModelEnabled,
            semanticsLabel:
                '${context.l10n.settingsModelEnabled} · ${model.displayName} · $accountId / ${model.modelId}',
          ),
          subtitle: Text(
            operation?.pending == true
                ? context.l10n.settingsModelSaving
                : context.l10n.settingsModelEnabledHint,
          ),
          // Only this explicitly labelled short-term pending display is local.
          value: operation?.pending == true ? action!.enabled : model.enabled,
          onChanged: blocked ? null : onEnabled,
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (!model.enabled) Text(context.l10n.settingsModelDisabled),
              if (modelTextFilterMessage(context, model) case final reason?)
                Text(reason),
              for (final error in errors)
                SelectableText(
                  error,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              if (operation?.outcome == SettingsActionOutcome.rejected)
                Text(context.l10n.settingsModelSaveFailed),
              TextButton.icon(
                key: StudioDriverKeys.modelDetails(accountId, model.modelId),
                icon: const Icon(Icons.info_outline),
                label: Text(context.l10n.settingsModelDetails),
                onPressed: onDetails,
              ),
            ],
          ),
        ),
      ],
    );
  }
}
