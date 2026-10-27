import 'package:flutter/material.dart';

import '../../../../l10n/app_localizations.dart';
import '../state/account_presentations.dart';
import 'account_menu_button.dart';
import 'account_sections.dart'
    show AccountInlineError, accountBillingLabel, accountActionButtonStyle;

class AccountBillingControl extends StatelessWidget {
  const AccountBillingControl({
    required this.value,
    required this.onChanged,
    required this.onReset,
    super.key,
  });
  final AccountBillingPresentation value;
  final ValueChanged<AccountBilling> onChanged;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final selection = Wrap(
      spacing: 8,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text(
          '${accountBillingLabel(l10n, value.effective)} · '
          '${value.billingKindOverride == null ? l10n.settingsBillingAutomatic : l10n.settingsBillingOverride}',
          style: Theme.of(context).textTheme.bodyLarge?.copyWith(fontSize: 16),
        ),
        if (value.allowedOverrides.isNotEmpty)
          AccountMenuButton(
            buttonKey: const ValueKey<String>('account-billing-menu'),
            tooltip: l10n.settingsBillingKind,
            label: l10n.settingsBillingKind,
            menuChildren: [
              if (value.billingKindOverride != null) ...[
                MenuItemButton(
                  key: const ValueKey<String>('account-billing-automatic'),
                  onPressed: value.saving ? null : onReset,
                  leadingIcon: const Icon(Icons.restart_alt, size: 18),
                  child: Text(l10n.settingsModelAutoCompactRestore),
                ),
                const Divider(),
              ],
              for (final billing in value.allowedOverrides)
                MenuItemButton(
                  key: ValueKey<String>('account-billing-${billing.name}'),
                  onPressed: value.saving ? null : () => onChanged(billing),
                  leadingIcon: Icon(
                    value.billingKindOverride == billing
                        ? Icons.check
                        : Icons.circle_outlined,
                    size: 18,
                  ),
                  child: Text(accountBillingLabel(l10n, billing)),
                ),
            ],
          ),
        if (value.billingKindOverride != null)
          TextButton.icon(
            style: accountActionButtonStyle(context),
            onPressed: value.saving ? null : onReset,
            icon: const Icon(Icons.restart_alt, size: 18),
            label: Text(l10n.settingsModelAutoCompactRestore),
          ),
      ],
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LayoutBuilder(
          builder: (context, constraints) => constraints.maxWidth < 460
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.settingsBillingEffective,
                      style: Theme.of(context).textTheme.bodyLarge
                          ?.copyWith(fontSize: 16),
                    ),
                    selection,
                  ],
                )
              : Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    SizedBox(
                      width: 180,
                      child: Text(
                        l10n.settingsBillingEffective,
                        style: Theme.of(context).textTheme.bodyLarge
                            ?.copyWith(fontSize: 16),
                      ),
                    ),
                    Expanded(child: selection),
                  ],
                ),
        ),
        if (value.saving) const LinearProgressIndicator(minHeight: 2),
        if (value.error != null) AccountInlineError(message: value.error!),
        const SizedBox(height: 8),
        Text(
          l10n.accountsBillingDisclaimer,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontSize: 14),
        ),
      ],
    );
  }
}
