import 'package:flutter/material.dart';

import '../../../../l10n/app_localizations.dart';
import '../state/account_presentations.dart';
import '../widgets/account_sections.dart';
import '../widgets/account_list_item.dart';

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
    final heading = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.settingsAccountsTitle,
          style: Theme.of(context).textTheme.headlineMedium
              ?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        Text(
          l10n.accountsListHint,
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      ],
    );
    final actions = Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        FilledButton.tonalIcon(
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
    );
    return ListView(
      key: const PageStorageKey<String>('accounts-list'),
      controller: scrollController,
      padding: const EdgeInsets.all(24),
      children: [
        LayoutBuilder(
          builder: (context, constraints) =>
              constraints.maxWidth >=
                  760 * MediaQuery.textScalerOf(context).scale(1)
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: heading),
                    const SizedBox(width: 16),
                    actions,
                  ],
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [heading, const SizedBox(height: 16), actions],
                ),
        ),
        const SizedBox(height: 20),
        LayoutBuilder(
          builder: (context, constraints) => Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 16,
            runSpacing: 8,
            children: [
              SizedBox(
                width: constraints.maxWidth < 600
                    ? constraints.maxWidth * .62
                    : 300,
                child: AccountRawTextField(
                  key: const ValueKey<String>('accounts-search'),
                  value: AccountTextPresentation(raw: value.search),
                  label: l10n.settingsSearchAccounts,
                  prefixIcon: const Icon(Icons.search),
                  onChanged: onSearchChanged,
                ),
              ),
              if (value.phase == AccountListPhase.ready)
                Text(
                  l10n.accountsVisibleCount(value.rows.length),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
            ],
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
                  760 * MediaQuery.textScalerOf(context).scale(1).clamp(1, 1.3);
              return Card(
                margin: EdgeInsets.zero,
                color: accountGroupSurface(context),
                clipBehavior: Clip.antiAlias,
                child: Column(
                  children: [
                    if (wide)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 10, 20, 10),
                        child: DefaultTextStyle.merge(
                          style: const TextStyle(
                            fontSize: 12,
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
                      AccountListItem(
                        value: value.rows[i],
                        layout: wide
                            ? AccountItemLayout.columns
                            : AccountItemLayout.stacked,
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
