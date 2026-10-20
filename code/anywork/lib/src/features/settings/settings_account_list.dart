import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/theme/studio_tokens.dart';
import '../../domain/models/studio_models.dart';
import '../../l10n/studio_l10n.dart';
import '../../shared/account_brand.dart';
import '../../shared/studio_chrome.dart';
import '../../shared/studio_driver_keys.dart';
import 'settings_common.dart';
import 'settings_account_drafts.dart';
import 'settings_account_usage.dart';

class AccountList extends StatelessWidget {
  const AccountList({
    super.key,
    required this.accounts,
    this.selectedAccountId,
    required this.defaultAccountId,
    required this.filtering,
    required this.usageByAccount,
    required this.loadingAccountIds,
    required this.usageErrorsByAccountId,
    required this.onQueryChanged,
    required this.onAdd,
    required this.onSelect,
    required this.onSetDefault,
    required this.onRefreshAll,
    required this.onRefreshProvider,
    required this.onEdit,
    required this.onDelete,
  });

  final List<AccountSettingsView> accounts;
  final String? selectedAccountId;
  final String? defaultAccountId;
  final bool filtering;
  final Map<String, AccountUsageView> usageByAccount;
  final Set<String> loadingAccountIds;
  final Map<String, String> usageErrorsByAccountId;
  final ValueChanged<String> onQueryChanged;
  final VoidCallback onAdd;
  final ValueChanged<AccountSettingsView> onSelect;
  final ValueChanged<AccountSettingsView> onSetDefault;
  final Future<void> Function({String? accountId}) onRefreshAll;
  final ValueChanged<AccountSettingsView> onRefreshProvider;
  final ValueChanged<AccountSettingsView> onEdit;
  final ValueChanged<AccountSettingsView>? onDelete;

  @override
  Widget build(BuildContext context) {
    return Column(
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
                onPressed: () => onRefreshAll(),
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
          onChanged: onQueryChanged,
        ),
        const SizedBox(height: 14),
        Expanded(
          child: accounts.isEmpty
              ? Center(
                  child: StudioEmptyState(
                    icon: Icons.cloud_off_outlined,
                    title: filtering
                        ? context.l10n.settingsNoAccountsMatchTitle
                        : context.l10n.settingsNoAccountsTitle,
                    message: filtering
                        ? context.l10n.settingsNoAccountsMatchMessage
                        : context.l10n.settingsNoAccountsMessage,
                  ),
                )
              : SingleChildScrollView(
                  child: SettingsGroup(
                    children: [
                      for (final account in accounts)
                        AccountListRow(
                          account: account,
                          selected: account.id == selectedAccountId,
                          isDefault: account.id == defaultAccountId,
                          usage: usageByAccount[account.id],
                          usageLoading: loadingAccountIds.contains(account.id),
                          usageError:
                              usageErrorsByAccountId[account.id] ??
                              usageErrorsByAccountId['*'],
                          onOpen: () => onSelect(account),
                          onSetDefault: () => onSetDefault(account),
                          onRefreshUsage: () => onRefreshProvider(account),
                          onEdit: () => onEdit(account),
                          onDelete: onDelete == null
                              ? null
                              : () => onDelete!(account),
                        ),
                    ],
                  ),
                ),
        ),
      ],
    );
  }
}

class AccountListRow extends StatelessWidget {
  const AccountListRow({
    super.key,
    required this.account,
    this.selected = false,
    required this.isDefault,
    required this.usage,
    required this.usageLoading,
    required this.usageError,
    required this.onOpen,
    required this.onSetDefault,
    required this.onRefreshUsage,
    required this.onEdit,
    required this.onDelete,
  });

  final AccountSettingsView account;
  final bool selected;
  final bool isDefault;
  final AccountUsageView? usage;
  final bool usageLoading;
  final String? usageError;
  final VoidCallback onOpen;
  final FutureOr<void> Function() onSetDefault;
  final FutureOr<void> Function() onRefreshUsage;
  final FutureOr<void> Function() onEdit;
  final FutureOr<void> Function()? onDelete;

  @override
  Widget build(BuildContext context) {
    return Material(
      key: StudioDriverKeys.accountRow(account.id),
      color: selected ? context.colors.surfaceContainer : Colors.transparent,
      child: InkWell(
        onTap: onOpen,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AccountBrandMark(
                iconKey: account.iconKey,
                fallbackName: account.name,
                active: isDefault,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _ProviderRowTitle(account: account, isDefault: isDefault),
                    const SizedBox(height: 7),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        SettingsMiniMeta(
                          icon: Icons.key_outlined,
                          label: account.id,
                        ),
                        if (account.templateId != null &&
                            account.templateId!.isNotEmpty)
                          SettingsMiniMeta(
                            icon: Icons.tune_outlined,
                            label:
                                '${context.l10n.settingsAccountTemplate}: ${account.templateId}',
                          ),
                        SettingsAccountStatusChip(
                          account: account,
                          usage: usage,
                        ),
                      ],
                    ),
                    const SizedBox(height: 7),
                    Wrap(
                      spacing: 10,
                      runSpacing: 6,
                      children: [
                        SettingsMiniMeta(
                          icon: Icons.memory_outlined,
                          label: [
                            context.l10n.settingsAccountModelsTitle,
                            account.modelCount.isNotEmpty
                                ? account.modelCount
                                : '${account.models.length}',
                          ].join(': '),
                        ),
                        SettingsMiniMeta(
                          icon: Icons.alt_route_outlined,
                          label: [
                            context.l10n.settingsAccountProtocol,
                            context.protocolKindLabel(account.protocol),
                          ].join(': '),
                        ),
                      ],
                    ),
                    const SizedBox(height: 9),
                    AccountListUsage(
                      account: account,
                      usage: usage,
                      loading: usageLoading,
                      error: usageError,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              _ProviderRowMenu(
                isDefault: isDefault,
                onSetDefault: onSetDefault,
                onRefreshUsage: onRefreshUsage,
                onEdit: onEdit,
                onDelete: onDelete,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProviderRowTitle extends StatelessWidget {
  const _ProviderRowTitle({required this.account, required this.isDefault});

  final AccountSettingsView account;
  final bool isDefault;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Flexible(
              child: Text(
                account.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: context.colors.onSurface,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            if (isDefault) ...[
              const SizedBox(width: 8),
              StudioPill(
                tone: StudioTone.brand,
                label: context.l10n.settingsDefaultBadge,
              ),
            ],
          ],
        ),
        if (account.subtitle.isNotEmpty) ...[
          const SizedBox(height: 2),
          Text(
            account.subtitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ],
    );
  }
}

class AccountListUsage extends StatelessWidget {
  const AccountListUsage({
    super.key,
    required this.account,
    required this.usage,
    required this.loading,
    required this.error,
  });

  final AccountSettingsView account;
  final AccountUsageView? usage;
  final bool loading;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final usage = this.usage;
    if (error?.isNotEmpty ?? false) {
      return AccountUsageMessage(
        icon: Icons.error_outline,
        message: error!,
        tone: UsageTone.failed,
      );
    }
    if (loading) {
      return AccountUsageMessage(
        icon: Icons.hourglass_empty,
        message: context.l10n.settingsUsageCheckingShort,
        tone: UsageTone.neutral,
      );
    }
    if (usage == null || usage.state is! ReadyAccountUsageView) {
      final message = usage == null
          ? accountUsageSummary(context, account, null, loading)
          : accountUsageMessage(context, account, usage);
      final tone = switch (usage?.state) {
        FailedAccountUsageView() => UsageTone.failed,
        MissingCredentialAccountUsageView() => UsageTone.warning,
        UnsupportedAccountUsageView() ||
        ReadyAccountUsageView() ||
        null => UsageTone.muted,
      };
      return AccountUsageMessage(
        icon: usage?.state is FailedAccountUsageView
            ? Icons.error_outline
            : Icons.info_outline,
        message: message,
        tone: tone,
      );
    }
    if (usage.state case ReadyAccountUsageView(
      data: DeepSeekBalanceAccountUsageView(:final balance),
    )) {
      return DeepSeekBalanceReadout(usage: balance, compact: true);
    }
    if (usage.state case ReadyAccountUsageView(
      data: ZhipuCodingPlanAccountUsageView(:final codingPlan),
    )) {
      return _ProviderQuotaList(limits: codingPlan.limits);
    }
    return AccountUsageMessage(
      icon: Icons.account_balance_wallet_outlined,
      message: accountUsageSummary(context, account, usage, loading),
      tone: UsageTone.muted,
    );
  }
}

class _ProviderQuotaList extends StatelessWidget {
  const _ProviderQuotaList({required this.limits});

  final List<ZhipuQuotaLimitView> limits;

  @override
  Widget build(BuildContext context) {
    final ordered = [
      findQuotaLimit(limits, 'fiveHour'),
      findQuotaLimit(limits, 'weekly'),
      findQuotaLimit(limits, 'mcpMonthly'),
    ].whereType<ZhipuQuotaLimitView>().toList();
    if (ordered.isEmpty) {
      return AccountUsageMessage(
        icon: Icons.info_outline,
        message: context.l10n.settingsUsageUnavailable,
        tone: UsageTone.muted,
      );
    }
    return Column(
      children: [
        for (var index = 0; index < ordered.length; index++) ...[
          _ProviderQuotaRow(limit: ordered[index]),
          if (index < ordered.length - 1) const SizedBox(height: 8),
        ],
      ],
    );
  }
}

class _ProviderQuotaRow extends StatelessWidget {
  const _ProviderQuotaRow({required this.limit});

  final ZhipuQuotaLimitView limit;

  @override
  Widget build(BuildContext context) {
    final percent = quotaRemainingPercent(limit);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 10,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              quotaTitle(context, limit),
              style: context.text.labelMedium?.copyWith(
                color: context.colors.onSurface,
                fontWeight: FontWeight.w600,
              ),
            ),
            Text(
              context.l10n.settingsUsagePercentRemaining(
                formatPercent(percent),
              ),
              style: context.text.labelMedium?.copyWith(
                color: context.colors.onSurface,
                fontWeight: FontWeight.w600,
              ),
            ),
            if (quotaResetLabel(context, limit.nextResetAt).isNotEmpty)
              Text(
                quotaResetLabel(context, limit.nextResetAt),
                style: context.text.labelSmall?.copyWith(
                  color: context.colors.onSurfaceVariant,
                ),
              ),
          ],
        ),
        const SizedBox(height: 5),
        ClipRRect(
          borderRadius: BorderRadius.circular(StudioRadii.xs),
          child: SizedBox(
            height: 5,
            child: LinearProgressIndicator(
              value: percent / 100,
              backgroundColor: context.colors.surfaceContainerHigh,
              color: percent >= 65
                  ? context.statusColors.success
                  : context.colors.primary,
            ),
          ),
        ),
      ],
    );
  }
}

class _ProviderRowMenu extends StatelessWidget {
  const _ProviderRowMenu({
    required this.isDefault,
    required this.onSetDefault,
    required this.onRefreshUsage,
    required this.onEdit,
    required this.onDelete,
  });

  final bool isDefault;
  final FutureOr<void> Function() onSetDefault;
  final FutureOr<void> Function() onRefreshUsage;
  final FutureOr<void> Function() onEdit;
  final FutureOr<void> Function()? onDelete;

  @override
  Widget build(BuildContext context) {
    return MenuAnchor(
      alignmentOffset: const Offset(6, 6),
      menuChildren: [
        MenuItemButton(
          overflowAxis: Axis.vertical,
          onPressed: isDefault ? null : () => onSetDefault(),
          child: _AccountMenuLabel(
            icon: isDefault
                ? Icons.check_circle_outline
                : Icons.radio_button_unchecked,
            label: isDefault
                ? context.l10n.settingsDefaultAccount
                : context.l10n.settingsSetAsDefaultAccount,
          ),
        ),
        MenuItemButton(
          overflowAxis: Axis.vertical,
          onPressed: () => onRefreshUsage(),
          child: _AccountMenuLabel(
            icon: Icons.refresh,
            label: context.l10n.settingsRefreshUsage,
          ),
        ),
        MenuItemButton(
          overflowAxis: Axis.vertical,
          onPressed: () => onEdit(),
          child: _AccountMenuLabel(
            icon: Icons.edit_outlined,
            label: context.l10n.settingsEditAccount,
          ),
        ),
        if (onDelete != null)
          MenuItemButton(
            overflowAxis: Axis.vertical,
            onPressed: () => onDelete?.call(),
            child: _AccountMenuLabel(
              icon: Icons.delete_outline,
              label: context.l10n.settingsDeleteAccount,
            ),
          ),
      ],
      builder: (context, controller, child) => IconButton(
        tooltip: context.l10n.settingsAccountActions,
        onPressed: () {
          if (controller.isOpen) {
            controller.close();
          } else {
            controller.open();
          }
        },
        iconSize: 20,
        icon: const Icon(Icons.more_horiz),
      ),
    );
  }
}

class _AccountMenuLabel extends StatelessWidget {
  const _AccountMenuLabel({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [Icon(icon, size: 18), const SizedBox(width: 10), Text(label)],
    );
  }
}
