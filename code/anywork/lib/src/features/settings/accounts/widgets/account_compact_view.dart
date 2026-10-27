import 'package:flutter/material.dart';

import '../../../../l10n/app_localizations.dart';
import '../state/account_presentations.dart';
import 'account_sections.dart';

class AccountCompactView extends StatelessWidget {
  const AccountCompactView({
    required this.value,
    required this.onChanged,
    required this.onReset,
    required this.onRetry,
    super.key,
  });
  final AccountCompactPresentation value;
  final ValueChanged<String> onChanged;
  final VoidCallback onReset;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Divider(height: 24),
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              '${l10n.settingsModelAutoCompactTitle} · ${value.overridden ? l10n.accountsOverride : l10n.accountsAutomatic}',
              style: Theme.of(context).textTheme.titleSmall
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            if (value.canReset)
              TextButton.icon(
                onPressed: value.saving ? null : onReset,
                icon: const Icon(Icons.restart_alt, size: 18),
                label: Text(l10n.settingsModelAutoCompactRestore),
              ),
          ],
        ),
        const SizedBox(height: 8),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 360),
            child: AccountRawTextField(
              value: AccountTextPresentation(
                raw: value.raw,
                error: value.error,
              ),
              label: l10n.settingsModelAutoCompactInputLabel,
              onChanged: onChanged,
              enabled: value.canEdit,
              keyboardType: TextInputType.number,
            ),
          ),
        ),
        // No parsing, rounding or filtering: exact raw intent goes to the VM.
        AccountFacts(
          facts: [
            if (value.effective != null && value.effective != value.raw)
              AccountDisplayFact(
                label: l10n.settingsModelAutoCompactEffectiveLabel,
                value: value.effective!,
              ),
            if (value.automatic != null &&
                value.automatic != value.effective &&
                value.automatic != value.raw)
              AccountDisplayFact(
                label: l10n.accountsAutomatic,
                value: value.automatic!,
              ),
          ],
        ),
        Text(
          l10n.settingsModelAutoCompactHelp,
          style: Theme.of(context).textTheme.bodySmall,
        ),
        if (value.saving) Text(l10n.settingsModelAutoCompactSaving),
        if (value.canRetry)
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton(
              onPressed: onRetry,
              child: Text(l10n.settingsModelAutoCompactRetry),
            ),
          ),
      ],
    );
  }
}
