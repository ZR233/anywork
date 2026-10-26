import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../l10n/app_localizations.dart';
import '../state/account_presentations.dart';
import '../state/account_view_state.dart';
import '../view_models/account_editor_view_model.dart';
import '../view_models/account_models_view_model.dart';
import '../view_models/accounts_view_model.dart';
import '../view_models/acp_account_view_model.dart';
import '../views/acp_account_editor_view.dart';
import '../views/native_account_editor_view.dart';
import 'account_actions.dart';
import 'account_navigation.dart';
import 'account_strings.dart';

class AccountEditorConnector extends ConsumerStatefulWidget {
  const AccountEditorConnector({required this.editor, super.key});
  final AccountEditorKey editor;
  @override
  ConsumerState<AccountEditorConnector> createState() =>
      _AccountEditorConnectorState();
}

class _AccountEditorConnectorState
    extends ConsumerState<AccountEditorConnector> {
  String? _locale;
  AccountAcpKey? _localizedAcp;
  @override
  void initState() {
    super.initState();
    scheduleMicrotask(() {
      if (mounted) {
        unawaited(
          ref
              .read(accountEditorViewModelProvider(widget.editor).notifier)
              .loadTemplates(),
        );
      }
    });
  }

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
          .read(accountEditorViewModelProvider(widget.editor).notifier)
          .setStrings(strings);
      if (widget.editor.target.kind == AccountKind.native &&
          !widget.editor.creating) {
        ref
            .read(accountModelsViewModelProvider(widget.editor.target).notifier)
            .setStrings(strings);
      }
    });
  }

  Future<void> _save() async {
    final owner = ref.read(
      accountEditorViewModelProvider(widget.editor).notifier,
    );
    if (!await owner.save() || !mounted) return;
    owner.finish();
    ref
        .read(accountsViewModelProvider.notifier)
        .finishEditor(widget.editor, saved: true);
  }

  @override
  Widget build(BuildContext context) {
    final provider = accountEditorViewModelProvider(widget.editor);
    final state = ref.watch(provider);
    final acpKey = state.asData?.value.acpKey;
    final acp = acpKey == null
        ? null
        : ref.watch(acpAccountViewModelProvider(acpKey)).asData?.value;
    final models =
        widget.editor.target.kind == AccountKind.native &&
            !widget.editor.creating
        ? ref
              .watch(accountModelsViewModelProvider(widget.editor.target))
              .asData
              ?.value
        : null;
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
      data: (state) {
        final owner = ref.read(provider.notifier);
        final value = owner.presentation(
          panel: acp?.panel,
          catalog: models?.catalog,
        );
        if (value.native case final native?) {
          return NativeAccountEditorView(
            value: native,
            onFieldChanged: owner.changeField,
            onTemplateChanged: owner.changeTemplate,
            onBillingChanged: owner.changeBilling,
            onResetBilling: () => owner.changeBilling(null),
            onAddModel: owner.addModel,
            onManualModelFieldChanged: (key, field, raw) =>
                owner.changeModel(key, field: field, raw: raw),
            onManualModelConnectionChanged: (key, connection) =>
                owner.changeModel(key, connection: connection),
            onManualModelWireApiChanged: (key, api) =>
                owner.changeModel(key, api: api),
            onRemoveManualModel: (key) async {
              if (owner.isSavedModel(key) &&
                  !await confirmAccountDelete(
                    context,
                    owner.modelName(key),
                    manualModel: true,
                  )) {
                return;
              }
              if (mounted) await owner.removeModel(key);
            },
            modelActions: accountModelActions(context, ref),
            onSave: _save,
            onCancel: () => confirmLeaveAccountsEditor(context, ref),
          );
        }
        if (value.acp case final account?) {
          return AcpAccountEditorView(
            value: account,
            onNameChanged: owner.changeName,
            onAction: (action) {
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
            onSave: _save,
            onCancel: () => confirmLeaveAccountsEditor(context, ref),
          );
        }
        return Center(
          child: state.error == null
              ? const CircularProgressIndicator()
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(state.error!),
                    TextButton(
                      onPressed: owner.retryObservation,
                      child: Text(AppLocalizations.of(context).accountsRetry),
                    ),
                    TextButton(
                      onPressed: () => confirmLeaveAccountsEditor(context, ref),
                      child: Text(AppLocalizations.of(context).commonCancel),
                    ),
                  ],
                ),
        );
      },
    );
  }
}
