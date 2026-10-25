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
import 'settings_acp_account_details.dart';

class AccountList extends StatelessWidget {
  const AccountList({
    super.key,
    required this.accounts,
    required this.acpEntries,
    required this.acpNotices,
    required this.selectedAcpAccountId,
    required this.onSelectAcp,
    required this.onEditAcp,
    required this.onRemoveAcp,
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

  /// ACP 接入条目：与 Native 账号同一列表，但各自按 typed 分支渲染。
  final List<AcpAccountEntryView> acpEntries;

  /// 按目标接入记账的命令失败通知：只出现在目标行，不跨账号串位。
  final Map<String, AcpCommandNotice> acpNotices;
  final String? selectedAcpAccountId;
  final ValueChanged<AcpAccountEntryView> onSelectAcp;
  final ValueChanged<AcpAccountEntryView> onEditAcp;
  final ValueChanged<AcpAccountEntryView>? onRemoveAcp;
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
          child: accounts.isEmpty && acpEntries.isEmpty
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
                      for (final entry in acpEntries)
                        AcpAccountListRow(
                          entry: entry,
                          selected: entry.id == selectedAcpAccountId,
                          notice: acpNotices[entry.id],
                          onOpen: () => onSelectAcp(entry),
                          onEdit: () => onEditAcp(entry),
                          onRemove: onRemoveAcp == null
                              ? null
                              : () => onRemoveAcp!(entry),
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

/// ACP 接入行：品牌、名称、接入协议与认证状态摘要。
///
/// 状态同时用图标与文本表达，不只依赖颜色；长程序路径单行省略并保留 tooltip。
class AcpAccountListRow extends StatelessWidget {
  const AcpAccountListRow({
    super.key,
    required this.entry,
    required this.selected,
    this.notice,
    required this.onOpen,
    required this.onEdit,
    this.onRemove,
  });

  final AcpAccountEntryView entry;
  final bool selected;

  /// 该行自己的命令失败摘要（已本地化）；安全原文只在详情页折叠诊断里。
  final AcpCommandNotice? notice;
  final VoidCallback onOpen;
  final VoidCallback onEdit;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final account = entry.account;
    final (icon, label, tone) = acpAuthBadge(context, entry.auth);
    return Material(
      key: StudioDriverKeys.acpAccountRow(account.accountId),
      color: selected ? context.colors.surfaceContainer : Colors.transparent,
      child: InkWell(
        onTap: onOpen,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AccountBrandMark(
                iconKey: entry.template?.iconKey,
                fallbackName: account.name,
                active: false,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            account.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.titleSmall
                                ?.copyWith(
                                  color: context.colors.onSurface,
                                  fontWeight: FontWeight.w700,
                                ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        StudioPill(
                          icon: Icons.hub_outlined,
                          label: l10n.acpAccountProviderChip,
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Icon(
                          icon,
                          size: 14,
                          color: tone == StudioTone.error
                              ? context.colors.error
                              : context.colors.onSurfaceVariant,
                        ),
                        const SizedBox(width: 5),
                        Flexible(
                          child: Text(
                            label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: context.text.bodySmall?.copyWith(
                              color: context.colors.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (notice case final notice?) ...[
                      const SizedBox(height: 6),
                      Row(
                        key: StudioDriverKeys.acpAccountNotice(
                          account.accountId,
                        ),
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            Icons.error_outline,
                            size: 14,
                            color: context.colors.error,
                          ),
                          const SizedBox(width: 5),
                          Expanded(
                            child: Text(
                              notice.summary,
                              style: context.text.bodySmall?.copyWith(
                                color: context.colors.error,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_horiz),
                onSelected: (value) {
                  switch (value) {
                    case 'edit':
                      onEdit();
                    case 'remove':
                      onRemove?.call();
                  }
                },
                itemBuilder: (context) => [
                  PopupMenuItem<String>(
                    value: 'edit',
                    child: Text(l10n.settingsEdit),
                  ),
                  if (onRemove != null)
                    PopupMenuItem<String>(
                      value: 'remove',
                      child: Text(l10n.settingsDeleteAccount),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 认证状态在列表里的紧凑表达：图标 + 文案 + 语气，状态不只靠颜色。
(IconData, String, StudioTone) acpAuthBadge(
  BuildContext context,
  AcpAuthStateView state,
) {
  final l10n = context.l10n;
  return switch (state) {
    AcpUncheckedState() => (
      Icons.link_off,
      l10n.acpAuthRowUnchecked,
      StudioTone.neutral,
    ),
    AcpCheckingState() => (
      Icons.sync,
      l10n.acpAuthRowChecking,
      StudioTone.brand,
    ),
    AcpRequiredState() => (
      Icons.lock_outline,
      l10n.acpAuthRowRequired,
      StudioTone.warning,
    ),
    AcpAuthenticatingState() => (
      Icons.login,
      l10n.acpAuthRowAuthenticating,
      StudioTone.brand,
    ),
    AcpVerifyingState() => (
      Icons.verified_outlined,
      l10n.acpAuthRowVerifying,
      StudioTone.brand,
    ),
    AcpClosingState() => (
      Icons.hourglass_bottom,
      l10n.acpAuthRowClosing,
      StudioTone.brand,
    ),
    AcpVerifiedState() => (
      Icons.check_circle_outline,
      l10n.acpAuthRowVerified,
      StudioTone.success,
    ),
    AcpCancellingState() => (
      Icons.stop_circle_outlined,
      l10n.acpAuthRowCancelling,
      StudioTone.warning,
    ),
    AcpCancelledState() => (
      Icons.cancel_outlined,
      l10n.acpAuthRowCancelled,
      StudioTone.neutral,
    ),
    AcpFailedState() => (
      Icons.error_outline,
      l10n.acpAuthRowFailed,
      StudioTone.error,
    ),
  };
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
