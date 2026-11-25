import 'package:material_ui/material_ui.dart';

import '../../../../l10n/app_localizations.dart';
import '../state/account_presentations.dart';

/// Caller shows the dialog and interprets the result; this view never saves.
class AccountUnsavedChangesDialog extends StatelessWidget {
  const AccountUnsavedChangesDialog({
    required this.onChoice,
    this.canSave = true,
    this.canDiscard = true,
    this.saving = false,
    this.error,
    this.warning,
    super.key,
  });
  final ValueChanged<AccountLeaveChoice> onChoice;
  final bool canSave;
  final bool canDiscard;
  final bool saving;
  final String? error;
  final String? warning;

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
          if (warning != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(warning!),
            ),
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
          onPressed: saving || !canDiscard
              ? null
              : () => onChoice(AccountLeaveChoice.discard),
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
