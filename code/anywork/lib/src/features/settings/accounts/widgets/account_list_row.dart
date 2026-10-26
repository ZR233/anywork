import 'dart:async';

import 'package:anywork_client/account_usage.dart';
import 'package:anywork_client/configuration.dart';
import 'package:flutter/material.dart';

import '../../../../app/theme/studio_tokens.dart';
import '../../../../diagnostics/studio_driver_keys.dart';
import '../../../../l10n/studio_l10n.dart';
import '../../../../ui/badges/studio_badges.dart';
import '../../../../ui/branding/account_brand.dart';
import '../../../../ui/feedback/studio_messages.dart';
import '../../../../ui/formatters/token_format.dart';
import '../../widgets/settings_readouts.dart';

/// One account row of the settings list.
///
/// Mirrors the pre-refactor row anatomy: brand mark, name with the default
/// badge, a status chip beside identity metadata, capacity/protocol metadata and
/// the inline usage line, all separated by hairlines in [SettingsGroup].
class AccountListRow extends StatelessWidget {
  const AccountListRow({
    required this.account,
    required this.selected,
    required this.isDefault,
    required this.iconKey,
    required this.modelCount,
    required this.canDelete,
    required this.defaultPending,
    required this.deletePending,
    required this.usage,
    required this.usageLoading,
    required this.usageErrors,
    required this.onOpen,
    required this.onSetDefault,
    required this.onRefreshUsage,
    required this.onEdit,
    required this.onDelete,
    super.key,
  });

  final AccountConfiguration account;
  final bool selected;
  final bool isDefault;
  final String? iconKey;
  final int modelCount;
  final bool canDelete;
  final bool defaultPending;
  final bool deletePending;
  final AccountUsageRecord? usage;
  final bool usageLoading;
  final List<String> usageErrors;
  final VoidCallback onOpen;
  final FutureOr<void> Function() onSetDefault;
  final FutureOr<void> Function() onRefreshUsage;
  final FutureOr<void> Function() onEdit;
  final FutureOr<void> Function()? onDelete;

  @override
  Widget build(BuildContext context) {
    final templateId = account.templateId;
    return Material(
      key: StudioDriverKeys.accountRow(account.accountId),
      color: selected ? context.colors.surfaceContainer : Colors.transparent,
      child: InkWell(
        onTap: onOpen,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AccountBrandMark(
                iconKey: iconKey,
                fallbackName: account.name,
                active: isDefault,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _Title(account: account, isDefault: isDefault),
                    const SizedBox(height: 7),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        SettingsMiniMeta(
                          icon: Icons.key_outlined,
                          label: account.accountId,
                        ),
                        if (templateId != null && templateId.isNotEmpty)
                          SettingsMiniMeta(
                            icon: Icons.tune_outlined,
                            label:
                                '${context.l10n.settingsAccountTemplate}: $templateId',
                          ),
                        StudioPill(
                          icon: account.hasBearerToken
                              ? Icons.key_outlined
                              : Icons.error_outline,
                          label: account.hasBearerToken
                              ? context.l10n.settingsConfigured
                              : context.l10n.settingsMissing,
                          tone: account.hasBearerToken
                              ? StudioTone.neutral
                              : StudioTone.warning,
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
                          label:
                              '${context.l10n.settingsAccountModelsTitle}: $modelCount',
                        ),
                        SettingsMiniMeta(
                          icon: Icons.alt_route_outlined,
                          label:
                              '${context.l10n.settingsAccountProtocol}: '
                              '${context.protocolKindLabel(account.protocol)}',
                        ),
                      ],
                    ),
                    const SizedBox(height: 9),
                    _AccountListUsage(
                      usage: usage,
                      loading: usageLoading,
                      errors: usageErrors,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              _ProviderRowMenu(
                isDefault: isDefault,
                defaultPending: defaultPending,
                deletePending: deletePending,
                canDelete: canDelete,
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

class _Title extends StatelessWidget {
  const _Title({required this.account, required this.isDefault});

  final AccountConfiguration account;
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
                style: context.text.titleSmall?.copyWith(
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
        if (account.baseUrl.isNotEmpty) ...[
          const SizedBox(height: 2),
          Text(
            account.baseUrl,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: context.text.bodySmall?.copyWith(
              color: context.colors.onSurfaceVariant,
            ),
          ),
        ],
      ],
    );
  }
}

/// Inline usage line of a list row: failures and pending states read as one
/// message, ready states as the provider's balances or quotas.
class _AccountListUsage extends StatelessWidget {
  const _AccountListUsage({
    required this.usage,
    required this.loading,
    required this.errors,
  });

  final AccountUsageRecord? usage;
  final bool loading;
  final List<String> errors;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    if (errors.isNotEmpty) {
      return StudioInlineMessage(
        icon: Icons.error_outline,
        message: errors.first,
        color: colors.error,
      );
    }
    if (loading) {
      return StudioInlineMessage(
        icon: Icons.hourglass_empty,
        message: context.l10n.settingsUsageCheckingShort,
      );
    }
    final record = usage;
    if (record == null) {
      return StudioInlineMessage(
        icon: Icons.info_outline,
        message: context.l10n.settingsUsageNotChecked,
      );
    }
    return switch (record.state) {
      UsageUnsupported() => StudioInlineMessage(
        icon: Icons.info_outline,
        message: context.l10n.settingsUsageNotSupported,
      ),
      UsageMissingCredential(:final message) => StudioInlineMessage(
        icon: Icons.info_outline,
        message: message.isEmpty
            ? context.l10n.settingsUsageApiKeyMissing
            : message,
        color: context.statusColors.warning,
      ),
      UsageFailed(:final error) => StudioInlineMessage(
        icon: Icons.error_outline,
        message: '${error.message} [${error.code}]',
        color: colors.error,
      ),
      UsageReady(:final data) => switch (data) {
        DeepSeekBalance() => _BalanceReadout(value: data),
        ZhipuCodingPlan() => _QuotaList(value: data),
      },
    };
  }
}

/// Balances of a ready provider usage: the availability pill over one bordered
/// card per currency, mirroring the pre-refactor compact readout.
class _BalanceReadout extends StatelessWidget {
  const _BalanceReadout({required this.value});

  final DeepSeekBalance value;

  @override
  Widget build(BuildContext context) {
    final balances = [...value.balances];
    final primary = balances.indexWhere(
      (balance) => balance.currency.toUpperCase() == 'CNY',
    );
    if (primary > 0) balances.insert(0, balances.removeAt(primary));
    if (balances.isEmpty) {
      return StudioInlineMessage(
        icon: Icons.info_outline,
        message: context.l10n.settingsUsageUnavailable,
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        StudioPill(
          icon: value.isAvailable
              ? Icons.check_circle_outline
              : Icons.warning_amber_outlined,
          label: value.isAvailable
              ? context.l10n.settingsUsageBalanceSufficient
              : context.l10n.settingsUsageBalanceInsufficient,
          tone: value.isAvailable ? StudioTone.success : StudioTone.warning,
        ),
        const SizedBox(height: 8),
        for (var index = 0; index < balances.length; index++) ...[
          _CurrencyBalanceCard(balance: balances[index]),
          if (index < balances.length - 1) const SizedBox(height: 8),
        ],
      ],
    );
  }
}

class _CurrencyBalanceCard extends StatelessWidget {
  const _CurrencyBalanceCard({required this.balance});

  final Balance balance;

  @override
  Widget build(BuildContext context) {
    final metrics = [
      (
        context.l10n.settingsUsageTotalBalance,
        '${balance.currency} ${balance.totalBalance}',
        null,
      ),
      (
        context.l10n.settingsUsageGrantedBalance,
        '${balance.currency} ${balance.grantedBalance}',
        Icons.card_giftcard_outlined,
      ),
      (
        context.l10n.settingsUsageToppedUpBalance,
        '${balance.currency} ${balance.toppedUpBalance}',
        Icons.payments_outlined,
      ),
    ];
    return DecoratedBox(
      decoration: BoxDecoration(
        color: context.colors.surfaceContainerLowest,
        border: Border.all(color: context.colors.outlineVariant),
        borderRadius: BorderRadius.circular(StudioRadii.sm),
      ),
      child: Padding(
        padding: const EdgeInsets.all(9),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.account_balance_wallet_outlined,
                  size: 15,
                  color: context.colors.onSurfaceVariant,
                ),
                const SizedBox(width: 6),
                Text(
                  balance.currency,
                  style: context.text.labelLarge?.copyWith(
                    color: context.colors.onSurface,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 9),
            LayoutBuilder(
              builder: (context, constraints) {
                final width = constraints.maxWidth < 132
                    ? constraints.maxWidth
                    : 132.0;
                return Wrap(
                  spacing: 14,
                  runSpacing: 10,
                  children: [
                    for (final (label, value, icon) in metrics)
                      SizedBox(
                        width: width,
                        child: _BalanceMetric(
                          label: label,
                          value: value,
                          icon: icon,
                        ),
                      ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _BalanceMetric extends StatelessWidget {
  const _BalanceMetric({required this.label, required this.value, this.icon});

  final String label;
  final String value;
  final IconData? icon;

  @override
  Widget build(BuildContext context) => Semantics(
    label: '$label: $value',
    value: value,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 13, color: context.colors.onSurfaceVariant),
              const SizedBox(width: 4),
            ],
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: context.text.labelSmall?.copyWith(
                  color: context.colors.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 2),
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: context.text.bodyMedium?.copyWith(
            color: context.colors.onSurface,
            fontWeight: icon == null ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
      ],
    ),
  );
}

/// Quotas of a ready coding-plan usage: one bordered row per window with the
/// remaining percentage, the reset time and a 6-high progress bar.
class _QuotaList extends StatelessWidget {
  const _QuotaList({required this.value});

  final ZhipuCodingPlan value;

  @override
  Widget build(BuildContext context) {
    final limits = [
      _window(FiveHourQuota(), context.l10n.settingsUsageFiveHourQuota),
      _window(WeeklyQuota(), context.l10n.settingsUsageWeeklyQuota),
      _window(McpMonthlyQuota(), context.l10n.settingsUsageMcpQuota),
    ].whereType<(String, QuotaLimit)>().toList();
    if (limits.isEmpty) {
      return StudioInlineMessage(
        icon: Icons.info_outline,
        message: context.l10n.settingsUsageUnavailable,
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var index = 0; index < limits.length; index++) ...[
          _QuotaRow(title: limits[index].$1, limit: limits[index].$2),
          if (index < limits.length - 1) const SizedBox(height: 8),
        ],
      ],
    );
  }

  (String, QuotaLimit)? _window(QuotaWindow window, String title) {
    for (final limit in value.limits) {
      if (limit.window.runtimeType == window.runtimeType) return (title, limit);
    }
    return null;
  }
}

class _QuotaRow extends StatelessWidget {
  const _QuotaRow({required this.title, required this.limit});

  final String title;
  final QuotaLimit limit;

  @override
  Widget build(BuildContext context) {
    final percent = _remainingPercent();
    final nextResetAt = limit.nextResetAt;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: context.colors.surfaceContainerLowest,
        border: Border.all(color: context.colors.outlineVariant),
        borderRadius: BorderRadius.circular(StudioRadii.sm),
      ),
      child: Padding(
        padding: const EdgeInsets.all(11),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.labelLarge
                        ?.copyWith(color: context.colors.onSurface),
                  ),
                ),
                Text(
                  _timeLabel(context, nextResetAt),
                  style: Theme.of(context).textTheme.labelSmall
                      ?.copyWith(color: context.colors.onSurfaceVariant),
                ),
              ],
            ),
            const SizedBox(height: 7),
            Text(
              _percentLabel(),
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: context.colors.onSurface,
                fontWeight: FontWeight.w600,
              ),
            ),
            Text(
              _detail(context),
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(color: context.colors.onSurfaceVariant),
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: SizedBox(
                height: 6,
                child: LinearProgressIndicator(
                  value: percent / 100,
                  backgroundColor: context.colors.surfaceContainerHigh,
                  color: percent >= 65
                      ? context.statusColors.success
                      : context.colors.primary,
                ),
              ),
            ),
            if (limit.usageDetails.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: [
                  for (final detail in limit.usageDetails)
                    Tooltip(
                      message: detail.name,
                      child: StudioPill(
                        tone: StudioTone.neutral,
                        label: '${detail.name} ${_toolUsage(detail)}',
                      ),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  double _remainingPercent() {
    final remaining = limit.remaining;
    final total = limit.total;
    if (remaining != null && total != null && total > 0) {
      return (remaining / total * 100).clamp(0, 100).toDouble();
    }
    return (100 - limit.percentage).clamp(0, 100).toDouble();
  }

  String _percentLabel() => '${_short(_remainingPercent())}%';

  String _detail(BuildContext context) {
    final remaining = limit.remaining;
    final total = limit.total;
    final used = limit.currentValue;
    String number(num value) =>
        limit.window is FiveHourQuota || limit.window is WeeklyQuota
        ? formatTokenCount(value.round())
        : _compact(value);
    if (remaining != null && total != null) {
      return context.l10n.settingsUsageQuotaRemaining(
        number(remaining),
        number(total),
      );
    }
    if (used != null && total != null) {
      return context.l10n.settingsUsageQuotaUsed(number(used), number(total));
    }
    return context.l10n.settingsUsagePercentRemaining(_percentLabel());
  }

  String _toolUsage(QuotaDetail detail) {
    final used = detail.currentValue;
    final total = detail.total;
    if (used != null && total != null) {
      return '${_compact((total - used).clamp(0, total))}/${_compact(total)}';
    }
    if (used != null) return _compact(used);
    return detail.percentage == null
        ? ''
        : '${_short((100 - detail.percentage!).clamp(0, 100))}%';
  }

  String _timeLabel(BuildContext context, int? nextResetAt) =>
      nextResetAt == null || nextResetAt <= 0
      ? ''
      : context.l10n.settingsUsageReset(_time(nextResetAt));
}

String _time(int seconds) {
  final value = DateTime.fromMillisecondsSinceEpoch(seconds * 1000);
  return '${value.month}/${value.day} '
      '${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';
}

String _short(num value) =>
    value.toStringAsFixed(3).replaceFirst(RegExp(r'\.?0+$'), '');

String _compact(num value) => value.abs() >= 1000000
    ? '${_short(value / 1000000)}M'
    : value.abs() >= 1000
    ? '${_short(value / 1000)}K'
    : _short(value);

class _ProviderRowMenu extends StatelessWidget {
  const _ProviderRowMenu({
    required this.isDefault,
    required this.defaultPending,
    required this.deletePending,
    required this.canDelete,
    required this.onSetDefault,
    required this.onRefreshUsage,
    required this.onEdit,
    required this.onDelete,
  });

  final bool isDefault;
  final bool defaultPending;
  final bool deletePending;
  final bool canDelete;
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
          onPressed: isDefault || defaultPending ? null : () => onSetDefault(),
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
            onPressed: canDelete && !deletePending
                ? () => onDelete?.call()
                : null,
            child: _AccountMenuLabel(
              icon: Icons.delete_outline,
              label: context.l10n.settingsDeleteAccount,
            ),
          ),
      ],
      builder: (context, controller, child) => IconButton(
        tooltip: context.l10n.settingsAccountActions,
        onPressed: () =>
            controller.isOpen ? controller.close() : controller.open(),
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
