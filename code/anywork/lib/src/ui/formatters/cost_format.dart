import 'package:anywork_client/account_usage.dart' show RuntimeCost;

const _currencySymbols = <String, String>{'CNY': '￥', 'USD': r'$'};

/// Canonical amount rounded to two decimal places; never converts currencies.
String formatRuntimeCostAmount(String currency, double amount) {
  final rounded = amount.toStringAsFixed(2);
  final display = rounded == '-0.00' ? '0.00' : rounded;
  final symbol = _currencySymbols[currency.toUpperCase()];
  if (symbol != null) return '$symbol$display';
  return '$currency $display'.trim();
}

/// Each supplied currency remains separate. An empty collection remains empty,
/// so the owner can distinguish unknown / unpriced usage from a known zero.
String formatRuntimeCosts(Iterable<RuntimeCost> costs) => costs
    .map((cost) => formatRuntimeCostAmount(cost.currency, cost.amount))
    .where((label) => label.isNotEmpty)
    .join(' + ');
