import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../l10n/app_localizations.dart';
import '../../../../app/routing/app_route.dart';
import '../state/account_presentations.dart';
import '../view_models/accounts_view_model.dart';
import '../views/accounts_list_view.dart';
import 'account_actions.dart';
import 'account_strings.dart';

class AccountsConnector extends ConsumerStatefulWidget {
  const AccountsConnector({required this.visible, super.key});
  final bool visible;
  @override
  ConsumerState<AccountsConnector> createState() => _AccountsConnectorState();
}

class _AccountsConnectorState extends ConsumerState<AccountsConnector> {
  final _listScroll = ScrollController();
  String? _locale;
  @override
  void initState() {
    super.initState();
    scheduleMicrotask(() {
      if (mounted) {
        ref.read(accountsViewModelProvider.notifier).setVisible(widget.visible);
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final l10n = AppLocalizations.of(context);
    if (_locale == l10n.localeName) return;
    _locale = l10n.localeName;
    scheduleMicrotask(() {
      if (mounted) {
        ref
            .read(accountsViewModelProvider.notifier)
            .setStrings(accountStrings(l10n));
      }
    });
  }

  @override
  void didUpdateWidget(covariant AccountsConnector oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.visible != widget.visible) {
      scheduleMicrotask(() {
        if (mounted) {
          ref
              .read(accountsViewModelProvider.notifier)
              .setVisible(widget.visible);
        }
      });
    }
  }

  @override
  void dispose() {
    _listScroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ref
      .watch(accountsViewModelProvider)
      .when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => Center(
          child: Text(AppLocalizations.of(context).accountsQueryFailed),
        ),
        data: (value) {
          final owner = ref.read(accountsViewModelProvider.notifier);
          return AccountsListView(
            value: value.list,
            scrollController: _listScroll,
            onSearchChanged: owner.search,
            onAdd: () => const AccountCreateRoute().go(context),
            onRefreshAll: owner.refreshAll,
            onRetry: owner.retryObservation,
            onOpen: (key) => AccountDetailsRoute(
              kind: key.kind,
              accountId: key.id,
            ).go(context),
            onRowAction: (key, action) {
              switch (action) {
                case AccountRowAction.refresh:
                  unawaited(owner.refresh(key));
                case AccountRowAction.setDefault:
                  unawaited(owner.setDefault(key));
                case AccountRowAction.edit:
                  AccountEditRoute(
                    kind: key.kind,
                    accountId: key.id,
                  ).go(context);
                case AccountRowAction.delete:
                  unawaited(deleteAccount(context, ref, key));
              }
            },
          );
        },
      );
}
