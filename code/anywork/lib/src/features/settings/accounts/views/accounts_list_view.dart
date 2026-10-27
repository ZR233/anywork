import 'package:flutter/material.dart';

import '../../../../l10n/app_localizations.dart';
import '../../../../shared/account_brand.dart';
import '../state/account_presentations.dart';
import '../state/account_view_key_values.dart';
import '../widgets/account_sections.dart';
import '../widgets/account_usage_view.dart';

/// Main settings content only. Search and scroll restoration are caller-owned.
class AccountsListView extends StatelessWidget {
  const AccountsListView({
    required this.value,
    required this.onSearchChanged,
    required this.onAdd,
    required this.onRefreshAll,
    required this.onOpen,
    required this.onRowAction,
    required this.onRetry,
    this.scrollController,
    super.key,
  });
  final AccountsListPresentation value;
  final ValueChanged<String> onSearchChanged;
  final VoidCallback onAdd;
  final VoidCallback onRefreshAll;
  final ValueChanged<AccountDisplayKey> onOpen;
  final void Function(AccountDisplayKey, AccountRowAction) onRowAction;
  final VoidCallback onRetry;
  final ScrollController? scrollController;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return ListView(
      key: const PageStorageKey<String>('accounts-list'),
      controller: scrollController,
      padding: const EdgeInsets.all(24),
      children: [
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 16,
          runSpacing: 12,
          children: [
            Text(
              l10n.settingsAccountsTitle,
              style: Theme.of(context).textTheme.headlineLarge
                  ?.copyWith(fontWeight: FontWeight.w800),
            ),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  style: accountActionButtonStyle(context),
                  onPressed: value.canRefresh ? onRefreshAll : null,
                  icon: const Icon(Icons.refresh),
                  label: Text(l10n.settingsRefreshUsage),
                ),
                FilledButton.icon(
                  style: accountActionButtonStyle(context),
                  key: const ValueKey<String>('account-add'),
                  onPressed: value.canAdd ? onAdd : null,
                  icon: const Icon(Icons.add),
                  label: Text(l10n.settingsAddAccount),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 20),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: AccountRawTextField(
              key: const ValueKey<String>('accounts-search'),
              value: AccountTextPresentation(raw: value.search),
              label: l10n.settingsSearchAccounts,
              prefixIcon: const Icon(Icons.search),
              onChanged: onSearchChanged,
            ),
          ),
        ),
        const SizedBox(height: 24),
        if (value.refreshing || value.phase == AccountListPhase.loading) ...[
          const LinearProgressIndicator(minHeight: 2),
          const SizedBox(height: 12),
        ],
        if (value.error != null || value.phase == AccountListPhase.failed)
          AccountInlineError(
            message: value.error ?? l10n.settingsAccountCatalogUnavailable,
            onRetry: onRetry,
          ),
        if (value.rows.isEmpty && value.phase != AccountListPhase.failed)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 48),
            child: Column(
              children: [
                Icon(
                  value.searchHasNoResults
                      ? Icons.search_off
                      : Icons.cloud_outlined,
                  size: 40,
                ),
                const SizedBox(height: 16),
                Text(
                  value.phase == AccountListPhase.loading
                      ? l10n.accountsLoading
                      : value.searchHasNoResults
                      ? l10n.settingsNoAccountsMatchTitle
                      : l10n.settingsNoAccountsTitle,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                if (value.phase != AccountListPhase.loading) ...[
                  const SizedBox(height: 8),
                  Text(
                    value.searchHasNoResults
                        ? l10n.settingsNoAccountsMatchMessage
                        : l10n.settingsNoAccountsMessage,
                    textAlign: TextAlign.center,
                  ),
                  if (value.searchHasNoResults)
                    TextButton(
                      onPressed: () => onSearchChanged(''),
                      child: Text(l10n.accountsClearSearch),
                    ),
                ],
              ],
            ),
          ),
        if (value.rows.isNotEmpty)
          LayoutBuilder(
            builder: (context, constraints) {
              // Main-area width, not window width: the settings sidebar is external.
              final wide =
                  constraints.maxWidth >=
                  880 * MediaQuery.textScalerOf(context).scale(1).clamp(1, 1.3);
              return Card(
                color: accountGroupSurface(context),
                clipBehavior: Clip.antiAlias,
                child: Column(
                  children: [
                    if (wide)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
                        child: DefaultTextStyle.merge(
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                flex: 7,
                                child: Text(l10n.settingsAccountsTitle),
                              ),
                              Expanded(
                                flex: 4,
                                child: Text(l10n.accountsStatusColumn),
                              ),
                              Expanded(
                                flex: 12,
                                child: Text(l10n.accountsBalanceColumn),
                              ),
                              const SizedBox(width: 48),
                            ],
                          ),
                        ),
                      ),
                    for (var i = 0; i < value.rows.length; i++) ...[
                      if (i > 0 || wide) const Divider(height: 1),
                      _AccountRow(
                        value: value.rows[i],
                        wide: wide,
                        selected:
                            value.selectedKey == value.rows[i].key ||
                            value.editingKey == value.rows[i].key,
                        onOpen: () => onOpen(value.rows[i].key),
                        onAction: (action) =>
                            onRowAction(value.rows[i].key, action),
                      ),
                    ],
                  ],
                ),
              );
            },
          ),
      ],
    );
  }
}

class _AccountRow extends StatelessWidget {
  const _AccountRow({
    required this.value,
    required this.wide,
    required this.selected,
    required this.onOpen,
    required this.onAction,
  });
  final AccountRowPresentation value;
  final bool wide;
  final bool selected;
  final VoidCallback onOpen;
  final ValueChanged<AccountRowAction> onAction;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final identity = Row(
      children: [
        AccountBrandMark(
          fallbackName: value.name,
          iconKey: value.iconKey,
          size: 64,
          active: value.isDefault,
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 10,
                runSpacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    value.name,
                    style: Theme.of(context).textTheme.titleLarge
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  if (value.isDefault)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.surfaceContainer,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Text(
                        l10n.settingsDefaultBadge,
                        style: Theme.of(context).textTheme.bodyLarge
                            ?.copyWith(fontSize: 16),
                      ),
                    ),
                ],
              ),
              if (value.operationError case final error?)
                AccountInlineError(message: error),
            ],
          ),
        ),
      ],
    );
    final status = value.key.kind == AccountKind.acp
        ? AccountStatusBadge(
            label: value.acpStatus ?? l10n.acpAccountProviderChip,
          )
        : AccountBillingBadge(
            billing: value.billing ?? AccountBilling.unknown,
            health: value.usage?.balanceHealth ?? AccountBalanceHealth.unknown,
          );
    final usage = value.key.kind == AccountKind.native && value.usage != null
        ? AccountUsageView(
            value: value.usage!,
            compact: true,
            onRetry: () => onAction(AccountRowAction.refresh),
          )
        : const SizedBox.shrink();
    // Menu is a sibling of the detail target: opening/actions never bubble to it.
    final menu = AccountMenuButton(
      buttonKey: ValueKey<String>(
        AccountViewKeyValues.rowMenu(value.key.kind.name, value.key.id),
      ),
      tooltip: l10n.settingsAccountActions,
      menuChildren: [
        for (final action in value.actions)
          MenuItemButton(
            onPressed: () => onAction(action),
            child: Text(switch (action) {
              AccountRowAction.refresh => l10n.settingsRefreshUsage,
              AccountRowAction.setDefault => l10n.settingsSetAsDefaultAccount,
              AccountRowAction.edit => l10n.settingsEditAccount,
              AccountRowAction.delete => l10n.settingsDeleteAccount,
            }),
          ),
      ],
    );
    return ColoredBox(
      color: selected
          ? Theme.of(context).colorScheme.surfaceContainerHigh
          : Colors.transparent,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
        child: wide
            ? Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    flex: 7,
                    child: InkWell(
                      key: ValueKey<String>(
                        AccountViewKeyValues.row(
                          value.key.kind.name,
                          value.key.id,
                        ),
                      ),
                      onTap: onOpen,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: identity,
                      ),
                    ),
                  ),
                  Expanded(
                    flex: 4,
                    child: Padding(
                      padding: const EdgeInsets.only(right: 12),
                      child: status,
                    ),
                  ),
                  Expanded(flex: 12, child: usage),
                  SizedBox(width: 48, child: menu),
                ],
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: InkWell(
                          key: ValueKey<String>(
                            AccountViewKeyValues.row(
                              value.key.kind.name,
                              value.key.id,
                            ),
                          ),
                          onTap: onOpen,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            child: identity,
                          ),
                        ),
                      ),
                      menu,
                    ],
                  ),
                  const SizedBox(height: 12),
                  status,
                  const SizedBox(height: 12),
                  usage,
                ],
              ),
      ),
    );
  }
}
