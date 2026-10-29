import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../l10n/app_localizations.dart';
import '../../../../platform/external_url_launcher.dart';
import '../state/account_presentations.dart';
import '../state/account_view_state.dart';
import '../view_models/account_models_view_model.dart';
import '../view_models/accounts_view_model.dart';
import '../view_models/acp_account_view_model.dart';
import '../views/account_dialogs.dart';
import '../widgets/account_models_view.dart';
import 'account_navigation.dart';

Future<bool> confirmAccountDelete(
  BuildContext context,
  String name, {
  bool manualModel = false,
}) async =>
    await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AccountDeleteDialog(
        name: name,
        manualModel: manualModel,
        onConfirm: () => Navigator.of(dialogContext).pop(true),
        onCancel: () => Navigator.of(dialogContext).pop(false),
      ),
    ) ??
    false;

Future<void> deleteAccount(
  BuildContext context,
  WidgetRef ref,
  AccountDisplayKey key,
) async {
  final navigation = ref.read(accountsViewModelProvider.notifier);
  if (!await confirmLeaveAccountsEditor(context) || !context.mounted) {
    return;
  }
  final name = navigation.accountName(key);
  AccountDisplayKey? replacement;
  if (navigation.needsReplacement(key)) {
    final candidates = navigation.replacements(key);
    replacement = await showDialog<AccountDisplayKey>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: Text(AppLocalizations.of(context).settingsSetAsDefaultAccount),
        children: [
          for (final candidate in candidates)
            SimpleDialogOption(
              onPressed: () => Navigator.of(dialogContext).pop(candidate.key),
              child: Text(candidate.name),
            ),
        ],
      ),
    );
    if (replacement == null || !context.mounted) return;
  }
  if (!await confirmAccountDelete(context, name) || !context.mounted) return;
  await navigation.remove(key, replacement: replacement);
}

AccountModelActions accountModelActions(BuildContext context, WidgetRef ref) =>
    AccountModelActions(
      onEnabledChanged: (key, enabled) => ref
          .read(accountModelsViewModelProvider(key.account).notifier)
          .setEnabled(key.modelId, enabled),
      onConnectionChanged: (key, connection) => ref
          .read(accountModelsViewModelProvider(key.account).notifier)
          .setConnection(key.modelId, connection),
      onCompactChanged: (key, raw) => ref
          .read(accountModelsViewModelProvider(key.account).notifier)
          .changeCompact(key.modelId, raw),
      onAction: (key, action) async {
        final owner = ref.read(
          accountModelsViewModelProvider(key.account).notifier,
        );
        switch (action) {
          case AccountModelAction.loadReadout ||
              AccountModelAction.retryReadout:
            await owner.loadReadout(key.modelId);
          case AccountModelAction.resetCompact:
            await owner.resetCompact(key.modelId);
          case AccountModelAction.retryCompact:
            await owner.retryCompact(key.modelId);
          case AccountModelAction.delete:
            if (await confirmAccountDelete(
              context,
              key.modelId,
              manualModel: true,
            )) {
              await owner.removeManual(key.modelId);
            }
          case AccountModelAction.edit:
            if (await confirmLeaveAccountsEditor(context) && context.mounted) {
              ref.read(accountsViewModelProvider.notifier).edit(key.account);
            }
        }
      },
    );

Future<void> performAcpAction(
  BuildContext context,
  WidgetRef ref,
  AccountAcpKey key,
  AcpAccountAction action,
) async {
  final owner = ref.read(acpAccountViewModelProvider(key).notifier);
  switch (action) {
    case AcpAccountAction.prepare:
      await owner.prepare();
    case AcpAccountAction.cancelPreparation:
      await owner.cancelPreparation();
    case AcpAccountAction.usePrepared:
      owner.usePrepared();
    case AcpAccountAction.check ||
        AcpAccountAction.verify ||
        AcpAccountAction.retry:
      await owner.authenticate();
    case AcpAccountAction.login:
      await owner.authenticate(login: true);
    case AcpAccountAction.cancelAuthentication:
      await owner.cancelAuthentication();
    case AcpAccountAction.openGuide || AcpAccountAction.openTerms:
      final url = owner.documentationUrl(action);
      if (url == null || url.isEmpty) return;
      try {
        await ref.read(externalUrlLauncherProvider)(url);
      } catch (_) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                AppLocalizations.of(context).acpAuthCommandUnavailable,
              ),
            ),
          );
        }
      }
  }
}
