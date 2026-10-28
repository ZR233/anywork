import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../app/theme/studio_semantic_colors.dart';
import '../../../../l10n/app_localizations.dart';
import '../state/account_presentations.dart';
import 'account_sections.dart';

class AccountBalanceMetrics extends StatelessWidget {
  const AccountBalanceMetrics({
    required this.value,
    this.density = AccountMetricDensity.detailed,
    super.key,
  });
  final AccountCurrencyBalance value;
  final AccountMetricDensity density;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    // Only add a familiar symbol; never parse, round or fill a decimal string.
    // Summary identifies each currency group once; detailed labels stay explicit.
    final symbol = switch (value.currency) {
      'CNY' || 'JPY' => '¥ ',
      'USD' || 'CAD' || 'AUD' => '\$ ',
      'EUR' => '€ ',
      'GBP' => '£ ',
      _ => '',
    };
    final metrics = [
      for (final metric in [
        (l10n.settingsUsageAvailableBalance, value.total, true),
        (l10n.settingsUsageGrantedBalance, value.granted, false),
        (l10n.settingsUsageToppedUpBalance, value.toppedUp, false),
      ])
        if (metric.$2 != null)
          (
            label: metric.$1,
            reading: '$symbol${metric.$2}',
            primary: metric.$3,
          ),
    ];
    final compact = density == AccountMetricDensity.summary;
    String label(int index) => compact && index > 0
        ? metrics[index].label
        : '${metrics[index].label} · ${value.currency}';
    final cells = [
      for (var i = 0; i < metrics.length; i++)
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label(i), style: _metricLabelStyle(context)),
            const SizedBox(height: 6),
            AccountSelectableText(
              metrics[i].reading,
              style: _readingStyle(
                context,
                compact,
                primary: metrics[i].primary,
              ),
            ),
          ],
        ),
    ];
    if (!compact) {
      return _DetailedBalanceGrid(
        primaryIndex: metrics.indexWhere((metric) => metric.primary),
        readingWidths: [
          for (final metric in metrics)
            _textWidth(
              context,
              metric.reading,
              _readingStyle(context, false, primary: metric.primary),
            ),
        ],
        children: cells,
      );
    }
    return _MetricGrid(
      density: density,
      crossAxisAlignment: compact
          ? WrapCrossAlignment.end
          : WrapCrossAlignment.start,
      preferredWidths: [
        for (var i = 0; i < metrics.length; i++)
          if (compact)
            _textWidth(
              context,
              metrics[i].reading,
              _readingStyle(context, compact, primary: metrics[i].primary),
            )
          else
            math.max(
              _textWidth(
                context,
                metrics[i].reading,
                _readingStyle(context, compact, primary: metrics[i].primary),
              ),
              _textWidth(context, label(i), _metricLabelStyle(context)),
            ),
      ],
      children: cells,
    );
  }
}

/// Detailed currency balances split by actual readout roles, never by item order.
/// Quotas and summary metrics retain their own independent grid contracts.
class _DetailedBalanceGrid extends StatelessWidget {
  const _DetailedBalanceGrid({
    required this.primaryIndex,
    required this.readingWidths,
    required this.children,
  });
  final int primaryIndex;
  final List<double> readingWidths;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    if (children.isEmpty) return const SizedBox.shrink();
    return LayoutBuilder(
      builder: (context, constraints) {
        final indices = List.generate(children.length, (index) => index);
        bool fits(List<int> group) {
          final width = constraints.maxWidth / group.length;
          for (var position = 0; position < group.length; position++) {
            // Preserve the detailed grid's 16px edge/partition padding,
            // including the border that Container adds to its content inset.
            final inset = position == 0 ? 16 : 33;
            if (readingWidths[group[position]] + inset > width) return false;
          }
          return true;
        }

        Widget row(List<int> group) => Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var position = 0; position < group.length; position++)
              Expanded(
                child: Container(
                  padding: EdgeInsetsDirectional.only(
                    start: position == 0 ? 0 : 16,
                    end: 16,
                  ),
                  decoration: BoxDecoration(
                    border: position == 0
                        ? null
                        : BorderDirectional(
                            start: BorderSide(
                              color: Theme.of(context)
                                  .colorScheme
                                  .outlineVariant,
                            ),
                          ),
                  ),
                  child: children[group[position]],
                ),
              ),
          ],
        );

        Widget secondaryGroup(List<int> group) => fits(group)
            ? row(group)
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (
                    var position = 0;
                    position < group.length;
                    position++
                  ) ...[
                    if (position > 0) const SizedBox(height: 16),
                    row([group[position]]),
                  ],
                ],
              );

        if (fits(indices)) return row(indices);
        if (primaryIndex < 0) return secondaryGroup(indices);
        final secondary = indices
            .where((index) => index != primaryIndex)
            .toList();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            row([primaryIndex]),
            if (secondary.isNotEmpty) ...[
              const SizedBox(height: 16),
              secondaryGroup(secondary),
            ],
          ],
        );
      },
    );
  }
}

class AccountQuotaMetrics extends StatelessWidget {
  const AccountQuotaMetrics({
    required this.values,
    this.density = AccountMetricDensity.detailed,
    super.key,
  });
  final List<AccountQuotaPresentation> values;
  final AccountMetricDensity density;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final semantic = Theme.of(context).extension<StudioSemanticColors>()!;
    final compact = density == AccountMetricDensity.summary;
    final style = _readingStyle(
      context,
      compact,
    ).copyWith(fontSize: compact ? 14 : 22);
    return _MetricGrid(
      density: density,
      preferredWidths: [
        for (final quota in values)
          if (compact)
            _textWidth(
              context,
              '${l10n.accountsRemaining} ${quota.remaining}',
              style,
            )
          else
            math.max(
              120,
              _textWidth(
                context,
                '${l10n.accountsRemaining} ${quota.remaining}',
                style,
              ),
            ),
      ],
      children: [
        for (final quota in values)
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (compact)
                Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    Text(quota.label, style: _metricLabelStyle(context)),
                    Text(
                      '${l10n.accountsRemaining} ${quota.remaining}',
                      style: style,
                    ),
                  ],
                )
              else ...[
                Text(quota.label, style: _metricLabelStyle(context)),
                const SizedBox(height: 6),
                Text(
                  '${l10n.accountsRemaining} ${quota.remaining}',
                  style: style,
                ),
              ],
              if (quota.remainingFraction != null) ...[
                const SizedBox(height: 8),
                LinearProgressIndicator(
                  value: quota.remainingFraction,
                  color: quota.low ? semantic.warning : semantic.success,
                  backgroundColor: Theme.of(context)
                      .colorScheme
                      .surfaceContainer,
                  minHeight: compact ? 4 : 6,
                  borderRadius: BorderRadius.circular(6),
                ),
              ],
              if (quota.resetLabel != null)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    l10n.settingsUsageReset(quota.resetLabel!),
                    style: _metricLabelStyle(context),
                  ),
                ),
              if (quota.low)
                Text(
                  l10n.accountsLowQuota,
                  style: _metricLabelStyle(context)
                      .copyWith(color: semantic.warning),
                ),
            ],
          ),
      ],
    );
  }
}

TextStyle _readingStyle(
  BuildContext context,
  bool compact, {
  bool primary = true,
}) =>
    (compact
            ? Theme.of(context).textTheme.titleLarge
            : Theme.of(context).textTheme.headlineSmall)!
        .copyWith(
          fontSize: compact
              ? primary
                    ? 18
                    : 14
              : primary
              ? 30
              : 22,
          fontWeight: primary ? FontWeight.w700 : FontWeight.w600,
          height: 1.25,
        );

TextStyle _metricLabelStyle(BuildContext context) => Theme.of(context)
    .textTheme
    .bodyMedium!
    .copyWith(
      fontSize: 11,
      color: Theme.of(context).colorScheme.onSurfaceVariant,
    );

double _textWidth(BuildContext context, String text, TextStyle style) {
  final painter = TextPainter(
    text: TextSpan(text: text, style: style),
    textDirection: Directionality.of(context),
    textScaler: MediaQuery.textScalerOf(context),
  )..layout();
  final width = painter.width;
  painter.dispose();
  return width;
}

/// Columns follow the actual readable values, not the outer window breakpoint.
/// Long decimal strings get fewer columns; even a single column may wrap text,
/// but never truncates, scales down, or loses provider precision.
class _MetricGrid extends StatelessWidget {
  const _MetricGrid({
    required this.preferredWidths,
    required this.children,
    required this.density,
    this.crossAxisAlignment = WrapCrossAlignment.start,
  });
  final List<double> preferredWidths;
  final List<Widget> children;
  final AccountMetricDensity density;
  final WrapCrossAlignment crossAxisAlignment;

  @override
  Widget build(BuildContext context) {
    if (children.isEmpty) return const SizedBox.shrink();
    return LayoutBuilder(
      builder: (context, constraints) {
        if (density == AccountMetricDensity.summary) {
          const gap = 12.0;
          const separator = 1.0;
          final preferred = preferredWidths.reduce(math.max);
          final columns = ((constraints.maxWidth + gap) / (preferred + gap))
              .floor()
              .clamp(1, math.min(3, children.length));
          final contentWidth =
              ((constraints.maxWidth - (columns - 1) * gap) / columns)
                  .floorToDouble();
          return Wrap(
            crossAxisAlignment: crossAxisAlignment,
            runSpacing: 10,
            children: [
              for (var i = 0; i < children.length; i++)
                Container(
                  // Charge each internal gap once, leaving both outer edges bare.
                  width: contentWidth + (i % columns == 0 ? 0 : gap),
                  padding: EdgeInsetsDirectional.only(
                    start: i % columns == 0 ? 0 : gap - separator,
                  ),
                  decoration: BoxDecoration(
                    border: i % columns == 0
                        ? null
                        : BorderDirectional(
                            start: BorderSide(
                              width: separator,
                              color: Theme.of(context)
                                  .colorScheme
                                  .outlineVariant,
                            ),
                          ),
                  ),
                  child: children[i],
                ),
            ],
          );
        }
        final preferred = preferredWidths.reduce(math.max) + 32;
        final columns = (constraints.maxWidth / preferred).floor().clamp(
          1,
          math.min(3, children.length),
        );
        // Leave fractional pixels unused rather than let Wrap push a third
        // item onto a new run due to floating-point layout accumulation.
        final width = (constraints.maxWidth / columns).floorToDouble();
        return Wrap(
          runSpacing: 16,
          children: [
            for (var i = 0; i < children.length; i++)
              Container(
                width: width,
                padding: EdgeInsetsDirectional.only(
                  start: i % columns == 0 ? 0 : 16,
                  end: 16,
                ),
                decoration: BoxDecoration(
                  border: i % columns == 0
                      ? null
                      : BorderDirectional(
                          start: BorderSide(
                            color: Theme.of(context).colorScheme.outlineVariant,
                          ),
                        ),
                ),
                child: children[i],
              ),
          ],
        );
      },
    );
  }
}
