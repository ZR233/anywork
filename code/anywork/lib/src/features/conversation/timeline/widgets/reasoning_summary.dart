String? inlineReasoningSummaryMarkdown(String raw) {
  final trimmed = raw.trim();
  if (trimmed.isEmpty || trimmed == '<!-- -->') return null;
  final firstLine = trimmed
      .split(RegExp(r'\r?\n'))
      .map((line) => line.trim())
      .firstWhere((line) => line.isNotEmpty, orElse: () => '');
  if (firstLine.isEmpty) return null;
  final withoutBlockPrefix = firstLine
      .replaceFirst(RegExp(r'^#{1,6}\s+'), '')
      .replaceFirst(RegExp(r'^>\s*'), '')
      .replaceFirst(RegExp(r'^(?:[-+*]|\d+[.)])\s+'), '')
      .trim();
  return withoutBlockPrefix.isEmpty ? null : withoutBlockPrefix;
}
