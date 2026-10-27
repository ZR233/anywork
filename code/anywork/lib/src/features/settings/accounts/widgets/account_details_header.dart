import 'package:flutter/material.dart';

import '../../../../l10n/app_localizations.dart';
import '../../../../shared/account_brand.dart';
import '../state/account_presentations.dart';
import 'account_sections.dart';

class AccountDetailsHeader extends StatelessWidget {
  const AccountDetailsHeader({
    required this.value,
    required this.onEdit,
    required this.onDelete,
    required this.onSetDefault,
    super.key,
  });
  final AccountDetailsPresentation value;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onSetDefault;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final identity = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AccountBrandMark(
          fallbackName: value.name,
          iconKey: value.iconKey,
          size: 76,
        ),
        const SizedBox(width: 24),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                value.name,
                style: Theme.of(context).textTheme.headlineLarge
                    ?.copyWith(fontWeight: FontWeight.w800),
              ),
              if (value.endpoint != null)
                AccountSelectableText(
                  value.endpoint!,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
            ],
          ),
        ),
      ],
    );
    final actions = Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        if (value.canEdit)
          OutlinedButton.icon(
            style: accountActionButtonStyle(context),
            key: const ValueKey<String>('account-edit'),
            onPressed: onEdit,
            icon: const Icon(Icons.edit_outlined),
            label: Text(l10n.settingsEditAccount),
          ),
        if (value.canSetDefault || value.canDelete)
          AccountMenuButton(
            buttonKey: const ValueKey<String>('account-details-menu'),
            tooltip: l10n.settingsAccountActions,
            menuChildren: [
              if (value.canSetDefault)
                MenuItemButton(
                  key: const ValueKey<String>('account-details-set-default'),
                  onPressed: onSetDefault,
                  leadingIcon: const Icon(Icons.star_outline),
                  child: Text(l10n.settingsSetAsDefaultAccount),
                ),
              if (value.canDelete)
                MenuItemButton(
                  key: const ValueKey<String>('account-details-delete'),
                  onPressed: onDelete,
                  leadingIcon: const Icon(Icons.delete_outline),
                  child: Text(l10n.settingsDeleteAccount),
                ),
            ],
          ),
      ],
    );
    return LayoutBuilder(
      builder: (context, constraints) =>
          constraints.maxWidth >=
              680 * MediaQuery.textScalerOf(context).scale(1)
          ? Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(child: identity),
                const SizedBox(width: 24),
                actions,
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [identity, const SizedBox(height: 12), actions],
            ),
    );
  }
}
