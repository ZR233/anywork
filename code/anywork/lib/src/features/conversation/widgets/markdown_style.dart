import 'package:flutter/material.dart';
import '../../../app/theme/studio_tokens.dart';

enum MarkdownSurface { assistant, user, panel, reasoning, error }

TextStyle? markdownBodyStyle(BuildContext context, MarkdownSurface surface) {
  final theme = Theme.of(context);
  // VS Code 预览正文行高 22px/14px ≈ 1.57，各阅读表面保持一致节奏。
  if (surface == MarkdownSurface.reasoning) {
    return theme.textTheme.bodySmall?.copyWith(
      color: context.colors.onSurfaceVariant,
      height: 1.57,
    );
  }
  if (surface == MarkdownSurface.error) {
    return theme.textTheme.bodyMedium?.copyWith(
      color: theme.colorScheme.error,
      height: 1.57,
    );
  }
  return theme.textTheme.bodyMedium?.copyWith(
    color: theme.colorScheme.onSurface,
    height: 1.57,
  );
}
