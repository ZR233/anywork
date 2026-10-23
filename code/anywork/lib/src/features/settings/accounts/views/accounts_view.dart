import 'package:anywork_client/account_usage.dart';
import 'package:anywork_client/configuration.dart';
import 'package:anywork_client/models.dart';
import 'package:flutter/material.dart';

import '../../../../diagnostics/studio_driver_keys.dart';
import '../../../../l10n/studio_l10n.dart';
import '../../../../ui/branding/account_brand.dart';
import '../../widgets/settings_form_field.dart';
import '../../widgets/settings_pane.dart';
import '../../widgets/settings_source_status_view.dart';
import '../state/accounts_state.dart';
import '../widgets/account_usage_panel.dart';

class AccountsView extends StatelessWidget {
  const AccountsView({required this.state, required this.accounts, required this.catalogs,
    required this.usages, required this.defaultAccountId, required this.canDelete,
    required this.hasMore, required this.errors, required this.actionErrors,
    required this.onQuery, required this.onAdd, required this.onSelect,
    required this.onEdit, required this.onDefault, required this.onDelete,
    required this.onRefreshAll, required this.onRefresh, required this.onMore,
    required this.onRetry, super.key});
  final AccountsViewState state;
  final List<AccountConfiguration> accounts;
  final Map<String, AccountCatalogEntry> catalogs;
  final Map<String, AccountUsageRecord> usages;
  final String? defaultAccountId;
  final bool canDelete;
  final bool hasMore;
  final List<String> errors;
  final Map<String, List<String>> actionErrors;
  final ValueChanged<String> onQuery;
  final VoidCallback onAdd;
  final ValueChanged<String> onSelect;
  final ValueChanged<String> onEdit;
  final ValueChanged<String> onDefault;
  final ValueChanged<String> onDelete;
  final VoidCallback onRefreshAll;
  final ValueChanged<String> onRefresh;
  final VoidCallback onMore;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => SettingsPane(title: context.l10n.settingsAccountsTitle,
    subtitle: context.l10n.settingsAccountsSubtitle,
    trailing: Wrap(spacing: 8, children: [
      IconButton(key: StudioDriverKeys.accountUsageCheck, tooltip: context.l10n.settingsRefreshUsage,
        onPressed: state.refreshingAll ? null : onRefreshAll, icon: const Icon(Icons.refresh)),
      FilledButton.icon(key: StudioDriverKeys.accountAdd, onPressed: onAdd,
        icon: const Icon(Icons.add), label: Text(context.l10n.settingsAddAccount)),
    ]),
    toolbar: SettingsFormField(value: state.query, label: context.l10n.settingsSearchAccounts, onChanged: onQuery),
    child: ListView(children: [
      SettingsSourceStatusView(title: context.l10n.settingsAccountsTitle, brief: state.source.projection.header?.source.brief,
        read: state.source.sourceStatus, origin: state.source.projection.stamp?.origin,
        reference: state.source.projection.header?.source.status, onRetry: onRetry),
      SettingsSourceStatusView(title: context.l10n.settingsAccountModelsTitle, brief: state.modelSource.projection.header?.source.brief,
        read: state.modelSource.sourceStatus, origin: state.modelSource.projection.stamp?.origin,
        reference: state.modelSource.projection.header?.source.status, onRetry: onRetry),
      SettingsSourceStatusView(title: context.l10n.settingsUsageTitle, brief: state.usageSource.projection.header?.source.brief,
        read: state.usageSource.sourceStatus, origin: state.usageSource.projection.stamp?.origin,
        reference: state.usageSource.projection.header?.source.status, onRetry: onRetry),
      for (final error in errors) SelectableText(error, style: TextStyle(color: Theme.of(context).colorScheme.error)),
      if (errors.isNotEmpty) TextButton(onPressed: onRetry, child: Text(context.l10n.runtimeFatalRetry)),
      if (accounts.isEmpty && !hasMore) Padding(padding: const EdgeInsets.all(24), child: Text(state.query.trim().isNotEmpty
        ? context.l10n.settingsNoAccountsMatchMessage : context.l10n.settingsNoAccountsMessage)),
      if (accounts.isEmpty && hasMore) const Text('—'),
      for (final account in accounts) Card.outlined(key: StudioDriverKeys.accountRow(account.accountId),
        child: Padding(padding: const EdgeInsets.all(12), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          ListTile(contentPadding: EdgeInsets.zero, onTap: () => onSelect(account.accountId),
            leading: AccountBrandMark(fallbackName: account.name, iconKey: state.templates?.templates
              .where((item) => item.id == account.templateId).firstOrNull?.iconKey),
            title: Text(account.name), subtitle: Text(account.baseUrl),
            trailing: PopupMenuButton<_AccountMenuAction>(tooltip: context.l10n.settingsAccountActions,
              onSelected: (action) => switch (action) {
                _AccountMenuAction.edit => onEdit(account.accountId),
                _AccountMenuAction.defaultAccount => onDefault(account.accountId),
                _AccountMenuAction.remove => onDelete(account.accountId),
              }, itemBuilder: (context) => [
                PopupMenuItem(value: _AccountMenuAction.edit, child: Text(context.l10n.settingsEditAccount)),
                PopupMenuItem(value: _AccountMenuAction.defaultAccount,
                  enabled: defaultAccountId != account.accountId && !(state.rowActions[(account.accountId, AccountRowAction.setDefault)]?.preventsResubmission ?? false),
                  child: Text(context.l10n.settingsSetAsDefaultAccount)),
                PopupMenuItem(value: _AccountMenuAction.remove, enabled: canDelete && !state.preparingRemovalIds.contains(account.accountId) &&
                    !(state.rowActions[(account.accountId, AccountRowAction.remove)]?.preventsResubmission ?? false),
                  child: Text(context.l10n.settingsDeleteAccount)),
              ])),
          Wrap(spacing: 8, children: [
            if (defaultAccountId == account.accountId) Chip(label: Text(context.l10n.settingsDefaultBadge)),
            Chip(label: Text(account.hasBearerToken ? context.l10n.settingsConfigured : context.l10n.settingsMissing)),
            Text(context.protocolKindLabel(account.protocol)),
            if (catalogs[account.accountId] case final catalog?) Text(catalog.effectiveModels.map((model) => model.modelId).join(' · ')),
          ]),
          AccountUsagePanel(usage: usages[account.accountId], loading: state.usageChecks[account.accountId]?.operation.isPending ?? false,
            preparing: state.usageChecks[account.accountId]?.preparing ?? false,
            errors: actionErrors[account.accountId] ?? [], onRefresh: () => onRefresh(account.accountId), compact: true),
        ]))),
      if (hasMore) TextButton.icon(onPressed: state.reading.isNotEmpty ? null : onMore,
        icon: const Icon(Icons.expand_more), label: Text(context.l10n.settingsSshNextPage)),
    ]));
}

enum _AccountMenuAction { edit, defaultAccount, remove }
