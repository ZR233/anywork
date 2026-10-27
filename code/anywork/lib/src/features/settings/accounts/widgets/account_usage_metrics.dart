import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../app/theme/studio_semantic_colors.dart';
import '../../../../l10n/app_localizations.dart';
import '../state/account_presentations.dart';

class AccountBalanceMetrics extends StatelessWidget {
  const AccountBalanceMetrics({
    required this.value,
    required this.compact,
    super.key,
  });
  final AccountCurrencyBalance value;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    // Only add a familiar symbol; never parse, round or fill a decimal string.
    // The currency code stays beside every label to disambiguate symbols.
    final symbol = switch (value.currency) {
      'CNY' || 'JPY' => '¥ ',
      'USD' || 'CAD' || 'AUD' => '\$ ',
      'EUR' => '€ ',
      'GBP' => '£ ',
      _ => '',
    };
    final metrics = [
      for (final metric in [
        (l10n.settingsUsageAvailableBalance, value.total),
        (l10n.settingsUsageGrantedBalance, value.granted),
        (l10n.settingsUsageToppedUpBalance, value.toppedUp),
      ])
        if (metric.$2 != null)
          (
            label: '${metric.$1} · ${value.currency}',
            reading: '$symbol${metric.$2}',
          ),
    ];
    final style = _readingStyle(context, compact);
    return _MetricGrid(
      preferredWidths: [
        for (final metric in metrics)
          math.max(
            _textWidth(context, metric.reading, style),
            _textWidth(context, metric.label, _metricLabelStyle(context)),
          ),
      ],
      children: [
        for (final metric in metrics)
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(metric.label, style: _metricLabelStyle(context)),
              const SizedBox(height: 6),
              Text(metric.reading, style: style),
            ],
          ),
      ],
    );
  }
}

class AccountQuotaMetrics extends StatelessWidget {
  const AccountQuotaMetrics({
    required this.values,
    required this.compact,
    super.key,
  });
  final List<AccountQuotaPresentation> values;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final semantic = Theme.of(context).extension<StudioSemanticColors>()!;
    final style = _readingStyle(context, compact);
    return _MetricGrid(
      preferredWidths: [
        for (final quota in values)
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
              Text(quota.label, style: _metricLabelStyle(context)),
              const SizedBox(height: 6),
              Text(
                '${l10n.accountsRemaining} ${quota.remaining}',
                style: style,
              ),
              if (quota.remainingFraction != null) ...[
                const SizedBox(height: 8),
                LinearProgressIndicator(
                  value: quota.remainingFraction,
                  color: quota.low ? semantic.warning : semantic.success,
                  backgroundColor: Theme.of(context)
                      .colorScheme
                      .surfaceContainer,
                  minHeight: 8,
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

TextStyle _readingStyle(BuildContext context, bool compact) =>
    (compact
            ? Theme.of(context).textTheme.titleLarge
            : Theme.of(context).textTheme.headlineSmall)!
        .copyWith(
          fontSize: compact ? 26 : 30,
          fontWeight: FontWeight.w700,
          height: 1.25,
        );

TextStyle _metricLabelStyle(BuildContext context) => Theme.of(context)
    .textTheme
    .bodyMedium!
    .copyWith(
      fontSize: 14,
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
  const _MetricGrid({required this.preferredWidths, required this.children});
  final List<double> preferredWidths;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    if (children.isEmpty) return const SizedBox.shrink();
    return LayoutBuilder(
      builder: (context, constraints) {
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
