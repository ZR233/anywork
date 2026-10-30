import 'package:flutter/material.dart';

import '../../../../l10n/app_localizations.dart';
import '../state/account_presentations.dart';
import '../state/account_view_key_values.dart';
import '../widgets/account_models_view.dart';
import '../widgets/account_editor_fields.dart';
import '../widgets/account_sections.dart';
import '../widgets/account_template_selector.dart';

class NativeAccountEditorView extends StatefulWidget {
  const NativeAccountEditorView({
    required this.value,
    required this.onFieldChanged,
    required this.onTemplateChanged,
    required this.onBillingChanged,
    required this.onResetBilling,
    required this.onAddModel,
    required this.onManualModelFieldChanged,
    required this.onManualModelConnectionChanged,
    required this.onManualModelWireApiChanged,
    required this.onRemoveManualModel,
    required this.modelActions,
    required this.onSave,
    required this.onCancel,
    this.scrollController,
    this.templateSelector,
    this.manualSectionKey,
    this.focusManualModelEditorKey,
    this.focusManualModelId = false,
    this.onSetDefaultOnCreateChanged,
    this.onAuthenticationChanged,
    this.onStartChatGptLogin,
    this.onCancelChatGptLogin,
    this.onOpenChatGptAuthorization,
    this.onOpenChatGptUsage,
    super.key,
  });
  final NativeAccountEditorPresentation value;
  final void Function(NativeAccountField field, String raw) onFieldChanged;
  final ValueChanged<AccountTemplateKey> onTemplateChanged;
  final ValueChanged<AccountBilling> onBillingChanged;
  final VoidCallback onResetBilling;
  final VoidCallback onAddModel;
  final void Function(String editorKey, ManualModelField field, String raw)
  onManualModelFieldChanged;
  final void Function(String editorKey, AccountConnection connection)
  onManualModelConnectionChanged;
  final void Function(String editorKey, AccountWireApi wireApi)
  onManualModelWireApiChanged;
  final ValueChanged<String> onRemoveManualModel;
  final AccountModelActions modelActions;
  final VoidCallback onSave;
  final VoidCallback onCancel;
  final ScrollController? scrollController;
  final Widget? templateSelector;
  final Key? manualSectionKey;
  final String? focusManualModelEditorKey;
  final bool focusManualModelId;
  final ValueChanged<bool>? onSetDefaultOnCreateChanged;
  final ValueChanged<AccountAuthenticationMethod>? onAuthenticationChanged;
  final VoidCallback? onStartChatGptLogin;
  final VoidCallback? onCancelChatGptLogin;
  final VoidCallback? onOpenChatGptAuthorization;
  final VoidCallback? onOpenChatGptUsage;

  @override
  State<NativeAccountEditorView> createState() =>
      _NativeAccountEditorViewState();
}

class _NativeAccountEditorViewState extends State<NativeAccountEditorView> {
  final Map<String, GlobalKey> _rowKeys = {};
  final FocusNode _targetFocus = FocusNode();
  int _focusGeneration = 0;
  int? _scheduledGeneration;
  bool _focusCompleted = false;

  @override
  void didUpdateWidget(covariant NativeAccountEditorView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value.editorId != widget.value.editorId ||
        oldWidget.focusManualModelEditorKey !=
            widget.focusManualModelEditorKey ||
        oldWidget.focusManualModelId != widget.focusManualModelId) {
      _focusGeneration++;
      _focusCompleted = false;
    }
    if (oldWidget.value.editorId != widget.value.editorId) _rowKeys.clear();
  }

  void _scheduleFocus() {
    final target = widget.focusManualModelEditorKey;
    if (target == null ||
        _focusCompleted ||
        _scheduledGeneration == _focusGeneration ||
        !widget.value.manualModels.any((model) => model.editorKey == target)) {
      return;
    }
    final generation = _focusGeneration;
    _scheduledGeneration = generation;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted || generation != _focusGeneration) return;
      _scheduledGeneration = null;
      final targetContext = _rowKeys[target]?.currentContext;
      if (targetContext == null) return;
      await Scrollable.ensureVisible(
        targetContext,
        alignment: .15,
        duration: Duration.zero,
      );
      if (!mounted ||
          generation != _focusGeneration ||
          _rowKeys[target]?.currentContext == null) {
        return;
      }
      _targetFocus.requestFocus();
      _focusCompleted = true;
    });
  }

  @override
  void dispose() {
    _focusGeneration++;
    _targetFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final value = widget.value;
    final l10n = AppLocalizations.of(context);
    final ids = value.manualModels.map((model) => model.editorKey).toSet();
    _rowKeys.removeWhere((key, _) => !ids.contains(key));
    for (final id in ids) {
      _rowKeys.putIfAbsent(id, GlobalKey.new);
    }
    _scheduleFocus();
    final templateSection = AccountSection(
      title: l10n.settingsAccountTemplate,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(l10n.accountsTemplatesHint),
          const SizedBox(height: 16),
          widget.templateSelector ??
              AccountTemplateSelector(
                templates: value.templates,
                selected: value.templateKey,
                enabled: value.canChangeTemplate && !value.saving,
                onSelected: widget.onTemplateChanged,
              ),
        ],
      ),
    );
    return AccountEditorScaffold(
      title: value.accountKey == null
          ? l10n.settingsNewAccount
          : l10n.settingsEditAccount,
      dirty: value.dirty,
      scrollKey: PageStorageKey<String>(
        AccountViewKeyValues.editorScroll(
          AccountKind.native.name,
          value.editorId,
        ),
      ),
      scrollController: widget.scrollController,
      children: [
        if (!value.isOpenAiTemplate) templateSection,
        if (value.error != null) AccountInlineError(message: value.error!),
        AccountSection(
          title: l10n.accountsConnectionBillingTitle,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (value.isOpenAiTemplate) ...[
                SegmentedButton<AccountAuthenticationMethod>(
                  segments: [
                    ButtonSegment(
                      value: AccountAuthenticationMethod.apiKey,
                      label: Text(l10n.accountsAuthApiKey),
                    ),
                    ButtonSegment(
                      value: AccountAuthenticationMethod.chatGpt,
                      label: Text(l10n.accountsAuthChatGpt),
                    ),
                  ],
                  selected: {value.authentication},
                  onSelectionChanged:
                      value.saving || widget.onAuthenticationChanged == null
                      ? null
                      : (selection) =>
                            widget.onAuthenticationChanged!(selection.single),
                ),
                const SizedBox(height: 20),
              ],
              if (value.isOpenAiTemplate &&
                  value.authentication ==
                      AccountAuthenticationMethod.chatGpt) ...[
                _ChatGptConnection(
                  value: value,
                  onStart: widget.onStartChatGptLogin,
                  onCancel: widget.onCancelChatGptLogin,
                  onOpenAuthorization: widget.onOpenChatGptAuthorization,
                  onOpenUsage: widget.onOpenChatGptUsage,
                ),
                const SizedBox(height: 20),
              ],
              AccountNativeConnectionFields(
                value: value,
                onChanged: widget.onFieldChanged,
                hideApiCredentials:
                    value.isOpenAiTemplate &&
                    value.authentication == AccountAuthenticationMethod.chatGpt,
                billingControl: AccountBillingControl(
                  value: value.billing,
                  onChanged: widget.onBillingChanged,
                  onReset: widget.onResetBilling,
                  layout: AccountBillingControlLayout.field,
                ),
              ),
              if (value.showSetDefaultOnCreate) ...[
                const SizedBox(height: 16),
                Card.filled(
                  margin: EdgeInsets.zero,
                  child: SwitchListTile(
                    key: const ValueKey('account-set-default-on-create'),
                    title: Text(l10n.accountsSetDefaultOnCreate),
                    subtitle: Text(l10n.accountsSetDefaultOnCreateHint),
                    value: value.setDefaultOnCreate,
                    onChanged: value.saving
                        ? null
                        : widget.onSetDefaultOnCreateChanged,
                  ),
                ),
              ],
              const Divider(height: 32),
              AccountEditorFooter(
                saving: value.saving,
                canSave: value.canSave,
                saveLabel: value.accountKey == null
                    ? l10n.settingsAddAccount
                    : null,
                onSave: widget.onSave,
                onCancel: widget.onCancel,
              ),
            ],
          ),
        ),
        if (value.isOpenAiTemplate) templateSection,
        if (value.declaredModels.isNotEmpty)
          AccountSection(
            title: l10n.settingsAccountModelsTitle,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final model in value.declaredModels)
                  AccountModelListItem(
                    key: ValueKey<String>(
                      AccountViewKeyValues.modelItem(
                        model.key.account.kind.name,
                        model.key.account.id,
                        model.key.modelId,
                      ),
                    ),
                    value: model,
                    actions: widget.modelActions,
                  ),
              ],
            ),
          ),
        AccountSection(
          key: widget.manualSectionKey,
          title: l10n.settingsAccountCustomModelsTitle,
          actions: [
            OutlinedButton.icon(
              onPressed: value.canAddModel ? widget.onAddModel : null,
              icon: const Icon(Icons.add),
              label: Text(l10n.settingsAddModel),
            ),
          ],
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (value.manualModels.isEmpty) Text(l10n.settingsNoCustomModels),
              for (final model in value.manualModels)
                Padding(
                  key: _rowKeys[model.editorKey],
                  padding: const EdgeInsets.only(bottom: 20),
                  child: KeyedSubtree(
                    key: ValueKey(
                      AccountViewKeyValues.manualItem(model.editorKey),
                    ),
                    child: AccountManualModelEditor(
                      value: model,
                      idFocusNode:
                          widget.focusManualModelEditorKey == model.editorKey &&
                              widget.focusManualModelId
                          ? _targetFocus
                          : null,
                      nameFocusNode:
                          widget.focusManualModelEditorKey == model.editorKey &&
                              !widget.focusManualModelId
                          ? _targetFocus
                          : null,
                      onFieldChanged: (field, raw) =>
                          widget.onManualModelFieldChanged(
                            model.editorKey,
                            field,
                            raw,
                          ),
                      onConnectionChanged: (connection) =>
                          widget.onManualModelConnectionChanged(
                            model.editorKey,
                            connection,
                          ),
                      onWireApiChanged: (api) => widget
                          .onManualModelWireApiChanged(model.editorKey, api),
                      onRemove: () =>
                          widget.onRemoveManualModel(model.editorKey),
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

class _ChatGptConnection extends StatelessWidget {
  const _ChatGptConnection({
    required this.value,
    required this.onStart,
    required this.onCancel,
    required this.onOpenAuthorization,
    required this.onOpenUsage,
  });

  final NativeAccountEditorPresentation value;
  final VoidCallback? onStart;
  final VoidCallback? onCancel;
  final VoidCallback? onOpenAuthorization;
  final VoidCallback? onOpenUsage;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final login = value.chatGptLogin;
    final phase = login?.phase;
    final waiting = phase == ChatGptLoginPhase.awaitingBrowser;
    final busy =
        phase == ChatGptLoginPhase.preparing ||
        phase == ChatGptLoginPhase.exchangingCode;
    final savedConnection = login == null && value.savedChatGptAccount != null;
    final succeeded = phase == ChatGptLoginPhase.succeeded || savedConnection;
    final hasPermission =
        login?.account?.planUsageEnabled ??
        value.savedChatGptAccount?.planUsageEnabled ??
        false;
    final status = switch (phase) {
      ChatGptLoginPhase.preparing => l10n.accountsChatGptPreparing,
      ChatGptLoginPhase.awaitingBrowser => l10n.accountsChatGptWaitingBrowser,
      ChatGptLoginPhase.exchangingCode => l10n.accountsChatGptChecking,
      ChatGptLoginPhase.succeeded when hasPermission =>
        l10n.accountsChatGptConnected,
      ChatGptLoginPhase.succeeded => l10n.accountsChatGptPermissionMissing,
      ChatGptLoginPhase.cancelled => l10n.accountsChatGptCancelled,
      ChatGptLoginPhase.failed => switch (login?.failure) {
        ChatGptLoginFailureCode.missingPlanPermission =>
          l10n.accountsChatGptPermissionMissing,
        ChatGptLoginFailureCode.authorizationDenied =>
          l10n.accountsChatGptAuthorizationDenied,
        ChatGptLoginFailureCode.expired => l10n.accountsChatGptExpired,
        _ => l10n.accountsChatGptFailed,
      },
      null when savedConnection => l10n.accountsChatGptConnected,
      null => l10n.accountsChatGptNotConnected,
    };
    final email = login?.account?.email ?? value.savedChatGptAccount?.email;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.accountsChatGptConnectionHint,
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: 12),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (busy) ...[
              const SizedBox.square(
                dimension: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              const SizedBox(width: 10),
            ],
            Expanded(child: Text(status)),
          ],
        ),
        if (succeeded && email != null && email.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(email, style: Theme.of(context).textTheme.bodySmall),
        ],
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            if (waiting)
              OutlinedButton.icon(
                onPressed: onOpenAuthorization,
                icon: const Icon(Icons.open_in_new),
                label: Text(l10n.accountsChatGptOpenBrowser),
              ),
            if (value.chatGptLogin == null ||
                phase == ChatGptLoginPhase.cancelled ||
                phase == ChatGptLoginPhase.failed ||
                (succeeded && !hasPermission))
              FilledButton.icon(
                onPressed: onStart,
                icon: const Icon(Icons.login),
                label: Text(l10n.accountsChatGptLogin),
              ),
            if (busy || waiting)
              OutlinedButton(
                onPressed: onCancel,
                child: Text(l10n.accountsChatGptCancel),
              ),
            if (succeeded)
              TextButton.icon(
                onPressed: onOpenUsage,
                icon: const Icon(Icons.open_in_new),
                label: Text(l10n.accountsChatGptUsage),
              ),
          ],
        ),
      ],
    );
  }
}

class AccountEditorFooter extends StatelessWidget {
  const AccountEditorFooter({
    required this.saving,
    required this.canSave,
    required this.onSave,
    required this.onCancel,
    this.saveLabel,
    this.saveIsPrimary = true,
    super.key,
  });
  final bool saving;
  final bool canSave;
  final VoidCallback onSave;
  final VoidCallback onCancel;
  final String? saveLabel;
  final bool saveIsPrimary;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Material(
      type: MaterialType.transparency,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Wrap(
            alignment: WrapAlignment.end,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 12,
            runSpacing: 8,
            children: [
              if (saving)
                const SizedBox.square(
                  dimension: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              OutlinedButton(
                key: const ValueKey<String>('account-cancel'),
                onPressed: onCancel,
                child: Text(l10n.commonCancel),
              ),
              if (saveIsPrimary)
                FilledButton(
                  key: const ValueKey<String>('account-save'),
                  onPressed: canSave && !saving ? onSave : null,
                  child: Text(saveLabel ?? l10n.commonSave),
                )
              else
                OutlinedButton(
                  key: const ValueKey<String>('account-save'),
                  onPressed: canSave && !saving ? onSave : null,
                  child: Text(saveLabel ?? l10n.commonSave),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
