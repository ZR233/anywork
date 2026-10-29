import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../l10n/app_localizations.dart';
import '../../../../app/routing/app_route.dart';
import '../state/account_presentations.dart';
import '../state/account_view_state.dart';
import '../view_models/account_details_view_model.dart';
import '../view_models/account_models_view_model.dart';
import '../view_models/accounts_view_model.dart';
import '../view_models/acp_account_view_model.dart';
import '../views/account_details_view.dart';
import 'account_actions.dart';
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
  void Function()? _releaseModels;

  @override
  void initState() {
    super.initState();
    _retainModels();
  }

  void _retainModels() {
    if (widget.account.kind == AccountKind.native) {
      _releaseModels = ref
          .read(accountModelsViewModelProvider(widget.account).notifier)
          .retainAccountScope();
    }
  }

  @override
  void didUpdateWidget(covariant AccountDetailsConnector oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.account != widget.account) {
      _releaseModels?.call();
      _releaseModels = null;
      _locale = null;
      _localizedAcp = null;
      _retainModels();
      _localize();
    }
  }

  @override
  void dispose() {
    _releaseModels?.call();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _localize();
  }

  void _localize() {
    final l10n = AppLocalizations.of(context);
    if (_locale == l10n.localeName) return;
    _locale = l10n.localeName;
    _localizedAcp = null;
    final account = widget.account;
    scheduleMicrotask(() {
      if (!mounted || widget.account != account) return;
      final strings = accountStrings(l10n);
      ref
          .read(accountDetailsViewModelProvider(account).notifier)
          .setStrings(strings);
      if (widget.account.kind == AccountKind.native) {
        ref
            .read(accountModelsViewModelProvider(account).notifier)
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
        if (mounted && _localizedAcp == acpKey) {
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
        final accounts = ref.read(accountsViewModelProvider.notifier);
        final value = owner.presentation(
          catalog: models?.catalog,
          acp: acp?.panel,
        );
        final modelsProvider = widget.account.kind == AccountKind.native
            ? accountModelsViewModelProvider(widget.account)
            : null;
        final modelsOwner = modelsProvider != null && ref.exists(modelsProvider)
            ? ref.read(modelsProvider.notifier)
            : null;
        final canRemoveModels =
            modelsProvider == null ||
            (models != null &&
                modelsOwner != null &&
                modelsOwner.canRemove(
                  expectedToken: modelsOwner.compactLeaveToken(),
                ));
        return AccountDetailsView(
          value: value.copyWith(
            canDelete:
                value.canDelete &&
                canRemoveModels &&
                !accounts.isRemovalBlocked(widget.account),
          ),
          onBack: () => const SettingsRoute().go(context),
          onEdit: () => AccountEditRoute(
            kind: widget.account.kind,
            accountId: widget.account.id,
          ).go(context),
          onDelete: () => deleteAccount(context, ref, widget.account),
          onSetDefault: () => accounts.setDefault(widget.account),
          onRefreshUsage: owner.refreshUsage,
          onBillingChanged: owner.setBilling,
          onResetBilling: () => owner.setBilling(null),
          onSyncModels: () => ref
              .read(accountModelsViewModelProvider(widget.account).notifier)
              .sync(),
          onAddModel: () => AccountEditRoute(
            kind: widget.account.kind,
            accountId: widget.account.id,
            addModel: true,
          ).go(context),
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
