import 'dart:async';

import 'package:anywork_client/configuration.dart';
import 'package:anywork_client/resources.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../diagnostics/studio_driver_keys.dart';
import '../../../../l10n/studio_l10n.dart';
import '../../../../ui/overlays/confirmation_view.dart';
import '../../connectors/settings_failure_text.dart';
import '../../state/settings_action.dart';
import '../../view_models/collection_values.dart';
import '../../view_models/read_values.dart';
import '../state/accounts_state.dart';
import '../view_models/accounts_view_model.dart';
import '../view_models/account_editor_view_model.dart';
import '../views/accounts_view.dart';
import '../widgets/account_usage_panel.dart';
import 'account_editor_connector.dart';
import 'account_model_limits_connector.dart';

class AccountsConnector extends ConsumerWidget {
  const AccountsConnector({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) => ref.watch(accountsViewModelProvider).when(
    loading: () => const Center(child: CircularProgressIndicator()),
    error: (error, stack) {
      if (error is! StudioFailure) Error.throwWithStackTrace(error, stack);
      return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
        SelectableText(settingsFailureText(error)),
        TextButton(onPressed: () => ref.invalidate(accountsViewModelProvider), child: Text(context.l10n.runtimeFatalRetry)),
      ]));
    },
    data: (state) {
      final vm = ref.read(accountsViewModelProvider.notifier);
      if (state.editor case final target?) return Center(child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 980),
        child: AccountEditorConnector(target: target,
          onCancel: () {
            ref.read(accountEditorViewModelProvider(target).notifier).endEditing();
            vm.closeEditor(target);
          },
          onSaved: () {
            ref.read(accountEditorViewModelProvider(target).notifier).endEditing();
            vm.closeEditor(target, saved: true);
          })));
      final usages = {for (final usage in displayCollectionRows(state.usageSource.usages)) usage.accountId: usage};
      final catalogs = {for (final account in displayCollectionRows(state.modelSource.accounts)) account.accountId: account};
      final allAccounts = displayCollectionRows(state.source.accounts);
      final collection = state.source.accounts;
      final canDelete = collection is CurrentCollectionMirror<AccountConfiguration> && collection.window.reference.total > 1;
      final errors = <String>[
        if (state.editorError case final error?) settingsFailureText(error),
        for (final error in state.readIssues.values) settingsFailureText(error),
        if (state.source.projection.sync.error case final error?) settingsFailureText(error),
        if (state.modelSource.projection.sync.error case final error?) settingsFailureText(error),
        if (state.usageSource.projection.sync.error case final error?) settingsFailureText(error),
        for (final entry in state.usageActions.entries)
          if (!state.usageActionIds.containsKey(entry.key)) ..._errors(entry.value),
      ];
      final list = AccountsView(state: state,
        accounts: [for (final id in state.matchingAccountIds) ...allAccounts.where((account) => account.accountId == id)],
        catalogs: catalogs, usages: usages, defaultAccountId: displayReadValue(state.source.defaultAccountId),
        canDelete: canDelete,
        hasMore: !collectionComplete(state.source.accounts, state.source.projection.stamp?.origin) ||
          !collectionComplete(state.modelSource.accounts, state.modelSource.projection.stamp?.origin) ||
          !collectionComplete(state.usageSource.usages, state.usageSource.projection.stamp?.origin),
        errors: errors, actionErrors: {for (final account in allAccounts) account.accountId: [
          ..._usageErrors(state, account.accountId),
          for (final action in AccountRowAction.values) ..._errors(state.rowActions[(account.accountId, action)]),
        ]},
        onQuery: vm.setQuery, onAdd: () => unawaited(vm.startCreate()), onSelect: vm.select,
        onEdit: vm.startEdit, onDefault: (id) => unawaited(vm.setDefault(id)),
        onDelete: (id) => unawaited(vm.remove(id)), onRefreshAll: () => unawaited(vm.refreshUsage()),
        onRefresh: (id) => unawaited(vm.refreshUsage(id)), onMore: () => unawaited(vm.loadMore()), onRetry: vm.retryRead);
      final id = state.selectedAccountId;
      if (!state.showDetails || id == null) return list;
      final details = AccountModelLimitsConnector(accountId: id,
        onBack: vm.showList, onEdit: () => vm.startEdit(id),
        onRemoveModel: (modelId) => unawaited(_removeModel(context, vm, id, modelId)),
        modelErrors: {for (final entry in state.modelActions.entries)
          if (entry.key.$1 == id) entry.key.$2: _errors(entry.value)},
        usage: AccountUsagePanel(usage: usages[id], loading: state.usageChecks[id]?.operation.isPending ?? false,
          preparing: state.usageChecks[id]?.preparing ?? false,
          errors: _usageErrors(state, id), onRefresh: () => unawaited(vm.refreshUsage(id))));
      return LayoutBuilder(builder: (context, constraints) => constraints.maxWidth >= 1100
        ? Row(children: [SizedBox(width: 400, child: list), const VerticalDivider(width: 1),
          Expanded(child: Padding(padding: const EdgeInsets.all(24), child: details))])
        : Padding(padding: const EdgeInsets.all(24), child: details));
    },
  );

  List<String> _errors(SettingsAction? action) => [
    if (action?.error case final error?) settingsFailureText(error),
    if (action?.observationError case final error?) settingsFailureText(error),
    if (action?.operation?.evidenceError case final error?) settingsFailureText(error),
  ];

  List<String> _usageErrors(AccountsViewState state, String id) {
    final check = state.usageChecks[id];
    return [
      if (check?.operation.error case final error?) settingsFailureText(error),
      if (check?.operation.evidenceError case final error?) settingsFailureText(error),
      if (check?.observationError case final error?) settingsFailureText(error),
      if (check != null && state.usageActionIds[id] == check.operation.id) ..._errors(state.usageActions[id]),
    ].toSet().toList();
  }

  Future<void> _removeModel(BuildContext context, AccountsViewModel vm, String accountId, String modelId) async {
    final confirmed = await showDialog<bool>(context: context, builder: (context) => ConfirmationView(
      title: context.l10n.settingsRemoveManualModelConfirmTitle,
      body: context.l10n.settingsRemoveManualModelConfirmBody,
      confirmLabel: context.l10n.settingsRemoveManualModelConfirmAction, cancelLabel: context.l10n.settingsCancel,
      destructive: true, confirmKey: StudioDriverKeys.accountManualModelDeleteConfirm,
      onConfirm: () => Navigator.pop(context, true), onCancel: () => Navigator.pop(context, false)));
    if (confirmed == true && context.mounted) await vm.removeModel(accountId, modelId);
  }
}
