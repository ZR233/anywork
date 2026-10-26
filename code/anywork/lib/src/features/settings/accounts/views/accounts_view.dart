import 'package:anywork_client/account_usage.dart';
import 'package:anywork_client/configuration.dart';
import 'package:anywork_client/models.dart';
import 'package:flutter/material.dart';

import '../../../../diagnostics/studio_driver_keys.dart';
import '../../../../l10n/studio_l10n.dart';
import '../../../../ui/feedback/studio_messages.dart';
import '../../widgets/settings_feedback.dart';
import '../../widgets/settings_form_layout.dart';
import '../../widgets/settings_layout.dart';
import '../state/accounts_state.dart';
import '../widgets/acp_account_list_row.dart';
import '../widgets/account_list_row.dart';
import '../widgets/auto_page_loader.dart';

/// Account list column.
///
/// Layout matches the pre-refactor list: page header with the refresh/add
/// actions, the search field, then the hairline row group or the empty state.
/// It is a plain column so the tab can place it beside the details column on
/// wide windows and on its own otherwise.
class AccountsView extends StatelessWidget {
  const AccountsView({
    required this.state,
    required this.accounts,
    required this.acpEntries,
    required this.acpNoticeSummaries,
    required this.selectedAcpAccountId,
    required this.onSelectAcp,
    required this.onEditAcp,
    required this.onRemoveAcp,
    required this.catalogs,
    required this.usages,
    required this.defaultAccountId,
    required this.canDelete,
    required this.hasMore,
    required this.errors,
    required this.actionErrors,
    required this.onQuery,
    required this.onAdd,
    required this.onSelect,
    required this.onEdit,
    required this.onDefault,
    required this.onDelete,
    required this.onRefreshAll,
    required this.onRefresh,
    required this.onMore,
    required this.onRetry,
    super.key,
  });
  final AccountsViewState state;
  final List<AccountConfiguration> accounts;

  /// 与查询匹配的 ACP 接入（已按 canonical 顺序排列）。
  final List<AcpAccountEntryView> acpEntries;

  /// 按目标接入记账的命令失败摘要（已本地化）；只出现在目标行。
  final Map<String, String> acpNoticeSummaries;

  final String? selectedAcpAccountId;
  final ValueChanged<AcpAccountEntryView> onSelectAcp;
  final ValueChanged<AcpAccountEntryView> onEditAcp;
  final ValueChanged<AcpAccountEntryView> onRemoveAcp;

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
  Widget build(BuildContext context) => AutoPageLoader(
    hasMore: hasMore,
    loading: state.reading.contains(AccountsReadField.accounts),
    blocked: state.readIssues.containsKey(AccountsReadField.accounts),
    requestedCount: accounts.length,
    onLoadMore: onMore,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SettingsHeader(
          title: context.l10n.settingsAccountsTitle,
          subtitle: context.l10n.settingsAccountsSubtitle,
          trailing: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                key: StudioDriverKeys.accountUsageCheck,
                icon: const Icon(Icons.refresh),
                label: Text(context.l10n.settingsRefreshUsage),
                onPressed: state.refreshingAll ? null : onRefreshAll,
              ),
              FilledButton.icon(
                key: StudioDriverKeys.accountAdd,
                icon: const Icon(Icons.add),
                label: Text(context.l10n.settingsAddAccount),
                onPressed: onAdd,
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        SettingsSearchField(
          hintText: context.l10n.settingsSearchAccounts,
          onChanged: onQuery,
        ),
        const SizedBox(height: 14),
        if (errors.isNotEmpty) ...[
          SettingsInlineError(message: errors.join('\n')),
          TextButton(
            onPressed: onRetry,
            child: Text(context.l10n.runtimeFatalRetry),
          ),
          const SizedBox(height: 14),
        ],
        Expanded(
          child: accounts.isEmpty && acpEntries.isEmpty
              ? Center(
                  child: StudioEmptyState(
                    icon: Icons.cloud_off_outlined,
                    title: state.query.trim().isNotEmpty
                        ? context.l10n.settingsNoAccountsMatchTitle
                        : context.l10n.settingsNoAccountsTitle,
                    message: state.query.trim().isNotEmpty
                        ? context.l10n.settingsNoAccountsMatchMessage
                        : context.l10n.settingsNoAccountsMessage,
                  ),
                )
              : SingleChildScrollView(
                  child: SettingsGroup(
                    children: [
                      for (final account in accounts) _row(context, account),
                      for (final entry in acpEntries)
                        AcpAccountListRow(
                          entry: entry,
                          selected:
                              state.showDetails &&
                              selectedAcpAccountId == entry.account.accountId,
                          noticeSummary:
                              acpNoticeSummaries[entry.account.accountId],
                          onOpen: () => onSelectAcp(entry),
                          onEdit: () => onEditAcp(entry),
                          onRemove: () => onRemoveAcp(entry),
                        ),
                    ],
                  ),
                ),
        ),
      ],
    ),
  );

  Widget _row(BuildContext context, AccountConfiguration account) {
    final id = account.accountId;
    return AccountListRow(
      account: account,
      selected: state.showDetails && state.selectedAccountId == id,
      isDefault: defaultAccountId == id,
      iconKey: state.templates?.templates
          .where((item) => item.id == account.templateId)
          .firstOrNull
          ?.iconKey,
      modelCount: catalogs[id]?.effectiveModels.length ?? 0,
      canDelete: canDelete,
      defaultPending:
          state
              .rowActions[(id, AccountRowAction.setDefault)]
              ?.preventsResubmission ??
          false,
      deletePending:
          state.preparingRemovalIds.contains(id) ||
          (state
                  .rowActions[(id, AccountRowAction.remove)]
                  ?.preventsResubmission ??
              false),
      usage: usages[id],
      usageLoading: state.usageChecks[id]?.operation.isPending ?? false,
      usageErrors: actionErrors[id] ?? const [],
      onOpen: () => onSelect(id),
      onSetDefault: () => onDefault(id),
      onRefreshUsage: () => onRefresh(id),
      onEdit: () => onEdit(id),
      onDelete: canDelete ? () => onDelete(id) : null,
    );
  }
}
