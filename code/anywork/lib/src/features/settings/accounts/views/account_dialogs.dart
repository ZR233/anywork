import 'package:flutter/material.dart';

import '../../../../l10n/app_localizations.dart';
import '../widgets/account_template_selector.dart';
import '../state/account_presentations.dart';

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
              const SizedBox(height: 24),
              AccountTemplateSelector(
                templates: templates,
                selected: null,
                onSelected: onSelected,
              ),
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
