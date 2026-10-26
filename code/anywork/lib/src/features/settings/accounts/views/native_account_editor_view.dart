import 'package:flutter/material.dart';

import '../../../../l10n/app_localizations.dart';
import '../state/account_presentations.dart';
import '../state/account_view_key_values.dart';
import '../widgets/account_models_view.dart';
import '../widgets/account_sections.dart';

class NativeAccountEditorView extends StatelessWidget {
  const NativeAccountEditorView({
    required this.value,
    required this.onFieldChanged,
    required this.onTemplateChanged,
    required this.onBillingChanged,
    required this.onResetBilling,
    required this.onAddModel,
    required this.onManualModelFieldChanged,
    required this.onManualModelConnectionChanged,
    required this.onManualModelWireApiChanged,
    required this.onRemoveManualModel,
    required this.modelActions,
    required this.onSave,
    required this.onCancel,
    this.scrollController,
    super.key,
  });
  final NativeAccountEditorPresentation value;
  final void Function(NativeAccountField field, String raw) onFieldChanged;
  final ValueChanged<AccountTemplateKey> onTemplateChanged;
  final ValueChanged<AccountBilling> onBillingChanged;
  final VoidCallback onResetBilling;
  final VoidCallback onAddModel;
  final void Function(String editorKey, ManualModelField field, String raw)
  onManualModelFieldChanged;
  final void Function(String editorKey, AccountConnection connection)
  onManualModelConnectionChanged;
  final void Function(String editorKey, AccountWireApi wireApi)
  onManualModelWireApiChanged;
  final ValueChanged<String> onRemoveManualModel;
  final AccountModelActions modelActions;
  final VoidCallback onSave;
  final VoidCallback onCancel;
  final ScrollController? scrollController;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: ListView(
            key: PageStorageKey<String>(
              AccountViewKeyValues.editorScroll(
                AccountKind.native.name,
                value.editorId,
              ),
            ),
            controller: scrollController,
            padding: const EdgeInsets.all(24),
            children: [
              Text(
                value.accountKey == null
                    ? l10n.settingsNewAccount
                    : l10n.settingsEditAccount,
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              if (value.dirty)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    l10n.accountsDirty,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              const SizedBox(height: 24),
              if (value.error != null)
                AccountInlineError(message: value.error!),
              AccountSection(
                title: l10n.settingsAccountConnectionTitle,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      l10n.settingsAccountTemplate,
                      style: Theme.of(context).textTheme.labelLarge,
                    ),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final template in value.templates)
                          ChoiceChip(
                            label: Text(template.name),
                            selected: template.key == value.templateKey,
                            onSelected: value.canChangeTemplate && !value.saving
                                ? (_) => onTemplateChanged(template.key)
                                : null,
                          ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    AccountRawTextField(
                      key: ValueKey<String>(
                        AccountViewKeyValues.editorField(
                          value.editorId,
                          NativeAccountField.name.name,
                        ),
                      ),
                      value: value.name,
                      label: l10n.settingsDisplayName,
                      onChanged: (raw) =>
                          onFieldChanged(NativeAccountField.name, raw),
                    ),
                    const SizedBox(height: 16),
                    AccountRawTextField(
                      key: ValueKey<String>(
                        AccountViewKeyValues.editorField(
                          value.editorId,
                          NativeAccountField.endpoint.name,
                        ),
                      ),
                      value: value.endpoint,
                      label: l10n.settingsBaseUrl,
                      keyboardType: TextInputType.url,
                      onChanged: (raw) =>
                          onFieldChanged(NativeAccountField.endpoint, raw),
                    ),
                    const SizedBox(height: 16),
                    AccountRawTextField(
                      key: ValueKey<String>(
                        AccountViewKeyValues.editorField(
                          value.editorId,
                          NativeAccountField.credential.name,
                        ),
                      ),
                      value: value.credential,
                      label: value.hasStoredCredential
                          ? l10n.settingsApiKeyKeepCurrent
                          : value.credentialRequired
                          ? l10n.settingsApiKey
                          : l10n.settingsApiKeyOptional,
                      obscure: true,
                      onChanged: (raw) =>
                          onFieldChanged(NativeAccountField.credential, raw),
                    ),
                    AccountFacts(
                      facts: [
                        if (value.accountKey != null)
                          AccountDisplayFact(
                            label: l10n.settingsAccountId,
                            value: value.accountKey!.id,
                          ),
                        AccountDisplayFact(
                          label: l10n.settingsAccountProtocol,
                          value: value.protocolLabel,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              AccountSection(
                title: l10n.settingsBillingKind,
                child: AccountBillingControl(
                  value: value.billing,
                  onChanged: onBillingChanged,
                  onReset: onResetBilling,
                ),
              ),
              if (value.declaredModels.isNotEmpty)
                AccountSection(
                  title: l10n.settingsAccountModelsTitle,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (final model in value.declaredModels)
                        AccountModelTile(
                          key: ValueKey<String>(
                            AccountViewKeyValues.modelItem(
                              model.key.account.kind.name,
                              model.key.account.id,
                              model.key.modelId,
                            ),
                          ),
                          value: model,
                          actions: modelActions,
                        ),
                    ],
                  ),
                ),
              AccountSection(
                title: l10n.settingsAccountCustomModelsTitle,
                actions: [
                  OutlinedButton.icon(
                    onPressed: value.canAddModel ? onAddModel : null,
                    icon: const Icon(Icons.add),
                    label: Text(l10n.settingsAddModel),
                  ),
                ],
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (value.manualModels.isEmpty)
                      Text(l10n.settingsNoCustomModels),
                    for (final model in value.manualModels)
                      Padding(
                        key: ValueKey<String>(
                          AccountViewKeyValues.manualItem(model.editorKey),
                        ),
                        padding: const EdgeInsets.only(bottom: 20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            AccountRawTextField(
                              key: ValueKey<String>(
                                AccountViewKeyValues.manualField(
                                  model.editorKey,
                                  ManualModelField.id.name,
                                ),
                              ),
                              value: model.id,
                              label: l10n.settingsModelId,
                              enabled: model.canEditId,
                              onChanged: (raw) => onManualModelFieldChanged(
                                model.editorKey,
                                ManualModelField.id,
                                raw,
                              ),
                            ),
                            const SizedBox(height: 12),
                            AccountRawTextField(
                              key: ValueKey<String>(
                                AccountViewKeyValues.manualField(
                                  model.editorKey,
                                  ManualModelField.name.name,
                                ),
                              ),
                              value: model.name,
                              label: l10n.settingsDisplayName,
                              onChanged: (raw) => onManualModelFieldChanged(
                                model.editorKey,
                                ManualModelField.name,
                                raw,
                              ),
                            ),
                            const SizedBox(height: 12),
                            AccountRawTextField(
                              key: ValueKey<String>(
                                AccountViewKeyValues.manualField(
                                  model.editorKey,
                                  ManualModelField.contextWindow.name,
                                ),
                              ),
                              value: model.contextWindow,
                              label: l10n.settingsContextBudget,
                              keyboardType: TextInputType.number,
                              onChanged: (raw) => onManualModelFieldChanged(
                                model.editorKey,
                                ManualModelField.contextWindow,
                                raw,
                              ),
                            ),
                            const SizedBox(height: 12),
                            AccountRawTextField(
                              key: ValueKey<String>(
                                AccountViewKeyValues.manualField(
                                  model.editorKey,
                                  ManualModelField.maxOutputTokens.name,
                                ),
                              ),
                              value: model.maxOutputTokens,
                              label: l10n.settingsOutputBudget,
                              keyboardType: TextInputType.number,
                              onChanged: (raw) => onManualModelFieldChanged(
                                model.editorKey,
                                ManualModelField.maxOutputTokens,
                                raw,
                              ),
                            ),
                            const SizedBox(height: 12),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                Text(l10n.settingsProtocolType),
                                for (final wireApi in model.allowedWireApis)
                                  ChoiceChip(
                                    label: Text(switch (wireApi) {
                                      AccountWireApi.chatCompletions =>
                                        l10n.settingsProtocolChatCompletionsHttp,
                                      AccountWireApi.responses =>
                                        l10n.settingsProtocolResponsesHttp,
                                    }),
                                    selected: model.wireApi == wireApi,
                                    onSelected: (_) =>
                                        onManualModelWireApiChanged(
                                          model.editorKey,
                                          wireApi,
                                        ),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                Text(l10n.accountsConnection),
                                for (final connection
                                    in model.allowedConnections)
                                  ChoiceChip(
                                    label: Text(
                                      accountConnectionLabel(l10n, connection),
                                    ),
                                    selected: model.connection == connection,
                                    onSelected: (_) =>
                                        onManualModelConnectionChanged(
                                          model.editorKey,
                                          connection,
                                        ),
                                  ),
                                if (model.canRemove)
                                  TextButton.icon(
                                    onPressed: () =>
                                        onRemoveManualModel(model.editorKey),
                                    icon: const Icon(Icons.delete_outline),
                                    label: Text(l10n.settingsRemoveModel),
                                  ),
                              ],
                            ),
                            if (model.error != null)
                              AccountInlineError(message: model.error!),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
        AccountEditorFooter(
          saving: value.saving,
          canSave: value.canSave,
          onSave: onSave,
          onCancel: onCancel,
        ),
      ],
    );
  }
}

class AccountEditorFooter extends StatelessWidget {
  const AccountEditorFooter({
    required this.saving,
    required this.canSave,
    required this.onSave,
    required this.onCancel,
    this.saveLabel,
    this.saveIsPrimary = true,
    super.key,
  });
  final bool saving;
  final bool canSave;
  final VoidCallback onSave;
  final VoidCallback onCancel;
  final String? saveLabel;
  final bool saveIsPrimary;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Material(
      color: Theme.of(context).colorScheme.surface,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Wrap(
            alignment: WrapAlignment.end,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 12,
            runSpacing: 8,
            children: [
              if (saving)
                const SizedBox.square(
                  dimension: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              OutlinedButton(
                key: const ValueKey<String>('account-cancel'),
                onPressed: onCancel,
                child: Text(l10n.commonCancel),
              ),
              if (saveIsPrimary)
                FilledButton(
                  key: const ValueKey<String>('account-save'),
                  onPressed: canSave && !saving ? onSave : null,
                  child: Text(saveLabel ?? l10n.commonSave),
                )
              else
                OutlinedButton(
                  key: const ValueKey<String>('account-save'),
                  onPressed: canSave && !saving ? onSave : null,
                  child: Text(saveLabel ?? l10n.commonSave),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
