import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../l10n/app_localizations.dart';
import '../../../../app/routing/app_route.dart';
import '../../../../platform/external_url_launcher.dart';
import '../../../../presentation/providers/account_domains.dart';
import '../state/account_presentations.dart';
import '../state/account_view_state.dart';
import '../view_models/account_models_view_model.dart';
import '../view_models/accounts_view_model.dart';
import '../view_models/account_projection.dart' show domainIdentity;
import '../view_models/acp_account_view_model.dart';
import '../views/account_dialogs.dart';
import '../widgets/account_models_view.dart';

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
  final sourceRoute = ModalRoute.of(context);
  if (sourceRoute == null || !sourceRoute.isCurrent) return;
  final container = ProviderScope.containerOf(context, listen: false);
  final accounts = ref.read(accountsViewModelProvider.notifier);
  final repository = container.read(accountsRepositoryProvider);
  final identity = domainIdentity(key);
  final initial = repository.state.value;
  final target = initial.account(identity);
  if (!initial.loaded || target == null || !target.capabilities.remove) return;
  final ownerEpoch = initial.stamp?.ownerEpoch;
  final modelsProvider = key.kind == AccountKind.native
      ? accountModelsViewModelProvider(key)
      : null;
  final modelsOwner = modelsProvider != null && container.exists(modelsProvider)
      ? container.read(modelsProvider.notifier)
      : null;
  final compactToken = modelsOwner?.compactLeaveToken();
  // This synchronous resource-only predicate is consumed once by Accounts.
  // An absent owner must remain absent; checking must never create one.
  bool isCompactClean() {
    if (modelsProvider == null) return true;
    if (modelsOwner == null) return !container.exists(modelsProvider);
    return container.exists(modelsProvider) &&
        identical(container.read(modelsProvider.notifier), modelsOwner) &&
        modelsOwner.canRemove(expectedToken: compactToken!);
  }

  bool sourceCurrent() =>
      context.mounted &&
      identical(ModalRoute.of(context), sourceRoute) &&
      sourceRoute.isCurrent &&
      container.exists(accountsViewModelProvider) &&
      identical(container.read(accountsViewModelProvider.notifier), accounts) &&
      container.exists(accountsRepositoryProvider) &&
      identical(container.read(accountsRepositoryProvider), repository) &&
      repository.state.value.loaded &&
      repository.state.value.stamp?.ownerEpoch == ownerEpoch;
  bool targetCurrent() {
    if (!sourceCurrent() ||
        accounts.isRemovalBlocked(key) ||
        !isCompactClean()) {
      return false;
    }
    final current = repository.state.value.account(identity);
    return current != null &&
        current.identity == target.identity &&
        current.capabilities.remove &&
        current.isDefault == target.isDefault &&
        current.acpConnectionRevision == target.acpConnectionRevision;
  }

  if (!targetCurrent()) return;
  final name = accounts.accountName(key);
  final needsReplacement = accounts.needsReplacement(key);
  AccountDisplayKey? replacement;
  if (needsReplacement) {
    final candidates = accounts.replacements(key);
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
    if (replacement == null || !targetCurrent()) return;
  }
  if (!context.mounted || !targetCurrent()) return;
  if (!await confirmAccountDelete(context, name) || !targetCurrent()) return;
  if (accounts.needsReplacement(key) != needsReplacement ||
      (replacement != null &&
          !accounts.replacements(key).any((row) => row.key == replacement))) {
    return;
  }
  if (!targetCurrent()) return;
  final removed = await accounts.remove(
    key,
    replacement: replacement,
    isCompactClean: isCompactClean,
  );
  // An admitted removal remains domain-owned. Only its still-current source
  // may navigate on success, and an already-recreated target is not absence.
  if (removed &&
      sourceCurrent() &&
      repository.state.value.account(identity) == null) {
    if (!context.mounted) return;
    const SettingsRoute().go(context);
  }
}

AccountModelActions accountModelActions(
  BuildContext context,
  WidgetRef ref,
) => AccountModelActions(
  onEnabledChanged: (key, enabled) => ref
      .read(accountModelsViewModelProvider(key.account).notifier)
      .setEnabled(key.modelId, enabled),
  onConnectionChanged: (key, connection) => ref
      .read(accountModelsViewModelProvider(key.account).notifier)
      .setConnection(key.modelId, connection),
  onCompactChanged: (key, raw) => ref
      .read(accountModelsViewModelProvider(key.account).notifier)
      .changeCompact(key.modelId, raw),
  onCompactPreset: (key, percent) => ref
      .read(accountModelsViewModelProvider(key.account).notifier)
      .presetCompact(key.modelId, percent),
  onAction: (key, action) async {
    if (action == AccountModelAction.delete &&
        (!context.mounted ||
            ModalRoute.of(context)?.isCurrent != true ||
            !ref.exists(accountModelsViewModelProvider(key.account)))) {
      return;
    }
    final owner = ref.read(
      accountModelsViewModelProvider(key.account).notifier,
    );
    switch (action) {
      case AccountModelAction.loadReadout:
        AccountModelRoute(
          kind: key.account.kind,
          accountId: key.account.id,
          modelId: key.modelId,
        ).go(context);
      case AccountModelAction.retryReadout:
        await owner.loadReadout(key.modelId);
      case AccountModelAction.saveCompact:
        await owner.saveCompact(key.modelId);
      case AccountModelAction.resetCompact:
        await owner.resetCompact(key.modelId);
      case AccountModelAction.retryCompact:
        await owner.retryCompact(key.modelId);
      case AccountModelAction.delete:
        final sourceRoute = ModalRoute.of(context);
        if (sourceRoute == null ||
            !sourceRoute.isCurrent ||
            key.account.kind != AccountKind.native) {
          return;
        }
        final container = ProviderScope.containerOf(context, listen: false);
        final provider = accountModelsViewModelProvider(key.account);
        final repository = container.read(modelsRepositoryProvider);
        final account = domainIdentity(key.account);
        final catalogOwner =
            repository.state.value.accounts[account]?.stamp?.ownerEpoch;
        final configOwner =
            repository.state.value.configurations[account]?.stamp?.ownerEpoch;
        final compactToken = owner.compactLeaveToken();
        bool targetCurrent() {
          if (!context.mounted ||
              !identical(ModalRoute.of(context), sourceRoute) ||
              !sourceRoute.isCurrent ||
              !container.exists(provider) ||
              !identical(container.read(provider.notifier), owner) ||
              !owner.canRemove(expectedToken: compactToken) ||
              !container.exists(modelsRepositoryProvider) ||
              !identical(
                container.read(modelsRepositoryProvider),
                repository,
              )) {
            return false;
          }
          final current = repository.state.value;
          if (current.accounts[account]?.loaded != true ||
              current.configurations[account]?.loaded != true ||
              current.accounts[account]?.stamp?.ownerEpoch != catalogOwner ||
              current.configurations[account]?.stamp?.ownerEpoch !=
                  configOwner) {
            return false;
          }
          final model = container
              .read(provider)
              .asData
              ?.value
              .catalog
              .models
              .where((model) => model.key == key)
              .firstOrNull;
          return model != null &&
              model.origin == AccountModelOrigin.manual &&
              model.canDelete &&
              !model.saving;
        }

        if (!targetCurrent()) return;
        if (await confirmAccountDelete(
              context,
              key.modelId,
              manualModel: true,
            ) &&
            targetCurrent()) {
          await owner.removeManual(key.modelId, expectedToken: compactToken);
        }
      case AccountModelAction.edit:
        AccountEditRoute(
          kind: key.account.kind,
          accountId: key.account.id,
          focusModelId: key.modelId,
        ).go(context);
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
