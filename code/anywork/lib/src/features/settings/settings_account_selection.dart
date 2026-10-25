import 'dart:async';

import 'package:anywork_client/studio_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/studio_l10n.dart';
import '../../presentation/providers/client_provider.dart';
import '../../presentation/providers/settings_store.dart';
import '../../shared/delegation_labels.dart';
import '../../shared/model_route_selector.dart';
import '../../shared/studio_driver_keys.dart';
import 'settings_common.dart';
import 'settings_model_details.dart';
import 'settings_views.dart';

/// Projects the canonical category, never the connection editor's stale snapshot.
class AccountNoChargeControl extends ConsumerWidget {
  const AccountNoChargeControl({
    super.key,
    required this.accountId,
    this.enabled = true,
  });
  final String accountId;
  final bool enabled;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final account = ref
        .watch(settingsAccountsViewProvider)
        .accounts
        .where((account) => account.id == accountId)
        .firstOrNull;
    if (account == null) return const SizedBox.shrink();
    final command = ref
        .watch(settingsStoreProvider)
        .commands['account-billing-kind:$accountId'];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SwitchListTile(
          key: StudioDriverKeys.accountNoCharge,
          title: Text(context.l10n.settingsNoCharge),
          subtitle: Text(context.l10n.settingsNoChargeHelp),
          value: account.billingKind == BillingKind.noCharge,
          onChanged: !enabled || command?.isPending == true
              ? null
              : (noCharge) => unawaited(
                  ref
                      .read(anyworkClientProvider)
                      .settingsCommands
                      .setAccountBillingKind(
                        accountId,
                        noCharge ? BillingKind.noCharge : null,
                      )
                      .then<void>((_) {}, onError: (Object _, StackTrace _) {}),
                ),
        ),
        if (command?.isPending == true) Text(context.l10n.settingsModelSaving),
        if (command?.error case final failure?)
          SettingsInlineError(message: failure.message),
      ],
    );
  }
}

class AccountModelSelectionControl extends ConsumerWidget {
  const AccountModelSelectionControl({
    super.key,
    required this.accountId,
    required this.model,
  });
  final String accountId;
  final AccountModelView model;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final command = ref
        .watch(settingsStoreProvider)
        .commands[accountModelEnabledMutationKey(accountId, model.modelId)];
    final pending = command?.isPending == true;
    final error = command?.error;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SwitchListTile(
          key: StudioDriverKeys.modelEnabled(accountId, model.modelId),
          contentPadding: const EdgeInsets.symmetric(horizontal: 12),
          title: Text(
            context.l10n.settingsModelEnabled,
            semanticsLabel:
                '${context.l10n.settingsModelEnabled} · ${model.displayName} · $accountId / ${model.modelId}',
          ),
          subtitle: Text(
            pending
                ? context.l10n.settingsModelSaving
                : context.l10n.settingsModelEnabledHint,
          ),
          value: pending
              ? command!.target.enabled ?? model.enabled
              : model.enabled,
          onChanged: (enabled) => unawaited(
            ref
                .read(anyworkClientProvider)
                .settingsCommands
                .setAccountModelEnabled(accountId, model.modelId, enabled)
                .then<void>((_) {}, onError: (Object _, StackTrace _) {}),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (!model.enabled) Text(context.l10n.settingsModelDisabled),
              if (modelTextFilterMessage(context, model) case final reason?)
                Text(reason),
              if (error != null) ...[
                SettingsInlineError(message: error.message),
                Text(context.l10n.settingsModelSaveFailed),
              ],
              TextButton.icon(
                key: StudioDriverKeys.modelDetails(accountId, model.modelId),
                icon: const Icon(Icons.info_outline),
                label: Text(context.l10n.settingsModelDetails),
                onPressed: () => showModelDetails(
                  context,
                  DelegationModelKey(
                    accountId: accountId,
                    modelId: model.modelId,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class AccountBillingControl extends ConsumerWidget {
  const AccountBillingControl({super.key, required this.account});
  final AccountSettingsView account;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final command = ref
        .watch(settingsStoreProvider)
        .commands['account-billing-kind:${account.id}'];
    final width = (MediaQuery.sizeOf(context).width - 48).clamp(0.0, 480.0);
    return SettingsSectionPanel(
      title: context.l10n.settingsBillingKind,
      children: [
        SettingsReadout(
          label: context.l10n.settingsBillingEffective,
          value: context.billingKindLabel(account.billingKind),
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
                onPressed: () => unawaited(
                  ref
                      .read(anyworkClientProvider)
                      .settingsCommands
                      .setAccountBillingKind(account.id, kind)
                      .then<void>((_) {}, onError: (Object _, StackTrace _) {}),
                ),
                child: Text(context.billingKindLabel(kind)),
              ),
          ],
          builder: (context, controller, child) => TextButton(
            key: StudioDriverKeys.accountBillingKind(account.id),
            onPressed: controller.isOpen ? controller.close : controller.open,
            child: Text(context.billingKindLabel(account.billingKindOverride)),
          ),
        ),
        Text(context.l10n.settingsBillingHint),
        if (command?.isPending == true) Text(context.l10n.settingsModelSaving),
        if (command?.error case final failure?)
          SettingsInlineError(message: failure.message),
      ],
    );
  }
}
