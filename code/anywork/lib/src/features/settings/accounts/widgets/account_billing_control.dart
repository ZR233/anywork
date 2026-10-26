import 'package:anywork_client/configuration.dart';
import 'package:anywork_client/models.dart';
import 'package:flutter/material.dart';

import '../../../../diagnostics/studio_driver_keys.dart';
import '../../../../l10n/studio_l10n.dart';
import '../../../../ui/labels/delegation_labels.dart';
import '../../state/settings_action.dart';
import '../state/model_limits_state.dart';

class AccountBillingControl extends StatelessWidget {
  const AccountBillingControl({
    required this.account,
    this.action,
    this.onChanged,
    this.errors = const [],
    super.key,
  });
  final AccountConfiguration account;
  final AccountBillingAction? action;
  final ValueChanged<BillingKind?>? onChanged;
  final List<String> errors;

  @override
  Widget build(BuildContext context) {
    final operation = action?.action;
    final blocked =
        operation?.uncertain == true ||
        operation?.outcome == SettingsActionOutcome.synchronizationFailed;
    final width = (MediaQuery.sizeOf(context).width - 48)
        .clamp(0.0, 480.0)
        .toDouble();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            context.l10n.settingsBillingKind,
            style: Theme.of(context).textTheme.titleSmall,
          ),
          Text(
            '${context.l10n.settingsBillingEffective}: ${context.billingKindLabel(account.billingKind)}',
          ),
          MenuAnchor(
            crossAxisUnconstrained: false,
            style: MenuStyle(
              maximumSize: WidgetStatePropertyAll(Size(width, double.infinity)),
            ),
            menuChildren: [
              for (final kind in <BillingKind?>[null, ...BillingKind.values])
                MenuItemButton(
                  key: StudioDriverKeys.billingKindOption(kind),
                  leadingIcon: Icon(
                    kind == account.billingKindOverride ? Icons.check : null,
                  ),
                  onPressed: onChanged == null || blocked
                      ? null
                      : () => onChanged!(kind),
                  child: Text(context.billingKindLabel(kind)),
                ),
            ],
            builder: (context, controller, child) => TextButton(
              key: StudioDriverKeys.accountBillingKind(account.accountId),
              onPressed: onChanged == null || blocked
                  ? null
                  : controller.isOpen
                  ? controller.close
                  : controller.open,
              child: Text(
                context.billingKindLabel(account.billingKindOverride),
              ),
            ),
          ),
          Text(context.l10n.settingsBillingHint),
          if (operation?.pending == true)
            Text(context.l10n.settingsModelSaving),
          for (final error in errors)
            SelectableText(
              error,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
        ],
      ),
    );
  }
}
