import 'package:flutter/material.dart';

import '../../../../l10n/app_localizations.dart';
import '../state/account_presentations.dart';
import 'account_sections.dart';

/// Raw input and presets only emit draft intents. Saving is always explicit.
class AccountCompactView extends StatelessWidget {
  const AccountCompactView({
    required this.value,
    required this.onChanged,
    required this.onPreset,
    required this.onSave,
    required this.onReset,
    required this.onRetry,
    super.key,
  });
  final AccountCompactPresentation value;
  final ValueChanged<String> onChanged;
  final ValueChanged<int> onPreset;
  final VoidCallback onSave;
  final VoidCallback onReset;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final textTheme = Theme.of(context).textTheme;
    return Card.filled(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final explanation = Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.settingsModelAutoCompactTitle,
                  style: textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                if (value.effective != null)
                  AccountSelectableText(
                    '${l10n.settingsModelAutoCompactEffectiveLabel} · ${value.effective}',
                    style: textTheme.labelMedium,
                  ),
                if (value.automatic != null &&
                    value.automatic != value.effective)
                  AccountSelectableText(
                    '${l10n.accountsAutomatic} · ${value.automatic}',
                    style: textTheme.labelMedium,
                  ),
                const SizedBox(height: 8),
                Text(
                  value.adjusted
                      ? l10n.accountsCompactAdjusted
                      : l10n.settingsModelAutoCompactHelp,
                  style: textTheme.bodySmall,
                ),
                if (value.dirty)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      l10n.accountsDirty,
                      style: textTheme.labelSmall,
                    ),
                  ),
              ],
            );
            final controls = LayoutBuilder(
              builder: (context, constraints) => Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final percent in const [25, 50, 75, 90])
                        ActionChip(
                          label: Text('$percent%'),
                          visualDensity: VisualDensity.compact,
                          onPressed:
                              value.canEdit &&
                                  value.contextWindow != null &&
                                  !value.saving
                              ? () => onPreset(percent)
                              : null,
                        ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      SizedBox(
                        width: constraints.maxWidth.clamp(0, 230).toDouble(),
                        child: AccountRawTextField(
                          key: const ValueKey<String>('account-compact-input'),
                          value: AccountTextPresentation(
                            raw: value.raw,
                            error: value.error,
                          ),
                          label: l10n.settingsModelAutoCompactInputLabel,
                          onChanged: onChanged,
                          enabled: value.canEdit && !value.saving,
                          keyboardType: TextInputType.number,
                        ),
                      ),
                      FilledButton(
                        key: const ValueKey<String>('account-compact-save'),
                        onPressed: value.canSave && !value.saving
                            ? onSave
                            : null,
                        child: Text(l10n.commonSave),
                      ),
                      if (value.canReset)
                        TextButton.icon(
                          key: const ValueKey<String>('account-compact-reset'),
                          onPressed: value.saving ? null : onReset,
                          icon: const Icon(Icons.restart_alt, size: 18),
                          label: Text(l10n.settingsModelAutoCompactRestore),
                        ),
                    ],
                  ),
                  if (value.saving) const LinearProgressIndicator(minHeight: 2),
                  if (value.canRetry)
                    TextButton(
                      onPressed: onRetry,
                      child: Text(l10n.settingsModelAutoCompactRetry),
                    ),
                ],
              ),
            );
            return constraints.maxWidth >=
                    720 * MediaQuery.textScalerOf(context).scale(1)
                ? Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: explanation),
                      const SizedBox(width: 24),
                      Expanded(child: controls),
                    ],
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      explanation,
                      const SizedBox(height: 12),
                      controls,
                    ],
                  );
          },
        ),
      ),
    );
  }
}
