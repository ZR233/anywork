import 'package:flutter/material.dart';

import '../../../../l10n/app_localizations.dart';
import '../state/account_presentations.dart';
import '../state/account_view_key_values.dart';
import 'account_sections.dart';

/// Shared editor page geometry. Drafts, navigation and saving stay caller-owned.
/// Eager form layout also makes off-screen manual rows available to ensureVisible.
class AccountEditorScaffold extends StatelessWidget {
  const AccountEditorScaffold({
    required this.title,
    required this.scrollKey,
    required this.children,
    this.dirty = false,
    this.scrollController,
    super.key,
  });
  final String title;
  final Key scrollKey;
  final List<Widget> children;
  final bool dirty;
  final ScrollController? scrollController;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Expanded(
        child: SingleChildScrollView(
          key: scrollKey,
          controller: scrollController,
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                title,
                style: Theme.of(context).textTheme.headlineMedium
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
              if (dirty)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    AppLocalizations.of(context).accountsDirty,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              const SizedBox(height: 24),
              ...children,
            ],
          ),
        ),
      ),
    ],
  );
}

class AccountConnectionControl extends StatelessWidget {
  const AccountConnectionControl({
    required this.value,
    required this.allowed,
    required this.onChanged,
    this.enabled = true,
    super.key,
  });
  final AccountConnection value;
  final List<AccountConnection> allowed;
  final ValueChanged<AccountConnection> onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text(l10n.accountsConnection),
        for (final connection in allowed)
          ChoiceChip(
            label: Text(accountConnectionLabel(l10n, connection)),
            selected: value == connection,
            onSelected: enabled ? (_) => onChanged(connection) : null,
          ),
      ],
    );
  }
}

class AccountNativeConnectionFields extends StatelessWidget {
  const AccountNativeConnectionFields({
    required this.value,
    required this.onChanged,
    this.billingControl,
    this.hideApiCredentials = false,
    super.key,
  });
  final NativeAccountEditorPresentation value;
  final void Function(NativeAccountField field, String raw) onChanged;
  final Widget? billingControl;
  final bool hideApiCredentials;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth >= 660
                ? (constraints.maxWidth - 16) / 2
                : constraints.maxWidth;
            return Wrap(
              spacing: 16,
              runSpacing: 16,
              children: [
                SizedBox(
                  width: width,
                  child: AccountRawTextField(
                    key: ValueKey(
                      AccountViewKeyValues.editorField(
                        value.editorId,
                        NativeAccountField.name.name,
                      ),
                    ),
                    value: value.name,
                    enabled: !value.saving,
                    label: l10n.settingsDisplayName,
                    onChanged: (raw) => onChanged(NativeAccountField.name, raw),
                  ),
                ),
                if (!hideApiCredentials)
                  SizedBox(
                    width: width,
                    child: AccountRawTextField(
                      key: ValueKey(
                        AccountViewKeyValues.editorField(
                          value.editorId,
                          NativeAccountField.endpoint.name,
                        ),
                      ),
                      value: value.endpoint,
                      enabled: !value.saving,
                      label: l10n.settingsBaseUrl,
                      keyboardType: TextInputType.url,
                      onChanged: (raw) =>
                          onChanged(NativeAccountField.endpoint, raw),
                    ),
                  ),
                if (!hideApiCredentials)
                  SizedBox(
                    width: width,
                    child: AccountRawTextField(
                      key: ValueKey(
                        AccountViewKeyValues.editorField(
                          value.editorId,
                          NativeAccountField.credential.name,
                        ),
                      ),
                      value: value.credential,
                      enabled: !value.saving,
                      label: value.hasStoredCredential
                          ? l10n.settingsApiKeyKeepCurrent
                          : value.credentialRequired
                          ? l10n.settingsApiKey
                          : l10n.settingsApiKeyOptional,
                      obscure: true,
                      onChanged: (raw) =>
                          onChanged(NativeAccountField.credential, raw),
                    ),
                  ),
                if (billingControl != null)
                  SizedBox(width: width, child: billingControl!),
              ],
            );
          },
        ),
        const SizedBox(height: 12),
        ExpansionTile(
          key: PageStorageKey('native-editor-advanced:${value.editorId}'),
          title: Text(l10n.accountsAdvancedSection),
          tilePadding: EdgeInsets.zero,
          children: [
            AccountFacts(
              facts: [
                if (value.accountKey != null)
                  AccountDisplayFact(
                    label: l10n.settingsAccountId,
                    value: value.accountKey!.id,
                  ),
                AccountDisplayFact(
                  label: l10n.settingsAccountTemplate,
                  value: value.templateKey.id,
                ),
                AccountDisplayFact(
                  label: l10n.settingsAccountProtocol,
                  value: value.protocolLabel,
                ),
              ],
            ),
          ],
        ),
      ],
    );
  }
}

class AccountManualModelEditor extends StatelessWidget {
  const AccountManualModelEditor({
    required this.value,
    required this.onFieldChanged,
    required this.onConnectionChanged,
    required this.onWireApiChanged,
    required this.onRemove,
    this.idFocusNode,
    this.nameFocusNode,
    super.key,
  });
  final ManualAccountModelPresentation value;
  final void Function(ManualModelField field, String raw) onFieldChanged;
  final ValueChanged<AccountConnection> onConnectionChanged;
  final ValueChanged<AccountWireApi> onWireApiChanged;
  final VoidCallback onRemove;
  final FocusNode? idFocusNode;
  final FocusNode? nameFocusNode;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth >= 660
                ? (constraints.maxWidth - 16) / 2
                : constraints.maxWidth;
            return Wrap(
              spacing: 16,
              runSpacing: 16,
              children: [
                for (final field in [
                  (ManualModelField.id, value.id, l10n.settingsModelId),
                  (ManualModelField.name, value.name, l10n.settingsDisplayName),
                  (
                    ManualModelField.contextWindow,
                    value.contextWindow,
                    l10n.settingsContextBudget,
                  ),
                  (
                    ManualModelField.maxOutputTokens,
                    value.maxOutputTokens,
                    l10n.settingsOutputBudget,
                  ),
                ])
                  SizedBox(
                    width: width,
                    child: AccountRawTextField(
                      key: ValueKey(
                        AccountViewKeyValues.manualField(
                          value.editorKey,
                          field.$1.name,
                        ),
                      ),
                      value: field.$2,
                      focusNode: switch (field.$1) {
                        ManualModelField.id => idFocusNode,
                        ManualModelField.name => nameFocusNode,
                        _ => null,
                      },
                      label: field.$3,
                      enabled:
                          field.$1 != ManualModelField.id || value.canEditId,
                      keyboardType:
                          field.$1 == ManualModelField.contextWindow ||
                              field.$1 == ManualModelField.maxOutputTokens
                          ? TextInputType.number
                          : TextInputType.text,
                      onChanged: (raw) => onFieldChanged(field.$1, raw),
                    ),
                  ),
              ],
            );
          },
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(l10n.settingsProtocolType),
            for (final api in value.allowedWireApis)
              ChoiceChip(
                label: Text(switch (api) {
                  AccountWireApi.chatCompletions =>
                    l10n.settingsProtocolChatCompletionsHttp,
                  AccountWireApi.responses =>
                    l10n.settingsProtocolResponsesHttp,
                }),
                selected: value.wireApi == api,
                onSelected: (_) => onWireApiChanged(api),
              ),
          ],
        ),
        const SizedBox(height: 12),
        AccountConnectionControl(
          value: value.connection,
          allowed: value.allowedConnections,
          onChanged: onConnectionChanged,
        ),
        if (value.canRemove)
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton.icon(
              onPressed: onRemove,
              icon: const Icon(Icons.delete_outline),
              label: Text(l10n.settingsRemoveModel),
            ),
          ),
        if (value.error != null) AccountInlineError(message: value.error!),
      ],
    );
  }
}
