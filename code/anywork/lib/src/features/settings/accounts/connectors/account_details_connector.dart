import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../l10n/app_localizations.dart';
import '../state/account_presentations.dart';
import '../state/account_view_state.dart';
import '../view_models/account_details_view_model.dart';
import '../view_models/account_models_view_model.dart';
import '../view_models/accounts_view_model.dart';
import '../view_models/acp_account_view_model.dart';
import '../views/account_details_view.dart';
import 'account_actions.dart';
import 'account_navigation.dart';
import 'account_strings.dart';

class AccountDetailsConnector extends ConsumerStatefulWidget {
  const AccountDetailsConnector({required this.account, super.key});
  final AccountDisplayKey account;
  @override
  ConsumerState<AccountDetailsConnector> createState() =>
      _AccountDetailsConnectorState();
}

class _AccountDetailsConnectorState
    extends ConsumerState<AccountDetailsConnector> {
  String? _locale;
  AccountAcpKey? _localizedAcp;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final l10n = AppLocalizations.of(context);
    if (_locale == l10n.localeName) return;
    _locale = l10n.localeName;
    _localizedAcp = null;
    scheduleMicrotask(() {
      if (!mounted) return;
      final strings = accountStrings(l10n);
      ref
          .read(accountDetailsViewModelProvider(widget.account).notifier)
          .setStrings(strings);
      if (widget.account.kind == AccountKind.native) {
        ref
            .read(accountModelsViewModelProvider(widget.account).notifier)
            .setStrings(strings);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final provider = accountDetailsViewModelProvider(widget.account);
    final state = ref.watch(provider);
    final models = widget.account.kind == AccountKind.native
        ? ref
              .watch(accountModelsViewModelProvider(widget.account))
              .asData
              ?.value
        : null;
    final acpKey = state.asData?.value.acpKey;
    final acp = acpKey == null
        ? null
        : ref.watch(acpAccountViewModelProvider(acpKey)).asData?.value;
    if (acpKey != null && _localizedAcp != acpKey) {
      _localizedAcp = acpKey;
      final strings = accountStrings(AppLocalizations.of(context));
      scheduleMicrotask(() {
        if (mounted) {
          ref
              .read(acpAccountViewModelProvider(acpKey).notifier)
              .setStrings(strings);
        }
      });
    }
    return state.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (_, _) =>
          Center(child: Text(AppLocalizations.of(context).accountsQueryFailed)),
      data: (_) {
        final owner = ref.read(provider.notifier);
        final navigation = ref.read(accountsViewModelProvider.notifier);
        return AccountDetailsView(
          value: owner.presentation(catalog: models?.catalog, acp: acp?.panel),
          onBack: () async {
            if (await confirmLeaveAccountsEditor(context) && mounted) {
              navigation.back();
            }
          },
          onEdit: () async {
            if (await confirmLeaveAccountsEditor(context) && mounted) {
              navigation.edit(widget.account);
            }
          },
          onDelete: () => deleteAccount(context, ref, widget.account),
          onSetDefault: () => navigation.setDefault(widget.account),
          onRefreshUsage: owner.refreshUsage,
          onBillingChanged: owner.setBilling,
          onResetBilling: () => owner.setBilling(null),
          onSyncModels: () => ref
              .read(accountModelsViewModelProvider(widget.account).notifier)
              .sync(),
          modelActions: accountModelActions(context, ref),
          onAcpAction: (action) {
            if (acpKey != null) {
              unawaited(performAcpAction(context, ref, acpKey, action));
            }
          },
          onLoginMethodChanged: (id) {
            if (acpKey != null) {
              ref
                  .read(acpAccountViewModelProvider(acpKey).notifier)
                  .selectMethod(id);
            }
          },
          onRetry: owner.retryObservation,
        );
      },
    );
  }
}
