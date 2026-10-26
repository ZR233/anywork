import 'package:flutter/material.dart';

import '../../../../diagnostics/studio_driver_keys.dart';
import '../../../../l10n/studio_l10n.dart';
import '../../widgets/settings_form_field.dart';
import '../state/account_editor_state.dart';

class CustomModelFields extends StatelessWidget {
  const CustomModelFields({
    required this.state,
    required this.index,
    required this.enabled,
    required this.onChanged,
    required this.onRemove,
    super.key,
  });
  final CustomModelDraft state;
  final int index;
  final bool enabled;
  final void Function(CustomModelField field, String raw) onChanged;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 10),
    child: Column(
      children: [
        Row(
          children: [
            Expanded(
              child: SettingsFormField(
                key: StudioDriverKeys.customModelId(index),
                value: state.modelId,
                label: context.l10n.settingsModelId,
                enabled: enabled,
                error: state.validation.containsKey(CustomModelField.modelId)
                    ? context.l10n.settingsManualModelIdConflict
                    : null,
                onChanged: (raw) => onChanged(CustomModelField.modelId, raw),
              ),
            ),
            IconButton(
              onPressed: enabled ? onRemove : null,
              tooltip: context.l10n.settingsRemoveModel,
              icon: const Icon(Icons.delete_outline),
            ),
          ],
        ),
        ExpansionTile(
          key: StudioDriverKeys.customModelAdvanced(index),
          title: Text(context.l10n.settingsModelAdvanced),
          children: [
            SettingsFormField(
              key: StudioDriverKeys.customModelDisplayName(index),
              value: state.displayName,
              label: context.l10n.settingsDisplayName,
              enabled: enabled,
              onChanged: (raw) => onChanged(CustomModelField.displayName, raw),
            ),
            const SizedBox(height: 10),
            DropdownMenu<String>(
              initialSelection: state.wireApi,
              label: Text(context.l10n.settingsProtocolType),
              enabled: enabled,
              expandedInsets: EdgeInsets.zero,
              dropdownMenuEntries: [
                if (state.wireApi != 'chat_completions' &&
                    state.wireApi != 'responses')
                  DropdownMenuEntry(
                    value: state.wireApi,
                    label: state.wireApi,
                    enabled: false,
                  ),
                DropdownMenuEntry(
                  value: 'chat_completions',
                  label: context.l10n.settingsProtocolChatCompletionsHttp,
                ),
                DropdownMenuEntry(
                  value: 'responses',
                  label: context.l10n.settingsProtocolResponsesHttp,
                ),
              ],
              onSelected: (value) {
                if (value != null) onChanged(CustomModelField.wireApi, value);
              },
            ),
            const SizedBox(height: 10),
            SettingsFormField(
              value: state.contextWindowRaw,
              label: context.l10n.settingsContextBudget,
              hint: '32000',
              enabled: enabled,
              error:
                  state.validation.containsKey(CustomModelField.contextWindow)
                  ? context.l10n.modelContextParametersInvalid
                  : null,
              onChanged: (raw) =>
                  onChanged(CustomModelField.contextWindow, raw),
            ),
            const SizedBox(height: 10),
            SettingsFormField(
              value: state.maxOutputTokensRaw,
              label: context.l10n.settingsOutputBudget,
              hint: '4096',
              enabled: enabled,
              error:
                  state.validation.containsKey(CustomModelField.maxOutputTokens)
                  ? context.l10n.modelContextParametersInvalid
                  : null,
              onChanged: (raw) =>
                  onChanged(CustomModelField.maxOutputTokens, raw),
            ),
          ],
        ),
      ],
    ),
  );
}
