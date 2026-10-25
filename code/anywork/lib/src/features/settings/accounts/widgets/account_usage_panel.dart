import 'package:anywork_client/account_usage.dart';
import 'package:flutter/material.dart';

import '../../../../l10n/studio_l10n.dart';
import '../../../../ui/formatters/token_format.dart';

class AccountUsagePanel extends StatelessWidget {
  const AccountUsagePanel({
    required this.usage,
    required this.loading,
    required this.errors,
    required this.onRefresh,
    this.compact = false,
    this.preparing = false,
    super.key,
  });
  final AccountUsageRecord? usage;
  final bool loading;
  final List<String> errors;
  final VoidCallback? onRefresh;
  final bool compact;
  final bool preparing;

  @override
  Widget build(BuildContext context) {
    final record = usage;
    return Card.outlined(
      child: Padding(
        padding: EdgeInsets.all(compact ? 10 : 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(Icons.account_balance_wallet_outlined, size: 18),
                const SizedBox(width: 8),
                Expanded(child: Text(context.l10n.settingsUsageTitle)),
                Text(
                  record == null || record.updatedAt <= 0
                      ? context.l10n.settingsUsageNotChecked
                      : context.l10n.settingsUsageUpdated(
                          _time(record.updatedAt),
                        ),
                ),
                IconButton(
                  tooltip: context.l10n.settingsRefreshUsage,
                  onPressed: loading ? null : onRefresh,
                  icon: loading
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.refresh, size: 18),
                ),
              ],
            ),
            for (final error in errors)
              SelectableText(
                error,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            if (record == null)
              Text(
                loading && !preparing
                    ? context.l10n.settingsUsageChecking
                    : context.l10n.settingsUsageNotLoaded,
              )
            else
              switch (record.state) {
                UsageUnsupported() => Text(
                  context.l10n.settingsUsageNotSupported,
                ),
                UsageMissingCredential(:final message) => Text(
                  message.isEmpty
                      ? context.l10n.settingsUsageApiKeyMissing
                      : message,
                ),
                UsageFailed(:final error) => SelectableText(
                  '${error.message} [${error.code}]',
                ),
                UsageReady(:final data) => switch (data) {
                  DeepSeekBalance() => _BalanceReadout(value: data),
                  ZhipuCodingPlan() => _QuotaReadout(value: data),
                },
              },
          ],
        ),
      ),
    );
  }
}

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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          value.isAvailable
              ? context.l10n.settingsUsageBalanceSufficient
              : context.l10n.settingsUsageBalanceInsufficient,
        ),
        if (balances.isEmpty) Text(context.l10n.settingsUsageUnavailable),
        for (final balance in balances)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  balance.currency,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                Wrap(
                  spacing: 16,
                  runSpacing: 8,
                  children: [
                    _metric(
                      context,
                      context.l10n.settingsUsageTotalBalance,
                      '${balance.currency} ${balance.totalBalance}',
                    ),
                    _metric(
                      context,
                      context.l10n.settingsUsageGrantedBalance,
                      '${balance.currency} ${balance.grantedBalance}',
                    ),
                    _metric(
                      context,
                      context.l10n.settingsUsageToppedUpBalance,
                      '${balance.currency} ${balance.toppedUpBalance}',
                    ),
                  ],
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _QuotaReadout extends StatelessWidget {
  const _QuotaReadout({required this.value});
  final ZhipuCodingPlan value;
  @override
  Widget build(BuildContext context) {
    final limits = [
      value.limits.where((limit) => limit.window is FiveHourQuota).firstOrNull,
      value.limits.where((limit) => limit.window is WeeklyQuota).firstOrNull,
      value.limits
          .where((limit) => limit.window is McpMonthlyQuota)
          .firstOrNull,
      ...value.limits.where((limit) => limit.window is OtherQuota),
    ].whereType<QuotaLimit>();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (value.level != null && value.level!.isNotEmpty) Text(value.level!),
        if (limits.isEmpty) Text(context.l10n.settingsUsageUnavailable),
        for (final limit in limits)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: _QuotaCard(limit: limit),
          ),
      ],
    );
  }
}

class _QuotaCard extends StatelessWidget {
  const _QuotaCard({required this.limit});
  final QuotaLimit limit;
  @override
  Widget build(BuildContext context) {
    final percent = _remainingPercent(limit);
    final title = switch (limit.window) {
      FiveHourQuota() => context.l10n.settingsUsageFiveHourQuota,
      WeeklyQuota() => context.l10n.settingsUsageWeeklyQuota,
      McpMonthlyQuota() => context.l10n.settingsUsageMcpQuota,
      OtherQuota(:final value) =>
        value.isEmpty ? context.l10n.settingsUsageQuota : value,
    };
    String number(num value) =>
        limit.window is FiveHourQuota || limit.window is WeeklyQuota
        ? formatTokenCount(value.round())
        : _compact(value);
    final remaining = limit.remaining;
    final total = limit.total;
    final used = limit.currentValue;
    final detail = remaining != null && total != null
        ? context.l10n.settingsUsageQuotaRemaining(
            number(remaining),
            number(total),
          )
        : used != null && total != null
        ? context.l10n.settingsUsageQuotaUsed(number(used), number(total))
        : context.l10n.settingsUsagePercentRemaining('${_short(percent)}%');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          spacing: 10,
          children: [
            Text(title),
            if (limit.nextResetAt != null && limit.nextResetAt! > 0)
              Text(context.l10n.settingsUsageReset(_time(limit.nextResetAt!))),
          ],
        ),
        Text(
          '${_short(percent)}%',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        Text(detail),
        const SizedBox(height: 8),
        LinearProgressIndicator(value: percent / 100),
        if (limit.usageDetails.isNotEmpty)
          Wrap(
            spacing: 8,
            children: [
              for (final detail in limit.usageDetails)
                Tooltip(
                  message: detail.name,
                  child: Chip(
                    label: Text('${detail.name} ${_toolUsage(detail)}'),
                  ),
                ),
            ],
          ),
      ],
    );
  }
}

Widget _metric(BuildContext context, String label, String value) => SizedBox(
  width: 170,
  child: Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label, style: Theme.of(context).textTheme.labelSmall),
      SelectableText(value),
    ],
  ),
);
String _time(int seconds) {
  final value = DateTime.fromMillisecondsSinceEpoch(seconds * 1000);
  return '${value.month}/${value.day} ${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';
}

String _short(num value) =>
    value.toStringAsFixed(3).replaceFirst(RegExp(r'\.?0+$'), '');
String _compact(num value) => value.abs() >= 1000000
    ? '${_short(value / 1000000)}M'
    : value.abs() >= 1000
    ? '${_short(value / 1000)}K'
    : _short(value);
double _clamp(double value) =>
    value.isFinite ? value.clamp(0, 100).toDouble() : 0;
double _remainingPercent(QuotaLimit value) =>
    value.remaining != null && value.total != null && value.total! > 0
    ? _clamp(value.remaining! / value.total! * 100)
    : _clamp(100 - value.percentage);
String _toolUsage(QuotaDetail value) {
  final used = value.currentValue;
  final total = value.total;
  if (used != null && total != null) {
    return '${_compact((total - used).clamp(0, total))}/${_compact(total)}';
  }
  if (used != null) return _compact(used);
  return value.percentage == null
      ? ''
      : '${_short(_clamp(100 - value.percentage!))}%';
}
