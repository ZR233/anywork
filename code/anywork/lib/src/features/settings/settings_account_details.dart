import 'package:flutter/material.dart';

import '../../domain/models/studio_models.dart';
import '../../l10n/studio_l10n.dart';
import '../../shared/account_brand.dart';
import '../../shared/studio_driver_keys.dart';
import 'settings_common.dart';
import 'settings_account_model_readout.dart';
import 'settings_account_usage.dart';
import 'settings_model_catalog.dart';
import 'settings_account_auto_compact.dart';
import 'settings_account_selection.dart';

class AccountDetails extends StatelessWidget {
  const AccountDetails({
    super.key,
    required this.account,
    required this.usage,
    required this.usageLoading,
    required this.usageError,
    required this.onBack,
    required this.onEdit,
    required this.onRefreshUsage,
    required this.autoCompactEdits,
    required this.onAutoCompactChanged,
    required this.onAutoCompactCommit,
    required this.onAutoCompactInvalid,
    required this.onRemoveManualModel,
  });

  final AccountSettingsView? account;
  final AccountUsageView? usage;
  final bool usageLoading;
  final String? usageError;
  final VoidCallback onBack;
  final ValueChanged<AccountSettingsView> onEdit;
  final VoidCallback? onRefreshUsage;
  final Map<String, ModelAutoCompactEdit> autoCompactEdits;
  final void Function(String modelId, int? value) onAutoCompactChanged;
  final ValueChanged<String> onAutoCompactCommit;
  final ValueChanged<String> onAutoCompactInvalid;
  final ValueChanged<AccountModelView> onRemoveManualModel;

  @override
  Widget build(BuildContext context) {
    final account = this.account;
    if (account == null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextButton.icon(
            icon: const Icon(Icons.arrow_back),
            label: Text(context.l10n.settingsAccountsTitle),
            onPressed: onBack,
          ),
          Expanded(
            child: Center(child: Text(context.l10n.settingsNoAccountSelected)),
          ),
        ],
      );
    }
    return ListView(
      key: StudioDriverKeys.accountEditor,
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            icon: const Icon(Icons.arrow_back),
            label: Text(context.l10n.settingsAccountsTitle),
            onPressed: onBack,
          ),
        ),
        const SizedBox(height: 4),
        SettingsHeader(
          title: account.name,
          subtitle: account.baseUrl,
          leading: AccountBrandMark(
            iconKey: account.iconKey,
            fallbackName: account.name,
          ),
          trailing: FilledButton.tonalIcon(
            key: StudioDriverKeys.accountEdit,
            icon: const Icon(Icons.edit_outlined),
            label: Text(context.l10n.settingsEdit),
            onPressed: () => onEdit(account),
          ),
        ),
        const SizedBox(height: 12),
        AccountUsagePanel(
          account: account,
          usage: usage,
          loading: usageLoading,
          error: usageError,
          onRefresh: onRefreshUsage ?? () {},
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            SettingsAccountStatusChip(account: account, usage: usage),
            SettingsInfoPill(
              icon: Icons.hub_outlined,
              label: account.models
                  .map((model) => context.modelWireApiLabel(model.wireApi))
                  .toSet()
                  .join(' / '),
            ),
            SettingsInfoPill(
              icon: Icons.memory_outlined,
              label: account.modelCount,
            ),
          ],
        ),
        const SizedBox(height: 16),
        SettingsSectionPanel(
          title: context.l10n.settingsAccountTitle,
          children: [
            SettingsReadout(
              label: context.l10n.settingsAccountId,
              value: account.id,
            ),
            SettingsReadout(
              label: context.l10n.settingsAccountTemplate,
              value: account.templateId == null || account.templateId!.isEmpty
                  ? context.l10n.settingsCustomAccount
                  : account.templateId!,
            ),
            SettingsReadout(
              label: context.l10n.settingsApiKey,
              value: account.hasBearerToken
                  ? context.l10n.settingsConfigured
                  : context.l10n.settingsMissing,
            ),
          ],
        ),
        const SizedBox(height: 12),
        SettingsSectionPanel(
          title: context.l10n.settingsAccountModelsTitle,
          children: [
            AccountBillingControl(account: account),
            if (account.modelCatalog.supported)
              ModelCatalogReadout(status: account.modelCatalog),
            if (account.models.isEmpty)
              Text(context.l10n.settingsModelCatalogEmpty)
            else ...[
              _originSection(
                context,
                title: context.l10n.settingsAccountOnlineModelsTitle,
                emptyLabel: context.l10n.settingsNoOnlineModels,
                models: account.onlineModels,
                account: account,
              ),
              _originSection(
                context,
                title: context.l10n.settingsAccountDefaultModelsTitle,
                emptyLabel: context.l10n.settingsNoBundledModels,
                models: account.bundledModels,
                account: account,
              ),
              _originSection(
                context,
                title: context.l10n.settingsAccountCustomModelsTitle,
                emptyLabel: context.l10n.settingsNoCustomModels,
                models: account.customModels,
                account: account,
                onRemove: onRemoveManualModel,
              ),
            ],
          ],
        ),
      ],
    );
  }

  Widget _originSection(
    BuildContext context, {
    required String title,
    required String emptyLabel,
    required List<AccountModelView> models,
    required AccountSettingsView account,
    ValueChanged<AccountModelView>? onRemove,
  }) {
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          if (models.isEmpty)
            Text(emptyLabel)
          else
            for (final model in models)
              AccountModelReadout(
                key: ValueKey((account.id, model.modelId)),
                model: model,
                accountId: account.id,
                managementControls: AccountModelSelectionControl(
                  accountId: account.id,
                  model: model,
                ),
                framed: true,
                autoCompact: account.autoCompactLimitFor(model),
                autoCompactEdit: autoCompactEdits[model.modelId],
                onAutoCompactChanged: (value) =>
                    onAutoCompactChanged(model.modelId, value),
                onAutoCompactCommit: () => onAutoCompactCommit(model.modelId),
                onAutoCompactInvalid: () => onAutoCompactInvalid(model.modelId),
                onDelete: onRemove == null ? null : () => onRemove(model),
              ),
        ],
      ),
    );
  }
}
