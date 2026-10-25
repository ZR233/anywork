import 'package:anywork_client/models.dart';
import 'package:flutter/material.dart';

import '../../../../diagnostics/studio_driver_keys.dart';
import '../../../../l10n/studio_l10n.dart';
import '../../../../ui/branding/account_brand.dart';
import '../../widgets/settings_feedback.dart';
import '../../widgets/settings_form_field.dart';
import '../../widgets/settings_form_layout.dart';
import '../../widgets/settings_layout.dart';
import '../../widgets/settings_pane.dart';
import '../state/account_editor_state.dart';
import '../widgets/account_model_card.dart';
import '../widgets/custom_model_fields.dart';

class AccountEditorView extends StatelessWidget {
  const AccountEditorView({
    required this.state,
    required this.errors,
    required this.onCancel,
    required this.onSave,
    required this.onTemplate,
    required this.onName,
    required this.onBaseUrl,
    required this.onPricing,
    required this.onSecret,
    required this.onSecretIntent,
    required this.onAddModel,
    required this.onModel,
    required this.onRemoveModel,
    required this.onConnection,
    super.key,
  });
  final AccountEditorViewState state;
  final List<String> errors;
  final VoidCallback onCancel;
  final VoidCallback onSave;
  final ValueChanged<String> onTemplate;
  final ValueChanged<String> onName;
  final ValueChanged<String> onBaseUrl;
  final ValueChanged<bool> onPricing;
  final ValueChanged<String> onSecret;
  final ValueChanged<AccountSecretIntent> onSecretIntent;
  final VoidCallback onAddModel;
  final void Function(int rowId, CustomModelField field, String raw) onModel;
  final ValueChanged<int> onRemoveModel;
  final void Function(String modelId, String connection) onConnection;

  @override
  Widget build(BuildContext context) {
    final editable =
        !state.saving &&
        !(state.saveAction?.preventsResubmission ?? false) &&
        !(state.defaultAction?.preventsResubmission ?? false);
    final template = state.templates.templates
        .where((item) => item.id == state.templateId)
        .firstOrNull;
    final models = !state.templatePreview && state.catalog != null
        ? state.catalog!.effectiveModels
        : state.templates.modelCatalogs[template?.modelCatalogId]?.models ??
              <ModelDescriptor>[];
    return Column(
      children: [
        Expanded(
          child: ListView(
            key: StudioDriverKeys.accountEditorScroll,
            children: [
              SettingsHeader(
                title: state.create
                    ? context.l10n.settingsNewAccount
                    : state.name,
                subtitle: state.baseUrl,
              ),
              if (errors.isNotEmpty) ...[
                const SizedBox(height: 12),
                SettingsInlineError(message: errors.join('\n')),
              ],
              SettingsSection(
                title: context.l10n.settingsAccountConnectionTitle,
                children: [
                  SettingsResponsiveFieldGrid(
                    children: [
                      DropdownMenu<String>(
                        key: StudioDriverKeys.accountTemplate,
                        initialSelection: state.templateId ?? '',
                        label: Text(context.l10n.settingsAccountTemplate),
                        expandedInsets: EdgeInsets.zero,
                        enabled: editable,
                        dropdownMenuEntries: [
                          if (template == null)
                            DropdownMenuEntry(
                              value: state.templateId ?? '',
                              enabled: false,
                              label:
                                  state.templateId ??
                                  context.l10n.settingsCustomAccount,
                            ),
                          for (final item in state.templates.templates)
                            DropdownMenuEntry(
                              value: item.id,
                              label: item.displayName,
                              labelWidget: Row(
                                children: [
                                  AccountBrandMark(
                                    iconKey: item.iconKey,
                                    fallbackName: item.displayName,
                                    size: 18,
                                  ),
                                  const SizedBox(width: 8),
                                  Flexible(child: Text(item.displayName)),
                                ],
                              ),
                            ),
                        ],
                        onSelected: (value) {
                          if (value != null) onTemplate(value);
                        },
                      ),
                      SettingsFormField(
                        value: state.name,
                        label: context.l10n.settingsDisplayName,
                        onChanged: onName,
                        enabled: editable,
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  SettingsFormField(
                    key: StudioDriverKeys.accountBaseUrl,
                    value: state.baseUrl,
                    label: context.l10n.settingsBaseUrl,
                    onChanged: onBaseUrl,
                    enabled: editable,
                  ),
                  const SizedBox(height: 10),
                  SettingsFormField(
                    key: StudioDriverKeys.accountApiKey,
                    value: state.secretRaw,
                    obscureText: true,
                    label: state.hasBearerToken
                        ? context.l10n.settingsApiKeyKeepCurrent
                        : (!state.templatePreview && state.catalog != null
                              ? state.catalog!.credentialRequired
                              : (template?.credential.envVar?.isNotEmpty ??
                                    false))
                        ? context.l10n.settingsApiKey
                        : context.l10n.settingsApiKeyOptional,
                    enabled: editable,
                    onChanged: onSecret,
                    error:
                        state.validation.containsKey(AccountEditorField.secret)
                        ? context.l10n.settingsAgentProfileRequired
                        : null,
                  ),
                  if (template?.credential.envVar case final env?)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        env,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                  Wrap(
                    spacing: 8,
                    children: [
                      TextButton(
                        onPressed: editable
                            ? () => onSecretIntent(AccountSecretIntent.preserve)
                            : null,
                        child: Text(context.l10n.settingsApiKeyKeepCurrent),
                      ),
                      TextButton.icon(
                        onPressed: editable
                            ? () => onSecretIntent(AccountSecretIntent.clear)
                            : null,
                        icon: Icon(
                          state.secretIntent == AccountSecretIntent.clear
                              ? Icons.check
                              : Icons.delete_outline,
                        ),
                        label: Text(
                          context.l10n.settingsRemoveManualModelConfirmAction,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              SwitchListTile(
                key: StudioDriverKeys.accountPricing,
                title: Text(context.l10n.settingsPricingEnabled),
                subtitle: Text(context.l10n.settingsPricingHelp),
                value: state.pricingEnabled,
                onChanged: editable ? onPricing : null,
              ),
              for (final origin in [ModelOrigin.online, ModelOrigin.bundled])
                SettingsSection(
                  title: origin == ModelOrigin.online
                      ? context.l10n.settingsAccountOnlineModelsTitle
                      : context.l10n.settingsAccountDefaultModelsTitle,
                  children: [
                    if (!models.any((model) => model.origin == origin))
                      Text(
                        origin == ModelOrigin.online
                            ? context.l10n.settingsNoOnlineModels
                            : context.l10n.settingsNoBundledModels,
                      ),
                    for (final model in models.where(
                      (model) => model.origin == origin,
                    ))
                      AccountModelCard(
                        accountId: state.accountId,
                        model: model,
                        connectionMode:
                            state.connectionEdits[model.modelId] ??
                            state.canonical?.modelConnectionModes
                                .where((item) => item.modelId == model.modelId)
                                .firstOrNull
                                ?.connectionMode ??
                            model.transport.defaultConnectionMode,
                        onConnection: editable
                            ? (value) => onConnection(model.modelId, value)
                            : null,
                      ),
                  ],
                ),
              SettingsSection(
                title: context.l10n.settingsAccountCustomModelsTitle,
                children: [
                  Align(
                    alignment: Alignment.centerLeft,
                    child: OutlinedButton.icon(
                      key: StudioDriverKeys.accountModelAdd,
                      onPressed: editable ? onAddModel : null,
                      icon: const Icon(Icons.add),
                      label: Text(context.l10n.settingsAddModel),
                    ),
                  ),
                  if (state.customModels.isEmpty)
                    Text(context.l10n.settingsNoCustomModels),
                  for (
                    var index = 0;
                    index < state.customModels.length;
                    index++
                  )
                    CustomModelFields(
                      key: ValueKey((
                        state.formGeneration,
                        state.customModels[index].rowId,
                      )),
                      index: index,
                      state: state.customModels[index],
                      enabled: editable,
                      onChanged: (field, raw) =>
                          onModel(state.customModels[index].rowId, field, raw),
                      onRemove: () =>
                          onRemoveModel(state.customModels[index].rowId),
                    ),
                ],
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
        Align(
          alignment: Alignment.centerRight,
          child: Wrap(
            spacing: 8,
            children: [
              OutlinedButton.icon(
                key: StudioDriverKeys.accountCancel,
                onPressed: state.saving ? null : onCancel,
                icon: const Icon(Icons.close),
                label: Text(context.l10n.settingsCancel),
              ),
              FilledButton.icon(
                key: StudioDriverKeys.accountSave,
                onPressed: editable ? onSave : null,
                icon: const Icon(Icons.save_outlined),
                label: Text(context.l10n.settingsSave),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
