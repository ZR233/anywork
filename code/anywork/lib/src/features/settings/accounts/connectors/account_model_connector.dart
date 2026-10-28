import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/routing/app_route.dart';
import '../../../../l10n/app_localizations.dart';
import '../state/account_presentations.dart';
import '../view_models/account_details_view_model.dart';
import '../view_models/account_models_view_model.dart';
import '../views/account_model_details_view.dart';
import 'account_strings.dart';

class AccountModelConnector extends ConsumerStatefulWidget {
  const AccountModelConnector({
    required this.model,
    this.tab = AccountModelTab.specifications,
    super.key,
  });
  final AccountModelKey model;
  final AccountModelTab tab;

  @override
  ConsumerState<AccountModelConnector> createState() =>
      _AccountModelConnectorState();
}

class _AccountModelConnectorState extends ConsumerState<AccountModelConnector> {
  String? _locale;
  bool _requested = false;

  @override
  void didUpdateWidget(covariant AccountModelConnector oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.model != widget.model) {
      _requested = false;
      _locale = null;
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final l10n = AppLocalizations.of(context);
    if (_locale == l10n.localeName ||
        widget.model.account.kind != AccountKind.native) {
      return;
    }
    _locale = l10n.localeName;
    final key = widget.model;
    final strings = accountStrings(l10n);
    scheduleMicrotask(() {
      if (mounted && widget.model == key) {
        ref
            .read(accountModelsViewModelProvider(key.account).notifier)
            .setStrings(strings);
      }
    });
  }

  void _back() => AccountDetailsRoute(
    kind: widget.model.account.kind,
    accountId: widget.model.account.id,
  ).go(context);

  Widget _missing(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(AppLocalizations.of(context).accountsTargetMissing),
        TextButton(
          onPressed: _back,
          child: Text(AppLocalizations.of(context).accountsBack),
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final key = widget.model;
    // An ACP account has no Native catalog. A known but inapplicable target is
    // visible domain absence, not a route fallback or a fabricated model owner.
    if (key.account.kind != AccountKind.native) return _missing(context);
    final state = ref.watch(accountModelsViewModelProvider(key.account));
    final account = ref
        .watch(accountDetailsViewModelProvider(key.account))
        .asData
        ?.value
        .details;
    return state.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (_, _) =>
          Center(child: Text(AppLocalizations.of(context).accountsQueryFailed)),
      data: (value) {
        final model = value.catalog.models
            .where((model) => model.key == key)
            .firstOrNull;
        if (model == null) {
          if (value.catalog.syncing) {
            return const Center(child: CircularProgressIndicator());
          }
          return _missing(context);
        }
        final owner = ref.read(
          accountModelsViewModelProvider(key.account).notifier,
        );
        if (!_requested && model.canLoadReadout) {
          _requested = true;
          scheduleMicrotask(() {
            if (mounted &&
                widget.model == key &&
                ref.exists(accountModelsViewModelProvider(key.account)) &&
                identical(
                  ref.read(
                    accountModelsViewModelProvider(key.account).notifier,
                  ),
                  owner,
                )) {
              unawaited(owner.loadReadout(key.modelId));
            }
          });
        }
        return AccountModelDetailsView(
          key: ValueKey(key),
          value: model,
          accountName: account?.name ?? key.account.id,
          iconKey: account?.iconKey,
          tab: widget.tab,
          onTabChanged: (tab) => AccountModelRoute(
            kind: key.account.kind,
            accountId: key.account.id,
            modelId: key.modelId,
            tab: tab,
          ).replace(context),
          onBack: _back,
          onRetry: () => owner.loadReadout(key.modelId),
          onEnabledChanged: (enabled) => owner.setEnabled(key.modelId, enabled),
          onFilterChanged: (filter) =>
              owner.filterEvaluations(key.modelId, filter),
        );
      },
    );
  }
}
