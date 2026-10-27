import 'package:flutter/material.dart';

import '../../../../l10n/app_localizations.dart';
import '../../../../shared/account_brand.dart';
import '../state/account_presentations.dart';
import '../state/account_view_key_values.dart';

class AccountTemplatePickerView extends StatelessWidget {
  const AccountTemplatePickerView({
    required this.templates,
    required this.onSelected,
    required this.onCancel,
    super.key,
  });
  final List<AccountTemplatePresentation> templates;
  final ValueChanged<AccountTemplateKey> onSelected;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              Text(
                l10n.settingsAddAccount,
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: 8),
              Text(l10n.accountsTemplatePickerHint),
              // Keep official ACP integrations visible before the larger API catalog.
              for (final kind in [AccountKind.acp, AccountKind.native]) ...[
                Padding(
                  padding: const EdgeInsets.only(top: 24, bottom: 12),
                  child: Text(
                    kind == AccountKind.native
                        ? l10n.acpAccountPickerNativeGroup
                        : l10n.acpAccountPickerAcpGroup,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                for (final template in templates.where(
                  (template) => template.key.kind == kind,
                ))
                  ListTile(
                    key: ValueKey<String>(
                      AccountViewKeyValues.template(
                        template.key.kind.name,
                        template.key.id,
                      ),
                    ),
                    leading: AccountBrandMark(
                      fallbackName: template.name,
                      iconKey: template.iconKey,
                    ),
                    title: Text(template.name),
                    subtitle: template.description == null
                        ? null
                        : Text(template.description!),
                    onTap: () => onSelected(template.key),
                  ),
              ],
            ],
          ),
        ),
        Align(
          alignment: AlignmentDirectional.centerEnd,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: OutlinedButton(
              onPressed: onCancel,
              child: Text(l10n.commonCancel),
            ),
          ),
        ),
      ],
    );
  }
}

/// Caller shows the dialog and interprets the result; this view never saves.
class AccountUnsavedChangesDialog extends StatelessWidget {
  const AccountUnsavedChangesDialog({
    required this.onChoice,
    this.canSave = true,
    this.saving = false,
    this.error,
    super.key,
  });
  final ValueChanged<AccountLeaveChoice> onChoice;
  final bool canSave;
  final bool saving;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(l10n.accountsUnsavedTitle),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.accountsUnsavedBody),
          if (saving)
            const Padding(
              padding: EdgeInsets.only(top: 12),
              child: LinearProgressIndicator(),
            ),
          if (error != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(
                error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => onChoice(AccountLeaveChoice.cancel),
          child: Text(l10n.accountsKeepEditing),
        ),
        TextButton(
          onPressed: saving ? null : () => onChoice(AccountLeaveChoice.discard),
          child: Text(l10n.accountsDiscard),
        ),
        FilledButton(
          onPressed: canSave && !saving
              ? () => onChoice(AccountLeaveChoice.save)
              : null,
          child: Text(l10n.commonSave),
        ),
      ],
    );
  }
}

/// Reference checks and deletion belong to the external owner.
class AccountDeleteDialog extends StatelessWidget {
  const AccountDeleteDialog({
    required this.name,
    required this.onConfirm,
    required this.onCancel,
    this.manualModel = false,
    this.canConfirm = true,
    this.error,
    super.key,
  });
  final String name;
  final bool manualModel;
  final bool canConfirm;
  final String? error;
  final VoidCallback onConfirm;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(
        manualModel
            ? l10n.settingsRemoveManualModelConfirmTitle
            : l10n.accountsDeleteTitle,
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(name, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          Text(
            manualModel
                ? l10n.settingsRemoveManualModelConfirmBody
                : l10n.accountsDeleteBody,
          ),
          if (error != null)
            Text(
              error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
        ],
      ),
      actions: [
        TextButton(onPressed: onCancel, child: Text(l10n.commonCancel)),
        FilledButton(
          onPressed: canConfirm ? onConfirm : null,
          child: Text(l10n.settingsRemoveManualModelConfirmAction),
        ),
      ],
    );
  }
}
