/// Only formats the canonical throughput; the localized unit belongs to l10n.
/// This does not calculate a rate or fill missing samples with zero.
String? formatTokenThroughputValue(double? tokensPerSecond) {
  if (tokensPerSecond == null || !tokensPerSecond.isFinite) return null;
  return tokensPerSecond >= 10
      ? tokensPerSecond.round().toString()
      : tokensPerSecond.toStringAsFixed(1);
}
