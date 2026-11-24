import 'package:material_ui/material_ui.dart';

import '../../../../app/theme/studio_semantic_colors.dart';
import '../../../../l10n/app_localizations.dart';
import '../state/account_presentations.dart';
import '../state/account_view_key_values.dart';
import '../widgets/account_sections.dart';

/// Main settings content only. Search, category filter, and scroll restoration are caller-owned.
class AccountsListView extends StatelessWidget {
  const AccountsListView({
    required this.value,
    required this.onSearchChanged,
    this.onCategoryChanged,
    required this.onAdd,
    required this.onRefreshAll,
    required this.onOpen,
    required this.onRowAction,
    required this.onRetry,
    required this.cardBuilder,
    this.scrollController,
    super.key,
  });

  final AccountsListPresentation value;
  final ValueChanged<String> onSearchChanged;
  final ValueChanged<AccountListCategory>? onCategoryChanged;
  final VoidCallback onAdd;
  final VoidCallback onRefreshAll;
  final ValueChanged<AccountDisplayKey> onOpen;
  final void Function(AccountDisplayKey, AccountRowAction) onRowAction;
  final VoidCallback onRetry;
  final ScrollController? scrollController;
  final Widget Function(
    BuildContext context,
    AccountDisplayKey account,
    AccountItemLayout layout,
    VoidCallback onOpen,
    ValueChanged<AccountRowAction> onAction,
  )
  cardBuilder;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final semantic = theme.extension<StudioSemanticColors>();

    final heading = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.settingsAccountsTitle,
          style: theme.textTheme.headlineMedium?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          l10n.accountsListHint,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: scheme.onSurfaceVariant,
          ),
        ),
      ],
    );

    final actions = Wrap(
      spacing: 10,
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

    final showCategoryCounts = value.totalCount > 0;
    Widget categoryChip(AccountListCategory category, String label, int count) {
      final selected = value.category == category;
      final text = showCategoryCounts ? '$label · $count' : label;
      return ChoiceChip(
        key: ValueKey<String>(AccountViewKeyValues.categoryChip(category.name)),
        label: Text(
          text,
          style: TextStyle(
            fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
        selected: selected,
        showCheckmark: false,
        visualDensity: VisualDensity.compact,
        side: BorderSide(
          color: selected
              ? scheme.primary.withValues(alpha: 0.45)
              : scheme.outlineVariant.withValues(alpha: 0.55),
        ),
        onSelected: onCategoryChanged == null
            ? null
            : (_) => onCategoryChanged!(category),
      );
    }

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
          builder: (context, constraints) {
            final compact = constraints.maxWidth < 680;
            final searchBox = SizedBox(
              width: compact ? constraints.maxWidth : 280,
              child: AccountRawTextField(
                key: const ValueKey<String>('accounts-search'),
                value: AccountTextPresentation(raw: value.search),
                label: l10n.settingsSearchAccounts,
                prefixIcon: const Icon(Icons.search),
                onChanged: onSearchChanged,
              ),
            );
            final rightGroup = Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                if (showCategoryCounts || onCategoryChanged != null) ...[
                  categoryChip(
                    AccountListCategory.all,
                    l10n.accountsCategoryAll,
                    value.totalCount,
                  ),
                  categoryChip(
                    AccountListCategory.acp,
                    l10n.accountsCategoryAcp,
                    value.acpCount,
                  ),
                  categoryChip(
                    AccountListCategory.native,
                    l10n.accountsCategoryNative,
                    value.nativeCount,
                  ),
                ],
                if (value.upgradableCount > 0)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: Color.alphaBlend(
                        scheme.primary.withValues(alpha: 0.12),
                        scheme.surfaceContainerHigh,
                      ),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(
                        color: scheme.primary.withValues(alpha: 0.3),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.system_update_alt_rounded,
                          size: 14,
                          color: scheme.primary,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          l10n.accountsUpgradableCount(value.upgradableCount),
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: scheme.primary,
                            fontWeight: FontWeight.w600,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                      ],
                    ),
                  ),
                if (value.phase == AccountListPhase.ready)
                  Padding(
                    padding: const EdgeInsets.only(left: 4),
                    child: Text(
                      l10n.accountsVisibleCount(value.members.length),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
              ],
            );
            return Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 16,
              runSpacing: 12,
              children: [searchBox, rightGroup],
            );
          },
        ),
        const SizedBox(height: 16),
        if (value.refreshing || value.phase == AccountListPhase.loading) ...[
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: const LinearProgressIndicator(minHeight: 2),
          ),
          const SizedBox(height: 12),
        ],
        if (value.error != null || value.phase == AccountListPhase.failed)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: AccountInlineError(
              message: value.error ?? l10n.settingsAccountCatalogUnavailable,
              onRetry: onRetry,
            ),
          ),
        if (value.members.isEmpty && value.phase != AccountListPhase.failed)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 48),
            child: Column(
              children: [
                Icon(
                  value.searchHasNoResults
                      ? Icons.search_off
                      : Icons.cloud_outlined,
                  size: 40,
                  color: semantic?.eyeAccent ?? scheme.onSurfaceVariant,
                ),
                const SizedBox(height: 16),
                Text(
                  value.phase == AccountListPhase.loading
                      ? l10n.accountsLoading
                      : value.searchHasNoResults
                      ? l10n.settingsNoAccountsMatchTitle
                      : l10n.settingsNoAccountsTitle,
                  style: theme.textTheme.titleMedium,
                ),
                if (value.phase != AccountListPhase.loading) ...[
                  const SizedBox(height: 8),
                  Text(
                    value.searchHasNoResults
                        ? l10n.settingsNoAccountsMatchMessage
                        : l10n.settingsNoAccountsMessage,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  if (value.searchHasNoResults) ...[
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: () {
                        if (value.search.isNotEmpty) {
                          onSearchChanged('');
                        }
                        if (value.category != AccountListCategory.all) {
                          onCategoryChanged?.call(AccountListCategory.all);
                        }
                      },
                      child: Text(l10n.accountsClearSearch),
                    ),
                  ],
                ],
              ],
            ),
          ),
        if (value.members.isNotEmpty)
          LayoutBuilder(
            builder: (context, constraints) {
              // Main-area width, not window width: the settings sidebar is external.
              final wide =
                  constraints.maxWidth >=
                  760 * MediaQuery.textScalerOf(context).scale(1).clamp(1, 1.3);
              final itemLayout = wide
                  ? AccountItemLayout.columns
                  : AccountItemLayout.stacked;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var i = 0; i < value.members.length; i++) ...[
                    if (i > 0) const SizedBox(height: 12),
                    cardBuilder(
                      context,
                      value.members[i],
                      itemLayout,
                      () => onOpen(value.members[i]),
                      (action) => onRowAction(value.members[i], action),
                    ),
                  ],
                ],
              );
            },
          ),
      ],
    );
  }
}
