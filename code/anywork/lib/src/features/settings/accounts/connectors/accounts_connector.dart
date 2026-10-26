import 'dart:async';

import 'package:anywork_client/account_usage.dart';
import 'package:anywork_client/acp.dart';
import 'package:anywork_client/configuration.dart';
import 'package:anywork_client/resources.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../diagnostics/studio_driver_keys.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../../l10n/studio_l10n.dart';
import '../../../../platform/external_url_launcher.dart';
import '../../../../ui/overlays/confirmation_view.dart';
import '../../connectors/settings_failure_text.dart';
import '../../state/settings_action.dart';
import '../../state/settings_navigation_state.dart';
import '../../view_models/collection_values.dart';
import '../../view_models/read_values.dart';
import '../../view_models/settings_navigation_view_model.dart';
import '../state/accounts_state.dart';
import '../state/account_template_choices.dart';
import '../state/acp_command_notice.dart';
import '../view_models/account_editor_view_model.dart';
import '../view_models/accounts_view_model.dart';
import '../views/accounts_view.dart';
import '../widgets/account_template_picker.dart';
import '../widgets/account_usage_panel.dart';
import 'account_editor_connector.dart';
import 'account_model_limits_connector.dart';
import 'acp_account_details_connector.dart';
import 'acp_account_editor_connector.dart';

class AccountsConnector extends ConsumerWidget {
  const AccountsConnector({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) => ref
      .watch(accountsViewModelProvider)
      .when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stack) {
          if (error is! StudioFailure) Error.throwWithStackTrace(error, stack);
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SelectableText(settingsFailureText(error)),
                TextButton(
                  onPressed: () => ref.invalidate(accountsViewModelProvider),
                  child: Text(context.l10n.runtimeFatalRetry),
                ),
              ],
            ),
          );
        },
        data: (state) {
          final vm = ref.read(accountsViewModelProvider.notifier);
          final l10n = context.l10n;
          // Tab 面板在设置页内保持挂载（Offstage），可见性必须来自导航状态：ACP 观察
          // 租约只在页面真正可见时由各自的 VM 取得。
          final visible = ref.watch(
            settingsNavigationViewModelProvider.select(
              (value) =>
                  value.asData?.value.visible == true &&
                  value.asData?.value.tab == SettingsTab.accounts,
            ),
          );
          // 统一“添加账号”入口的 typed 模板目录：Native 在前保持原顺序，ACP 由选择器前置。
          // 两侧来源独立：ACP 目录读取失败不影响 Native 账号的创建入口。
          final choices = accountTemplateChoices(
            native: state.templates?.templates ?? const [],
            acp: state.acpCatalog ?? AcpAccountCatalog.empty,
          );
          if (state.acpEditor case final target?) {
            return Padding(
              padding: const EdgeInsets.all(20),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 820),
                  child: AcpAccountEditorConnector(
                    key: ValueKey(target),
                    target: target,
                    visible: visible,
                    needsPreparation: state.acpNeedsPreparation,
                    onCancel: vm.closeAcpEditor,
                    onOpenUrl: (url) =>
                        unawaited(ref.read(externalUrlLauncherProvider)(url)),
                    onSaved: (accountId, checkFailure, connectionRevision) =>
                        unawaited(
                          _acpSaved(
                            vm,
                            accountId: accountId,
                            checkFailure: checkFailure,
                            connectionRevision: connectionRevision,
                          ),
                        ),
                  ),
                ),
              ),
            );
          }
          if (state.editor case final target?) {
            return Padding(
              padding: const EdgeInsets.all(20),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 980),
                  child: AccountEditorConnector(
                    target: target,
                    onCancel: () {
                      ref
                          .read(accountEditorViewModelProvider(target).notifier)
                          .endEditing();
                      vm.closeEditor(target);
                    },
                    onSaved: () {
                      ref
                          .read(accountEditorViewModelProvider(target).notifier)
                          .endEditing();
                      vm.closeEditor(target, saved: true);
                    },
                  ),
                ),
              ),
            );
          }
          final usages = {
            for (final usage in displayCollectionRows(state.usageSource.usages))
              usage.accountId: usage,
          };
          final catalogs = {
            for (final account in displayCollectionRows(
              state.modelSource.accounts,
            ))
              account.accountId: account,
          };
          final allAccounts = displayCollectionRows(state.source.accounts);
          final collection = state.source.accounts;
          final canDelete =
              collection is CurrentCollectionMirror<AccountConfiguration> &&
              collection.window.reference.total > 1;
          final acpEntries = [
            for (final id in state.matchingAcpAccountIds)
              ...?state.directory?.acpEntries.where(
                (entry) => entry.account.accountId == id,
              ),
          ];
          final errors = <String>[
            if (state.editorError case final error?) settingsFailureText(error),
            for (final error in state.readIssues.values)
              settingsFailureText(error),
            if (state.source.projection.sync.error case final error?)
              settingsFailureText(error),
            if (state.modelSource.projection.sync.error case final error?)
              settingsFailureText(error),
            if (state.usageSource.projection.sync.error case final error?)
              settingsFailureText(error),
            for (final entry in state.usageActions.entries)
              if (!state.usageActionIds.containsKey(entry.key))
                ..._errors(entry.value),
          ];
          final list = AccountsView(
            state: state,
            accounts: [
              for (final id in state.matchingAccountIds)
                ...allAccounts.where((account) => account.accountId == id),
            ],
            acpEntries: acpEntries,
            acpNoticeSummaries: _noticeSummaries(l10n, state, acpEntries),
            selectedAcpAccountId: state.selectedAcpAccountId,
            onSelectAcp: (entry) => vm.selectAcp(entry.account.accountId),
            onEditAcp: (entry) => _editAcp(context, vm, entry),
            onRemoveAcp: (entry) =>
                unawaited(vm.removeAcp(entry.account.accountId)),
            catalogs: catalogs,
            usages: usages,
            defaultAccountId: displayReadValue<String?, ConfigurationReadRef>(
              state.source.defaultAccountId,
            ),
            canDelete: canDelete,
            hasMore:
                !collectionComplete(
                  state.source.accounts,
                  state.source.projection.stamp?.origin,
                ) ||
                !collectionComplete(
                  state.modelSource.accounts,
                  state.modelSource.projection.stamp?.origin,
                ) ||
                !collectionComplete(
                  state.usageSource.usages,
                  state.usageSource.projection.stamp?.origin,
                ),
            errors: errors,
            actionErrors: {
              for (final account in allAccounts)
                account.accountId: [
                  ..._usageErrors(state, account.accountId),
                  for (final action in AccountRowAction.values)
                    ..._errors(state.rowActions[(account.accountId, action)]),
                ],
            },
            onQuery: vm.setQuery,
            onAdd: () => unawaited(_add(context, vm, choices)),
            onSelect: vm.select,
            onEdit: vm.startEdit,
            onDefault: (id) => unawaited(vm.setDefault(id)),
            onDelete: (id) => unawaited(vm.remove(id)),
            onRefreshAll: () => unawaited(vm.refreshUsage()),
            onRefresh: (id) => unawaited(vm.refreshUsage(id)),
            onMore: () => unawaited(vm.loadMore()),
            onRetry: vm.retryRead,
          );
          final acpSelected = state.showDetails
              ? state.directory?.acpEntries
                    .where(
                      (entry) =>
                          entry.account.accountId == state.selectedAcpAccountId,
                    )
                    .firstOrNull
              : null;
          final details = switch (acpSelected) {
            final entry? => AcpAccountDetailsConnector(
              account: entry.account,
              template: entry.template,
              visible: visible,
              onBack: vm.showList,
              onEdit: () => _editAcp(context, vm, entry),
              onRemove: () => vm.removeAcp(entry.account.accountId),
            ),
            null => _nativeDetails(
              context,
              state,
              vm,
              state.showDetails ? state.selectedAccountId : null,
              allAccounts,
              usages,
            ),
          };
          final id = state.selectedAccountId;
          // One-screen master/detail on wide windows; list and details become
          // separate pages below the split breakpoint.
          if (acpSelected == null && (!state.showDetails || id == null)) {
            return Padding(padding: const EdgeInsets.all(24), child: list);
          }
          return LayoutBuilder(
            builder: (context, constraints) {
              final split = constraints.maxWidth >= 1100;
              return Padding(
                padding: const EdgeInsets.all(24),
                child: split
                    ? Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          SizedBox(width: 360, child: list),
                          const SizedBox(width: 24),
                          const VerticalDivider(width: 1),
                          const SizedBox(width: 24),
                          Expanded(child: details),
                        ],
                      )
                    : details,
              );
            },
          );
        },
      );

  /// Native 账号详情（含模型额度子连接器）。
  Widget _nativeDetails(
    BuildContext context,
    AccountsViewState state,
    AccountsViewModel vm,
    String? id,
    List<AccountConfiguration> allAccounts,
    Map<String, AccountUsageRecord> usages,
  ) {
    if (id == null) return const SizedBox.shrink();
    return AccountModelLimitsConnector(
      accountId: id,
      iconKey: state.templates?.templates
          .where(
            (item) =>
                item.id ==
                allAccounts
                    .where((account) => account.accountId == id)
                    .firstOrNull
                    ?.templateId,
          )
          .firstOrNull
          ?.iconKey,
      onBack: vm.showList,
      onEdit: () => vm.startEdit(id),
      onRemoveModel: (modelId) =>
          unawaited(_removeModel(context, vm, id, modelId)),
      modelErrors: {
        for (final entry in state.modelActions.entries)
          if (entry.key.$1 == id) entry.key.$2: _errors(entry.value),
      },
      usage: AccountUsagePanel(
        usage: usages[id],
        loading: state.usageChecks[id]?.operation.isPending ?? false,
        preparing: state.usageChecks[id]?.preparing ?? false,
        errors: _usageErrors(state, id),
        onRefresh: () => unawaited(vm.refreshUsage(id)),
      ),
    );
  }

  /// 显示在目标行/目标详情的命令失败摘要（账号 + 连接身份 + 意图类别）。
  String? _noticeFor(
    AppLocalizations l10n,
    AccountsViewState state,
    AcpAccountEntryView entry,
  ) {
    final notice = visibleAcpCommandNotice(
      notice: state.acpNotices[entry.account.accountId],
      accountId: entry.account.accountId,
      connectionRevision: entry.account.connectionRevision,
      auth: entry.auth,
    );
    if (notice == null) return null;
    return acpCommandNoticeSummary(l10n, notice);
  }

  /// 逐行可见通知：只保留仍绑定该目标接入与当前在途操作的条目。
  Map<String, String> _noticeSummaries(
    AppLocalizations l10n,
    AccountsViewState state,
    List<AcpAccountEntryView> entries,
  ) {
    final summaries = <String, String>{};
    for (final entry in entries) {
      final summary = _noticeFor(l10n, state, entry);
      if (summary != null) summaries[entry.account.accountId] = summary;
    }
    return summaries;
  }

  Future<void> _add(
    BuildContext context,
    AccountsViewModel vm,
    List<AccountTemplateChoice> choices,
  ) async {
    if (choices.isEmpty) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(content: Text(context.l10n.settingsAccountCatalogUnavailable)),
      );
      return;
    }
    final choice = await showAccountTemplatePicker(context, templates: choices);
    if (choice == null || !context.mounted) return;
    await vm.startCreate(choice);
  }

  /// 编辑已保存接入：模板必须来自后端目录，缺失时报“模板不可用”，不合成发行事实。
  void _editAcp(
    BuildContext context,
    AccountsViewModel vm,
    AcpAccountEntryView entry,
  ) {
    if (vm.startAcpEdit(entry.account) == null) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(
          content: Text(context.l10n.settingsAccountTemplateUnavailable),
        ),
      );
    }
  }

  /// 保存成功后的收束：刷新 canonical 目录，绑定“账号已保存，连接未完成”的通知，再离开表单。
  ///
  /// 保存事实已成立：即使连接失败也不回滚、不重发保存，草稿只在保存失败时保留。
  Future<void> _acpSaved(
    AccountsViewModel vm, {
    required String accountId,
    required StudioFailure? checkFailure,
    required int connectionRevision,
  }) async {
    final account = await vm.refreshAcpAccounts(accountId);
    if (checkFailure case final failure?) {
      vm.setAcpNotice(
        accountId,
        AcpCommandNotice(
          kind: AcpCommandNoticeKind.authentication,
          accountId: accountId,
          // 只绑定保存编排解析到的连接代次；解析不到时不伪造身份。
          connectionRevision: connectionRevision > 0
              ? connectionRevision
              : (account?.connectionRevision ?? -1),
          failure: failure,
          // “账号已保存，连接未完成”：摘要使用专门的完成度文案。
          connectIncomplete: true,
        ),
      );
    } else {
      vm.clearAcpNotice(accountId);
    }
    vm.closeAcpEditor(savedAccountId: accountId);
  }

  List<String> _errors(SettingsAction? action) => [
    if (action?.error case final error?) settingsFailureText(error),
    if (action?.observationError case final error?) settingsFailureText(error),
    if (action?.operation?.evidenceError case final error?)
      settingsFailureText(error),
  ];

  List<String> _usageErrors(AccountsViewState state, String id) {
    final check = state.usageChecks[id];
    return {
      if (check?.operation.error case final error?) settingsFailureText(error),
      if (check?.operation.evidenceError case final error?)
        settingsFailureText(error),
      if (check?.observationError case final error?) settingsFailureText(error),
      if (check != null && state.usageActionIds[id] == check.operation.id)
        ..._errors(state.usageActions[id]),
    }.toList();
  }

  Future<void> _removeModel(
    BuildContext context,
    AccountsViewModel vm,
    String accountId,
    String modelId,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => ConfirmationView(
        title: context.l10n.settingsRemoveManualModelConfirmTitle,
        body: context.l10n.settingsRemoveManualModelConfirmBody,
        confirmLabel: context.l10n.settingsRemoveManualModelConfirmAction,
        cancelLabel: context.l10n.settingsCancel,
        destructive: true,
        confirmKey: StudioDriverKeys.accountManualModelDeleteConfirm,
        onConfirm: () => Navigator.pop(context, true),
        onCancel: () => Navigator.pop(context, false),
      ),
    );
    if (confirmed == true && context.mounted) {
      await vm.removeModel(accountId, modelId);
    }
  }
}
