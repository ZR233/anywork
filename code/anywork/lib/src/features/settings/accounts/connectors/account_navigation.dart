import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/account_presentations.dart';
import '../view_models/account_editor_view_model.dart';
import '../view_models/accounts_view_model.dart';
import '../views/account_dialogs.dart';

/// All external and internal exits use the same decision. Looking up whether
/// an editor exists must not create an accounts page or a new draft.
Future<bool> confirmLeaveAccountsEditor(BuildContext context) async {
  final container = ProviderScope.containerOf(context, listen: false);
  if (!container.exists(accountsViewModelProvider)) return true;
  final navigation = container.read(accountsViewModelProvider).asData?.value;
  final key = navigation?.editor;
  if (key == null || !container.exists(accountEditorViewModelProvider(key))) {
    return true;
  }
  final editor = container.read(accountEditorViewModelProvider(key).notifier);
  final state = container
      .read(accountEditorViewModelProvider(key))
      .asData
      ?.value;
  if (state == null) return false;
  void finish() {
    editor.finish();
    container.read(accountsViewModelProvider.notifier).finishEditor(key);
  }

  if (!state.dirty && !state.saving) {
    finish();
    return true;
  }
  return await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => Consumer(
          builder: (context, dialogRef, _) {
            final value = dialogRef
                .watch(accountEditorViewModelProvider(key))
                .asData
                ?.value;
            return AccountUnsavedChangesDialog(
              canSave: value?.canSave ?? false,
              saving: value?.saving ?? false,
              error: value?.error,
              onChoice: (choice) async {
                switch (choice) {
                  case AccountLeaveChoice.cancel:
                    Navigator.of(dialogContext).pop(false);
                  case AccountLeaveChoice.discard:
                    if (!await editor.requestLeave(choice)) return;
                    finish();
                    if (dialogContext.mounted) {
                      Navigator.of(dialogContext).pop(true);
                    }
                  case AccountLeaveChoice.save:
                    if (!await editor.requestLeave(choice)) return;
                    if (!dialogContext.mounted) return;
                    finish();
                    Navigator.of(dialogContext).pop(true);
                }
              },
            );
          },
        ),
      ) ??
      false;
}
