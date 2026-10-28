import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../l10n/app_localizations.dart';
import '../../../../app/routing/app_route.dart';
import '../state/account_presentations.dart';
import '../state/account_view_state.dart';
import '../view_models/account_editor_view_model.dart';
import '../view_models/account_models_view_model.dart';
import '../view_models/account_editor_session_view_model.dart';
import '../view_models/acp_account_view_model.dart';
import '../views/acp_account_editor_view.dart';
import '../views/native_account_editor_view.dart';
import '../widgets/account_template_selector.dart';
import 'account_actions.dart';
import 'account_navigation.dart';
import 'account_strings.dart';

class AccountEditorConnector extends ConsumerStatefulWidget {
  const AccountEditorConnector({
    required this.entry,
    required this.editor,
    super.key,
  });
  final AccountEditorEntryKey entry;
  final AccountEditorKey editor;
  @override
  ConsumerState<AccountEditorConnector> createState() =>
      _AccountEditorConnectorState();
}

class _AccountEditorConnectorState
    extends ConsumerState<AccountEditorConnector> {
  String? _locale;
  AccountAcpKey? _localizedAcp;
  int _selectorRevision = 0;
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

  bool _isCurrent(
    AccountEditorSessionViewModel session,
    AccountEditorKey source,
    AccountEditorViewModel owner,
  ) {
    final sessionProvider = accountEditorSessionViewModelProvider(widget.entry);
    final editorProvider = accountEditorViewModelProvider(source);
    return mounted &&
        widget.editor == source &&
        ref.exists(sessionProvider) &&
        identical(ref.read(sessionProvider.notifier), session) &&
        session.isEditorCurrent(source) &&
        ref.exists(editorProvider) &&
        identical(ref.read(editorProvider.notifier), owner);
  }

  void _cancel() {
    switch (widget.entry) {
      case CreatingAccountEditorEntryKey():
        const SettingsRoute().go(context);
      case EditingAccountEditorEntryKey(:final account):
        AccountDetailsRoute(
          kind: account.kind,
          accountId: account.id,
        ).go(context);
    }
  }

  Future<void> _save() async {
    final source = widget.editor;
    final owner = ref.read(accountEditorViewModelProvider(source).notifier);
    final session = ref.read(
      accountEditorSessionViewModelProvider(widget.entry).notifier,
    );
    final token = owner.leaveToken;
    if (!await owner.save() ||
        !_isCurrent(session, source, owner) ||
        !owner.matchesLeaveToken(token)) {
      return;
    }
    final value = ref
        .read(accountEditorViewModelProvider(source))
        .asData
        ?.value;
    if (value == null ||
        value.dirty ||
        value.saving ||
        owner.hasUnconfirmedSave) {
      return;
    }
    if (!mounted) return;
    AccountDetailsRoute(
      kind: source.target.kind,
      accountId: source.target.id,
    ).go(context);
  }

  Future<void> _switchTemplate(AccountTemplateKey template) async {
    final source = widget.editor;
    if (template == source.template) return;
    final container = ProviderScope.containerOf(context, listen: false);
    final sessionProvider = accountEditorSessionViewModelProvider(widget.entry);
    final session = container.read(sessionProvider.notifier);
    final modelsProvider = source.target.kind == AccountKind.native
        ? accountModelsViewModelProvider(source.target)
        : null;
    final models = modelsProvider != null && container.exists(modelsProvider)
        ? container.read(modelsProvider.notifier)
        : null;
    final compactToken = models?.compactLeaveToken;
    final replacement = session.beginTemplateReplacement(source);
    if (replacement == null) return;
    final choice = await confirmAccountTemplateReplacement(
      context,
      widget.entry,
      source: source,
      replacement: replacement,
    );
    if (choice == null) {
      session.cancelTemplateReplacement(replacement);
      if (mounted) setState(() => _selectorRevision++);
      return;
    }
    if (!container.exists(sessionProvider) ||
        !identical(container.read(sessionProvider.notifier), session) ||
        !session.isTemplateReplacementCurrent(source, replacement)) {
      return;
    }
    if (models != null &&
        (!container.exists(modelsProvider!) ||
            !identical(container.read(modelsProvider.notifier), models) ||
            !models.matchesCompactLeaveToken(compactToken!) ||
            models.compactLeaveBlocked)) {
      return;
    }
    final next = session.replaceTemplate(
      source: source,
      template: template,
      token: replacement,
    );
    if (next == null) return;
    if (choice == AccountLeaveChoice.discard && models != null) {
      models.discardCompactDrafts(compactToken!);
    }
    if (next.target.kind != AccountKind.acp) return;
    final editorProvider = accountEditorViewModelProvider(next);
    await container.read(editorProvider.future);
    if (container.exists(sessionProvider) &&
        identical(container.read(sessionProvider.notifier), session) &&
        session.isEditorCurrent(next) &&
        container.exists(editorProvider)) {
      await container.read(editorProvider.notifier).prepareSelectedTemplate();
    }
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
        final session = ref
            .watch(accountEditorSessionViewModelProvider(widget.entry))
            .asData
            ?.value;
        final selector = widget.editor.creating
            ? AccountTemplateSelector(
                key: ValueKey((widget.editor.editorId, _selectorRevision)),
                templates: session?.templates ?? const [],
                selected: widget.editor.template,
                enabled: !value.saving,
                onSelected: _switchTemplate,
              )
            : null;
        if (value.native case final native?) {
          final entry = widget.editor;
          if (entry.addModel && owner.addModelEntryEditorKey == null) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted ||
                  widget.editor != entry ||
                  !identical(ref.read(provider.notifier), owner)) {
                return;
              }
              owner.consumeAddModelEntry();
            });
          }
          final focusEditorKey = entry.addModel
              ? owner.addModelEntryEditorKey
              : native.manualModels
                    .where((model) => model.id.raw == entry.focusModelId)
                    .firstOrNull
                    ?.editorKey;
          return NativeAccountEditorView(
            value: native,
            templateSelector: selector,
            focusManualModelEditorKey:
                native.manualModels.any(
                  (model) => model.editorKey == focusEditorKey,
                )
                ? focusEditorKey
                : null,
            focusManualModelId: entry.addModel,
            onFieldChanged: owner.changeField,
            onTemplateChanged: _switchTemplate,
            onBillingChanged: owner.changeBilling,
            onResetBilling: () => owner.changeBilling(null),
            onSetDefaultOnCreateChanged:
                native.showSetDefaultOnCreate &&
                    !value.saving &&
                    !owner.hasUnconfirmedSave
                ? owner.changeSetDefaultOnCreate
                : null,
            onAddModel: owner.addModel,
            onManualModelFieldChanged: (key, field, raw) =>
                owner.changeModel(key, field: field, raw: raw),
            onManualModelConnectionChanged: (key, connection) =>
                owner.changeModel(key, connection: connection),
            onManualModelWireApiChanged: (key, api) =>
                owner.changeModel(key, api: api),
            onRemoveManualModel: (key) async {
              final source = widget.editor;
              final session = ref.read(
                accountEditorSessionViewModelProvider(widget.entry).notifier,
              );
              if (owner.isSavedModel(key) &&
                  !await confirmAccountDelete(
                    context,
                    owner.modelName(key),
                    manualModel: true,
                  )) {
                return;
              }
              if (_isCurrent(session, source, owner)) {
                await owner.removeModel(key);
              }
            },
            modelActions: accountModelActions(context, ref),
            onSave: _save,
            onCancel: _cancel,
          );
        }
        if (value.acp case final account?) {
          return AcpAccountEditorView(
            value: account,
            templateSelector: selector,
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
            onCancel: _cancel,
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
                      onPressed: _cancel,
                      child: Text(AppLocalizations.of(context).commonCancel),
                    ),
                  ],
                ),
        );
      },
    );
  }
}

/// Owns the finite resource for one actual typed route entry. The Router alone
/// decides whether this entry is covered or removed; only disposal retires it.
class AccountEditorEntryConnector extends ConsumerStatefulWidget {
  const AccountEditorEntryConnector({
    required this.entry,
    this.focusModelId,
    this.addModel = false,
    super.key,
  });
  final AccountEditorEntryKey entry;
  final String? focusModelId;
  final bool addModel;

  @override
  ConsumerState<AccountEditorEntryConnector> createState() =>
      _AccountEditorEntryConnectorState();
}

class _AccountEditorEntryConnectorState
    extends ConsumerState<AccountEditorEntryConnector> {
  late final AccountEditorSessionViewModel _session;
  String? _locale;

  @override
  void initState() {
    super.initState();
    _session = ref.read(
      accountEditorSessionViewModelProvider(widget.entry).notifier,
    );
    final focusModelId = widget.focusModelId;
    final addModel = widget.addModel;
    scheduleMicrotask(() {
      if (mounted && _session.isActive) {
        unawaited(
          _session.initialize(focusModelId: focusModelId, addModel: addModel),
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
    final strings = accountStrings(l10n);
    scheduleMicrotask(() {
      if (mounted && _session.isActive) _session.setStrings(strings);
    });
  }

  @override
  void dispose() {
    _session.finish();
    super.dispose();
  }

  void _cancel() {
    switch (widget.entry) {
      case CreatingAccountEditorEntryKey():
        const SettingsRoute().go(context);
      case EditingAccountEditorEntryKey(:final account):
        AccountDetailsRoute(
          kind: account.kind,
          accountId: account.id,
        ).go(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return ref
        .watch(accountEditorSessionViewModelProvider(widget.entry))
        .when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, _) => Center(child: Text(l10n.accountsQueryFailed)),
          data: (value) {
            final editor = value.editor;
        if (editor != null) {
              return AccountEditorConnector(
                key: ValueKey(editor.editorId),
                entry: widget.entry,
                editor: editor,
              );
        }
            return ListView(
              padding: const EdgeInsets.all(24),
              children: [
                Text(
                  l10n.settingsNewAccount,
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                if (value.templatesLoading) const LinearProgressIndicator(),
                if (value.error != null) Text(value.error!),
                if (value.error != null)
                  TextButton(
                    onPressed: _session.loadTemplates,
                    child: Text(l10n.accountsRetry),
                  ),
                TextButton(onPressed: _cancel, child: Text(l10n.commonCancel)),
              ],
            );
          },
        );
  }
}
