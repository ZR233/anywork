import 'package:flutter/material.dart';

import '../../../../l10n/app_localizations.dart';
import '../state/account_presentations.dart';
import 'account_menu_button.dart';
import 'account_sections.dart'
    show AccountInlineError, accountBillingLabel, accountActionButtonStyle;

enum AccountBillingControlLayout { settingsRow, field }

class AccountBillingControl extends StatefulWidget {
  const AccountBillingControl({
    required this.value,
    required this.onChanged,
    required this.onReset,
    this.layout = AccountBillingControlLayout.settingsRow,
    super.key,
  });
  final AccountBillingPresentation value;
  final ValueChanged<AccountBilling> onChanged;
  final VoidCallback onReset;
  final AccountBillingControlLayout layout;

  @override
  State<AccountBillingControl> createState() => _AccountBillingControlState();
}

class _AccountBillingControlState extends State<AccountBillingControl> {
  final TextEditingController _selection = TextEditingController();

  void _restoreSelection() {
    final l10n = AppLocalizations.of(context);
    final value = widget.value;
    _selection.text = value.billingKindOverride == null
        ? l10n.accountsAutomatic
        : accountBillingLabel(l10n, value.billingKindOverride!);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _restoreSelection();
  }

  @override
  void didUpdateWidget(covariant AccountBillingControl oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value.billingKindOverride !=
            widget.value.billingKindOverride ||
        oldWidget.value.effective != widget.value.effective) {
      _restoreSelection();
    }
  }

  @override
  void dispose() {
    _selection.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final value = widget.value;
    final onReset = widget.onReset;
    final onChanged = widget.onChanged;
    final layout = widget.layout;
    final l10n = AppLocalizations.of(context);
    if (layout == AccountBillingControlLayout.field) {
      return LayoutBuilder(
        builder: (context, constraints) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            DropdownMenu<AccountBilling?>(
              controller: _selection,
              width: constraints.maxWidth,
              enabled: !value.saving,
              requestFocusOnTap: false,
              initialSelection: value.billingKindOverride,
              label: Text(l10n.settingsBillingKind),
              menuHeight: 320,
              dropdownMenuEntries: [
                DropdownMenuEntry(value: null, label: l10n.accountsAutomatic),
                for (final billing in value.allowedOverrides)
                  DropdownMenuEntry(
                    value: billing,
                    label: accountBillingLabel(l10n, billing),
                  ),
              ],
              onSelected: (billing) {
                _restoreSelection();
                billing == null ? onReset() : onChanged(billing);
              },
            ),
            const SizedBox(height: 8),
            Text(
              l10n.accountsBillingDisclaimer,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            if (value.saving) const LinearProgressIndicator(minHeight: 2),
            if (value.error != null) AccountInlineError(message: value.error!),
          ],
        ),
      );
    }
    final selection = Wrap(
      spacing: 8,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text(
          '${accountBillingLabel(l10n, value.effective)} · '
          '${value.billingKindOverride == null ? l10n.settingsBillingAutomatic : l10n.settingsBillingOverride}',
          style: Theme.of(context).textTheme.bodyMedium,
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
                      style: Theme.of(context).textTheme.bodyMedium,
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
                        style: Theme.of(context).textTheme.bodyMedium,
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
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }
}
