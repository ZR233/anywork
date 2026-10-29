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
    required this.slot,
    required this.session,
    required this.editor,
    this.focusModelId,
    this.addModel = false,
    super.key,
  });
  final AccountEditorEntryKey entry;
  final AccountEditorSessionViewModel slot;
  final AccountEditorSessionOwner session;
  final AccountEditorKey editor;
  final String? focusModelId;
  final bool addModel;
  @override
  ConsumerState<AccountEditorConnector> createState() =>
      _AccountEditorConnectorState();
}

class _AccountEditorConnectorState
    extends ConsumerState<AccountEditorConnector> {
  String? _locale;
  AccountAcpKey? _localizedAcp;
  AccountModelsViewModel? _localizedModels;
  String? _modelsLocale;
  ({
    AccountDisplayKey target,
    AccountModelsViewModel owner,
    void Function() release,
  })?
  _createdModels;
  int _selectorRevision = 0;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final l10n = AppLocalizations.of(context);
    if (_locale == l10n.localeName) return;
    _locale = l10n.localeName;
    _localizedAcp = null;
    scheduleMicrotask(() {
      if (!_hasCurrentSession() ||
          !widget.session.isEditorCurrent(widget.editor) ||
          !ref.exists(accountEditorViewModelProvider(widget.editor))) {
        return;
      }
      final strings = accountStrings(l10n);
      ref
          .read(accountEditorViewModelProvider(widget.editor).notifier)
          .setStrings(strings);
    });
  }

  @override
  void dispose() {
    final release = _createdModels?.release;
    _createdModels = null;
    release?.call();
    super.dispose();
  }

  bool _hasCurrentSession() {
    if (!mounted) return false;
    final provider = accountEditorSessionViewModelProvider(widget.entry);
    return ref.exists(provider) &&
        identical(ref.read(provider.notifier), widget.slot) &&
        widget.slot.isCurrentOwner(widget.session) &&
        widget.session.isActive;
  }

  bool _isCurrent(
    AccountEditorSessionOwner session,
    AccountEditorKey source,
    AccountEditorViewModel owner,
    ModalRoute<dynamic> sourceRoute,
  ) {
    if (!mounted) return false;
    final editorProvider = accountEditorViewModelProvider(source);
    return identical(ModalRoute.of(context), sourceRoute) &&
        sourceRoute.isCurrent &&
        widget.editor == source &&
        _hasCurrentSession() &&
        identical(widget.session, session) &&
        session.isEditorCurrent(source) &&
        ref.exists(editorProvider) &&
        identical(ref.read(editorProvider.notifier), owner);
  }

  void _cancel() {
    if (!_hasCurrentSession() ||
        !widget.session.isEditorCurrent(widget.editor) ||
        ModalRoute.of(context)?.isCurrent != true) {
      return;
    }
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
    if (!mounted) return;
    final sourceRoute = ModalRoute.of(context);
    if (sourceRoute == null || !sourceRoute.isCurrent) return;
    final source = widget.editor;
    final session = widget.session;
    final editorProvider = accountEditorViewModelProvider(source);
    if (!_hasCurrentSession() || !ref.exists(editorProvider)) return;
    final owner = ref.read(editorProvider.notifier);
    if (!_isCurrent(session, source, owner, sourceRoute)) return;
    final token = owner.leaveToken();
    if (!await owner.save() ||
        !_isCurrent(session, source, owner, sourceRoute) ||
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
        owner.hasUnconfirmedSave()) {
      return;
    }
    if (!mounted ||
        !_isCurrent(session, source, owner, sourceRoute) ||
        !owner.matchesLeaveToken(token)) {
      return;
    }
    AccountDetailsRoute(
      kind: source.target.kind,
      accountId: source.target.id,
    ).go(context);
  }

  Future<void> _switchTemplate(AccountTemplateKey template) async {
    if (!mounted) return;
    // The entry, unlike its replaced form, survives this same-page business
    // commit. Retain only its actual context and the official source route.
    final entryContext = context
        .findAncestorStateOfType<_AccountEditorEntryConnectorState>()
        ?.context;
    if (entryContext == null) return;
    final sourceRoute = ModalRoute.of(context);
    if (sourceRoute == null || !sourceRoute.isCurrent) return;
    final container = ProviderScope.containerOf(context, listen: false);
    final sessionProvider = accountEditorSessionViewModelProvider(widget.entry);
    final slot = widget.slot;
    final session = widget.session;
    bool sourceCurrent() =>
        entryContext.mounted &&
        identical(ModalRoute.of(entryContext), sourceRoute) &&
        sourceRoute.isCurrent &&
        container.exists(sessionProvider) &&
        identical(container.read(sessionProvider.notifier), slot) &&
        slot.isCurrentOwner(session) &&
        session.isActive;
    if (!sourceCurrent()) return;
    final source = widget.editor;
    if (template == source.template) return;
    final sourceProvider = accountEditorViewModelProvider(source);
    if (!container.exists(sourceProvider)) return;
    final sourceOwner = container.read(sourceProvider.notifier);
    final modelsProvider = source.target.kind == AccountKind.native
        ? accountModelsViewModelProvider(source.target)
        : null;
    final models = modelsProvider != null && container.exists(modelsProvider)
        ? container.read(modelsProvider.notifier)
        : null;
    final compactToken = models?.compactLeaveToken();
    final replacement = session.beginTemplateReplacement(source);
    if (replacement == null) return;
    final choice = await confirmAccountTemplateReplacement(
      context,
      widget.entry,
      source: source,
      replacement: replacement,
    );
    if (choice == null || !sourceCurrent()) {
      session.cancelTemplateReplacement(replacement);
      if (mounted && sourceCurrent()) setState(() => _selectorRevision++);
      return;
    }
    if (!_isCurrent(session, source, sourceOwner, sourceRoute) ||
        !sourceCurrent() ||
        !session.isTemplateReplacementCurrent(source, replacement)) {
      return;
    }
    if (models != null &&
        (!container.exists(modelsProvider!) ||
            !identical(container.read(modelsProvider.notifier), models) ||
            !models.matchesCompactLeaveToken(compactToken!) ||
            models.compactLeaveBlocked())) {
      return;
    }
    if (models == null &&
        modelsProvider != null &&
        container.exists(modelsProvider)) {
      return;
    }
    if (!sourceCurrent()) return;
    final next = session.replaceTemplate(
      source: source,
      template: template,
      token: replacement,
    );
    if (next == null || !sourceCurrent() || !session.isEditorCurrent(next)) {
      return;
    }
    if (choice == AccountLeaveChoice.discard && models != null) {
      models.discardCompactDrafts(compactToken!);
    }
    if (next.target.kind != AccountKind.acp) return;
    final editorProvider = accountEditorViewModelProvider(next);
    if (!sourceCurrent() || !container.exists(editorProvider)) return;
    final nextOwner = container.read(editorProvider.notifier);
    final nextToken = nextOwner.leaveToken();
    await container.read(editorProvider.future);
    if (sourceCurrent() &&
        session.isEditorCurrent(next) &&
        container.exists(editorProvider) &&
        identical(container.read(editorProvider.notifier), nextOwner) &&
        nextOwner.matchesLeaveToken(nextToken) &&
        !nextOwner.leaveBlocked() &&
        !nextOwner.hasUnconfirmedSave()) {
      await nextOwner.prepareSelectedTemplate();
    }
  }

  @override
  Widget build(BuildContext context) {
    final sessionState = ref
        .watch(accountEditorSessionViewModelProvider(widget.entry))
        .asData
        ?.value;
    if (!_hasCurrentSession() ||
        sessionState == null ||
        sessionState.ownerId != widget.session.ownerId ||
        sessionState.editor != widget.editor ||
        !widget.session.isEditorCurrent(widget.editor)) {
      return const Center(child: CircularProgressIndicator());
    }
    final provider = accountEditorViewModelProvider(widget.editor);
    final state = ref.watch(provider);
    final acpKey = state.asData?.value.acpKey;
    final acp = acpKey == null
        ? null
        : ref.watch(acpAccountViewModelProvider(acpKey)).asData?.value;
    final confirmedTarget = state.asData?.value.native?.accountKey;
    final modelsTarget =
        confirmedTarget?.kind == AccountKind.native &&
            confirmedTarget == widget.editor.target
        ? confirmedTarget
        : null;
    final modelsProvider = modelsTarget == null
        ? null
        : accountModelsViewModelProvider(modelsTarget);
    final models = modelsProvider == null
        ? null
        : ref.watch(modelsProvider).asData?.value;
    if (modelsProvider != null && modelsTarget != null) {
      final modelsOwner = ref.read(modelsProvider.notifier);
      // Edit already has the Details scope. A confirmed Create can remain here
      // after a follow-up failure, so its actual form owns one finite retention.
      if (widget.editor.creating && _createdModels == null) {
        _createdModels = (
          target: modelsTarget,
          owner: modelsOwner,
          release: modelsOwner.retainAccountScope(),
        );
      }
      final l10n = AppLocalizations.of(context);
      final locale = l10n.localeName;
      if (!identical(_localizedModels, modelsOwner) ||
          _modelsLocale != locale) {
        final strings = accountStrings(l10n);
        final source = widget.editor;
        final session = widget.session;
        scheduleMicrotask(() {
          if (!_hasCurrentSession() ||
              _locale != locale ||
              !identical(widget.session, session) ||
              widget.editor != source ||
              !session.isEditorCurrent(source) ||
              !ref.exists(provider) ||
              !ref.exists(modelsProvider) ||
              !identical(ref.read(modelsProvider.notifier), modelsOwner)) {
            return;
          }
          final projection = ref
              .read(accountEditorSessionViewModelProvider(widget.entry))
              .asData
              ?.value;
          final current = ref.read(provider).asData?.value;
          if (projection?.ownerId != session.ownerId ||
              projection?.editor != source ||
              current?.key != source ||
              current?.native?.accountKey != modelsTarget ||
              (source.creating &&
                  (_createdModels?.target != modelsTarget ||
                      !identical(_createdModels?.owner, modelsOwner)))) {
            return;
          }
          if (identical(_localizedModels, modelsOwner) &&
              _modelsLocale == locale) {
            return;
          }
          _localizedModels = modelsOwner;
          _modelsLocale = locale;
          modelsOwner.setStrings(strings);
        });
      }
    }
    if (acpKey != null && _localizedAcp != acpKey) {
      _localizedAcp = acpKey;
      final strings = accountStrings(AppLocalizations.of(context));
      final source = widget.editor;
      final acpProvider = acpAccountViewModelProvider(acpKey);
      final acpOwner = ref.read(acpProvider.notifier);
      scheduleMicrotask(() {
        if (_hasCurrentSession() &&
            widget.session.isEditorCurrent(source) &&
            widget.editor == source &&
            ref.exists(acpProvider) &&
            identical(ref.read(acpProvider.notifier), acpOwner)) {
          acpOwner.setStrings(strings);
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
        final selector = widget.editor.creating
            ? AccountTemplateSelector(
                key: ValueKey((widget.editor.editorId, _selectorRevision)),
                templates: sessionState.templates,
                selected: widget.editor.template,
                enabled: !value.saving,
                onSelected: _switchTemplate,
              )
            : null;
        if (value.native case final native?) {
          final source = widget.editor;
          // Reading the official route also rebuilds this retained form when
          // it becomes current again. A queued callback consumes only the
          // latest typed props, never a frozen query from an earlier build.
          final sourceRoute = ModalRoute.of(context);
          final session = widget.session;
          if (widget.addModel &&
              owner.addModelEntryEditorKey() == null &&
              sourceRoute != null &&
              sourceRoute.isCurrent &&
              native.canAddModel) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!_isCurrent(session, source, owner, sourceRoute) ||
                  !widget.addModel ||
                  owner.addModelEntryEditorKey() != null) {
                return;
              }
              owner.consumeAddModelEntry(requested: widget.addModel);
            });
          }
          final focusEditorKey = widget.addModel
              ? owner.addModelEntryEditorKey()
              : native.manualModels
                    .where((model) => model.id.raw == widget.focusModelId)
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
            focusManualModelId: widget.addModel,
            onFieldChanged: owner.changeField,
            onTemplateChanged: _switchTemplate,
            onBillingChanged: owner.changeBilling,
            onResetBilling: () => owner.changeBilling(null),
            onSetDefaultOnCreateChanged:
                native.showSetDefaultOnCreate &&
                    !value.saving &&
                    !owner.hasUnconfirmedSave()
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
              if (!mounted) return;
              final sourceRoute = ModalRoute.of(context);
              if (sourceRoute == null || !sourceRoute.isCurrent) return;
              final source = widget.editor;
              final token = owner.leaveToken();
              final session = widget.session;
              if (!_isCurrent(session, source, owner, sourceRoute)) return;
              if (!owner.isSavedModel(key)) {
                if (_isCurrent(session, source, owner, sourceRoute) &&
                    owner.matchesLeaveToken(token)) {
                  await owner.removeModel(key);
                }
                return;
              }
              final modelsProvider = accountModelsViewModelProvider(
                source.target,
              );
              if (!ref.exists(modelsProvider)) return;
              final modelsOwner = ref.read(modelsProvider.notifier);
              final compactToken = modelsOwner.compactLeaveToken();
              bool canRemoveSaved() =>
                  _isCurrent(session, source, owner, sourceRoute) &&
                  owner.matchesLeaveToken(token) &&
                  owner.isSavedModel(key) &&
                  ref.exists(modelsProvider) &&
                  identical(ref.read(modelsProvider.notifier), modelsOwner) &&
                  modelsOwner.canRemove(expectedToken: compactToken);
              if (!canRemoveSaved()) return;
              if (!await confirmAccountDelete(
                    context,
                    owner.modelName(key),
                    manualModel: true,
                  ) ||
                  !canRemoveSaved()) {
                return;
              }
              await owner.removeModel(
                key,
                modelsOwner: modelsOwner,
                expectedCompactToken: compactToken,
              );
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
              if (!mounted) return;
              final sourceRoute = ModalRoute.of(context);
              if (acpKey != null &&
                  sourceRoute != null &&
                  _isCurrent(
                    widget.session,
                    widget.editor,
                    owner,
                    sourceRoute,
                  )) {
                unawaited(performAcpAction(context, ref, acpKey, action));
              }
            },
            onLoginMethodChanged: (id) {
              if (!mounted) return;
              final sourceRoute = ModalRoute.of(context);
              if (acpKey != null &&
                  sourceRoute != null &&
                  _isCurrent(
                    widget.session,
                    widget.editor,
                    owner,
                    sourceRoute,
                  )) {
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
  final Object _mountOwner = Object();
  late final AccountEditorSessionViewModel _slot;
  late final AccountEditorSessionOwner _session;
  String? _locale;

  bool _hasCurrentOwner() {
    if (!mounted) return false;
    final provider = accountEditorSessionViewModelProvider(widget.entry);
    return ref.exists(provider) &&
        identical(ref.read(provider.notifier), _slot) &&
        _slot.isCurrentOwner(_session) &&
        _session.isActive;
  }

  @override
  void initState() {
    super.initState();
    _slot = ref.read(
      accountEditorSessionViewModelProvider(widget.entry).notifier,
    );
    _session = _slot.claimMount(_mountOwner);
    scheduleMicrotask(() {
      if (_hasCurrentOwner()) {
        unawaited(_session.initialize());
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
      if (_hasCurrentOwner()) _session.setStrings(strings);
    });
  }

  @override
  void dispose() {
    _slot.releaseMount(_session);
    super.dispose();
  }

  void _cancel() {
    if (!_hasCurrentOwner() || ModalRoute.of(context)?.isCurrent != true) {
      return;
    }
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
    final value = ref
        .watch(accountEditorSessionViewModelProvider(widget.entry))
        .asData
        ?.value;
    // A reused locator can still expose the previous mount's cached value.
    // Never render its editor, templates or errors for this captured owner.
    if (!_hasCurrentOwner() ||
        value == null ||
        value.ownerId != _session.ownerId ||
        value.editor != _session.currentEditor) {
      return const Center(child: CircularProgressIndicator());
    }
    final editor = value.editor;
    if (editor != null) {
      return AccountEditorConnector(
        key: ValueKey(editor.editorId),
        entry: widget.entry,
        slot: _slot,
        session: _session,
        editor: editor,
        focusModelId: widget.focusModelId,
        addModel: widget.addModel,
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
            onPressed: () {
              if (_hasCurrentOwner()) unawaited(_session.loadTemplates());
            },
            child: Text(l10n.accountsRetry),
          ),
        TextButton(onPressed: _cancel, child: Text(l10n.commonCancel)),
      ],
    );
  }
}
