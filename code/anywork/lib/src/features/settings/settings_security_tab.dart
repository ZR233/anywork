import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/theme/studio_tokens.dart';
import '../../domain/models/studio_models.dart';
import '../../l10n/studio_l10n.dart';
import 'settings_common.dart';

class SecurityTab extends StatelessWidget {
  const SecurityTab({
    super.key,
    required this.mode,
    required this.pending,
    required this.onSelected,
  });

  final PermissionMode mode;
  final bool pending;
  final Future<void> Function(PermissionMode) onSelected;

  @override
  Widget build(BuildContext context) {
    return SettingsPane(
      header: SettingsHeader(
        title: context.l10n.settingsSecurityTitle,
        subtitle: context.l10n.settingsSecurityModeSubtitle,
      ),
      maxWidth: 880,
      children: [
        RadioGroup<PermissionMode>(
          groupValue: mode,
          onChanged: (value) {
            if (pending) return;
            if (value != null) {
              unawaited(_savePermissionMode(context, () => onSelected(value)));
            }
          },
          child: Column(
            children: [
              for (final option in PermissionMode.values)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: RadioListTile<PermissionMode>(
                    key: ValueKey('permission-choice-${option.name}'),
                    value: option,
                    enabled: !pending,
                    title: Text(context.permissionModeLabel(option)),
                    subtitle: Text(switch (option) {
                      PermissionMode.requestApproval =>
                        context.l10n.settingsPermissionRequestDescription,
                      PermissionMode.autoReview =>
                        context.l10n.settingsPermissionReviewDescription,
                      PermissionMode.fullAccess =>
                        context.l10n.settingsPermissionFullDescription,
                    }),
                    selected: option == mode,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    selectedTileColor: context.colors.surfaceContainer,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 12,
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Text(
          context.l10n.settingsWorkspaceBoundary,
          style: context.text.bodySmall?.copyWith(
            color: context.colors.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

Future<void> _savePermissionMode(
  BuildContext context,
  Future<void> Function() action,
) async {
  try {
    await action();
  } catch (error) {
    if (!context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(SnackBar(content: Text(error.toString())));
  }
}
