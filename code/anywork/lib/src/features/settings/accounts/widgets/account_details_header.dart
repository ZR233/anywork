import 'package:flutter/material.dart';

import '../../../../l10n/app_localizations.dart';
import 'account_identity.dart';
import '../state/account_presentations.dart';
import 'account_sections.dart';
import 'account_usage_view.dart';

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
    final identity = AccountIdentity(
      name: value.name,
      iconKey: value.iconKey,
      subtitle: value.endpoint,
      layout: AccountIdentityLayout.header,
      badge: switch (value.content) {
        NativeAccountDetailsContent(:final value) => AccountBillingBadge(
          billing: value.billing.effective,
        ),
        AcpAccountDetailsContent() => null,
      },
    );
    final actions = Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        if (value.canSetDefault)
          TextButton.icon(
            key: const ValueKey<String>('account-details-set-default'),
            onPressed: onSetDefault,
            icon: const Icon(Icons.star_outline, size: 18),
            label: Text(l10n.settingsSetAsDefaultAccount),
          ),
        if (value.canEdit)
          OutlinedButton.icon(
            style: accountActionButtonStyle(context),
            key: const ValueKey<String>('account-edit'),
            onPressed: onEdit,
            icon: const Icon(Icons.edit_outlined),
            label: Text(l10n.settingsEditAccount),
          ),
        if (value.canDelete)
          IconButton(
            key: const ValueKey<String>('account-details-delete'),
            tooltip: l10n.settingsDeleteAccount,
            onPressed: onDelete,
            icon: const Icon(Icons.delete_outline, size: 20),
          ),
      ],
    );
    return LayoutBuilder(
      builder: (context, constraints) =>
          constraints.maxWidth >=
              760 * MediaQuery.textScalerOf(context).scale(1)
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
