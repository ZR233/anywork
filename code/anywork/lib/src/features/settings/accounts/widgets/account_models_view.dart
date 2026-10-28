import 'package:flutter/material.dart';

import '../../../../l10n/app_localizations.dart';
import '../state/account_presentations.dart';
import '../state/account_view_key_values.dart';
import 'account_compact_view.dart';
import 'account_sections.dart';
import 'account_editor_fields.dart';

export 'account_compact_view.dart';

/// Narrow model intents shared by detail and editor views. Never a reducer.
@immutable
class AccountModelActions {
  const AccountModelActions({
    required this.onEnabledChanged,
    required this.onConnectionChanged,
    required this.onCompactChanged,
    required this.onCompactPreset,
    required this.onAction,
  });
  final void Function(AccountModelKey key, bool enabled) onEnabledChanged;
  final void Function(AccountModelKey key, AccountConnection connection)
  onConnectionChanged;
  final void Function(AccountModelKey key, String raw) onCompactChanged;
  final void Function(AccountModelKey key, int percent) onCompactPreset;
  final void Function(AccountModelKey key, AccountModelAction action) onAction;
}

class AccountModelsView extends StatelessWidget {
  const AccountModelsView({
    required this.value,
    required this.actions,
    required this.onSync,
    this.onAddModel,
    super.key,
  });
  final AccountCatalogPresentation value;
  final AccountModelActions actions;
  final VoidCallback onSync;
  final VoidCallback? onAddModel;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          spacing: 12,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Wrap(
              spacing: 16,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  l10n.settingsAccountModelsTitle,
                  style: Theme.of(context).textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
                if (onAddModel != null)
                  TextButton.icon(
                    key: const ValueKey('account-model-add'),
                    onPressed: onAddModel,
                    icon: const Icon(Icons.add, size: 18),
                    label: Text(l10n.settingsAddModel),
                  ),
                if (value.canSync || value.canRetry)
                  OutlinedButton.icon(
                    style: accountActionButtonStyle(context),
                    key: const ValueKey<String>('account-model-sync'),
                    onPressed: value.syncing ? null : onSync,
                    icon: const Icon(Icons.sync),
                    label: Text(
                      value.syncing
                          ? l10n.accountsSyncingModels
                          : value.error != null
                          ? l10n.accountsRetry
                          : l10n.accountsSyncModels,
                    ),
                  ),
              ],
            ),
            if (value.sourceLabel != null || value.checkedLabel != null)
              Wrap(
                spacing: 16,
                runSpacing: 4,
                alignment: WrapAlignment.end,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  if (value.sourceLabel != null)
                    Text(
                      '${l10n.accountsSource} · ${value.sourceLabel}',
                      style: Theme.of(context).textTheme.bodyMedium
                          ?.copyWith(fontSize: 14),
                    ),
                  if (value.checkedLabel != null)
                    Text(
                      '${l10n.settingsModelCatalogChecked} ${value.checkedLabel}',
                      style: Theme.of(context).textTheme.bodyMedium
                          ?.copyWith(fontSize: 14),
                    ),
                ],
              ),
          ],
        ),
        if (!value.canSync && !value.canRetry && !value.syncing)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(
              l10n.accountsSyncUnsupported,
              style: Theme.of(context).textTheme.bodyLarge,
            ),
          ),
        if (value.syncing) const LinearProgressIndicator(minHeight: 2),
        if (value.error != null)
          AccountInlineError(
            message: value.error!,
            onRetry: value.canRetry && !value.syncing ? onSync : null,
          ),
        if (value.models.isEmpty)
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              l10n.settingsModelCatalogEmpty,
              style: Theme.of(context).textTheme.bodyLarge,
            ),
          ),
        for (final origin in AccountModelOrigin.values)
          if (value.models.any((model) => model.origin == origin)) ...[
            Padding(
              padding: const EdgeInsets.only(top: 16, bottom: 8),
              child: Text(switch (origin) {
                AccountModelOrigin.online =>
                  l10n.settingsAccountOnlineModelsTitle,
                AccountModelOrigin.bundled => l10n.settingsModelCatalogDefault,
                AccountModelOrigin.manual =>
                  l10n.settingsAccountCustomModelsTitle,
              }, style: Theme.of(context).textTheme.bodyLarge),
            ),
            Card(
              color: accountGroupSurface(context),
              clipBehavior: Clip.antiAlias,
              child: Column(
                children: [
                  for (final model in value.models.where(
                    (model) => model.origin == origin,
                  ))
                    AccountModelListItem(
                      key: ValueKey<String>(
                        AccountViewKeyValues.modelItem(
                          model.key.account.kind.name,
                          model.key.account.id,
                          model.key.modelId,
                        ),
                      ),
                      value: model,
                      actions: actions,
                    ),
                ],
              ),
            ),
          ],
      ],
    );
  }
}

/// A catalog row owns expansion geometry only, not model facts or draft state.
class AccountModelListItem extends StatelessWidget {
  const AccountModelListItem({
    required this.value,
    required this.actions,
    this.initiallyExpanded = false,
    super.key,
  });
  final AccountModelPresentation value;
  final AccountModelActions actions;
  final bool initiallyExpanded;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return LayoutBuilder(
      builder: (context, constraints) => ExpansionTile(
        key: PageStorageKey<String>(
          AccountViewKeyValues.modelDetails(
            value.key.account.kind.name,
            value.key.account.id,
            value.key.modelId,
          ),
        ),
        initiallyExpanded: initiallyExpanded,
        maintainState: true,
        controlAffinity: ListTileControlAffinity.leading,
        tilePadding: const EdgeInsetsDirectional.only(start: 8, end: 12),
        childrenPadding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        title: Text(value.name, style: Theme.of(context).textTheme.titleSmall),
        subtitle: value.summary == null || value.summary!.isEmpty
            ? null
            : Text(
                value.summary!,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall,
              ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (constraints.maxWidth >= 600)
              TextButton.icon(
                key: ValueKey(
                  AccountViewKeyValues.modelReadout(
                    value.key.account.kind.name,
                    value.key.account.id,
                    value.key.modelId,
                  ),
                ),
                onPressed: value.canLoadReadout
                    ? () => actions.onAction(
                        value.key,
                        AccountModelAction.loadReadout,
                      )
                    : null,
                icon: const Icon(Icons.north_east, size: 16),
                label: Text(l10n.accountsModelDetails),
              )
            else
              IconButton(
                key: ValueKey(
                  AccountViewKeyValues.modelReadout(
                    value.key.account.kind.name,
                    value.key.account.id,
                    value.key.modelId,
                  ),
                ),
                tooltip: l10n.accountsModelDetails,
                onPressed: value.canLoadReadout
                    ? () => actions.onAction(
                        value.key,
                        AccountModelAction.loadReadout,
                      )
                    : null,
                icon: const Icon(Icons.north_east, size: 18),
              ),
            Semantics(
              label: '${l10n.settingsModelEnabled} · ${value.name}',
              child: Switch(
                key: ValueKey(
                  AccountViewKeyValues.modelEnabled(
                    value.key.account.kind.name,
                    value.key.account.id,
                    value.key.modelId,
                  ),
                ),
                value: value.enabled,
                onChanged: value.canToggle && !value.saving
                    ? (enabled) => actions.onEnabledChanged(value.key, enabled)
                    : null,
              ),
            ),
          ],
        ),
        children: [
          const Divider(height: 1),
          const SizedBox(height: 12),
          if (value.saving) const LinearProgressIndicator(minHeight: 2),
          if (value.error != null) AccountInlineError(message: value.error!),
          if (value.allowedConnections
                  .where((item) => item != AccountConnection.automatic)
                  .length >
              1) ...[
            AccountConnectionControl(
              value: value.connection ?? AccountConnection.automatic,
              allowed: value.allowedConnections,
              enabled: !value.saving,
              onChanged: (connection) =>
                  actions.onConnectionChanged(value.key, connection),
            ),
            const SizedBox(height: 12),
          ],
          if (value.compact case final compact?)
            AccountCompactView(
              value: compact,
              onChanged: (raw) => actions.onCompactChanged(value.key, raw),
              onPreset: (percent) =>
                  actions.onCompactPreset(value.key, percent),
              onSave: () =>
                  actions.onAction(value.key, AccountModelAction.saveCompact),
              onReset: () =>
                  actions.onAction(value.key, AccountModelAction.resetCompact),
              onRetry: () =>
                  actions.onAction(value.key, AccountModelAction.retryCompact),
            ),
          if (value.origin == AccountModelOrigin.manual)
            Wrap(
              spacing: 8,
              children: [
                if (value.canEdit)
                  TextButton.icon(
                    onPressed: () =>
                        actions.onAction(value.key, AccountModelAction.edit),
                    icon: const Icon(Icons.edit_outlined),
                    label: Text(l10n.settingsEdit),
                  ),
                if (value.canDelete)
                  TextButton.icon(
                    onPressed: () =>
                        actions.onAction(value.key, AccountModelAction.delete),
                    icon: const Icon(Icons.delete_outline),
                    label: Text(l10n.settingsRemoveModel),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}
