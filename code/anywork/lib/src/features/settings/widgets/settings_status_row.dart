import 'package:flutter/material.dart';

import '../../../app/theme/studio_tokens.dart';
import '../../../l10n/studio_l10n.dart';

/// Compact source / subscription status line.
///
/// A healthy or still-connecting source renders nothing: the page must not
/// occupy space with a status the user cannot act on. A degraded source states
/// the real reason and keeps an explicit retry entry, and it never presents a
/// last-known value as current evidence.
class SettingsStatusRow extends StatelessWidget {
  const SettingsStatusRow({
    required this.failed,
    required this.message,
    this.onRetry,
    this.retryLabel,
    this.retryKey,
    super.key,
  });

  final bool failed;
  final String message;
  final VoidCallback? onRetry;
  final String? retryLabel;
  final Key? retryKey;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Icon(
            failed ? Icons.error_outline : Icons.sync_problem_outlined,
            size: 16,
            color: failed ? context.colors.error : context.statusColors.warning,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: context.text.bodySmall?.copyWith(
                color: context.colors.onSurfaceVariant,
              ),
            ),
          ),
          if (failed && onRetry != null)
            TextButton.icon(
              key: retryKey,
              onPressed: onRetry,
              icon: const Icon(Icons.refresh, size: 16),
              label: Text(retryLabel ?? context.l10n.sidebarRetry),
            ),
        ],
      ),
    );
  }
}
