import 'package:flutter/material.dart';

import '../../../../l10n/app_localizations.dart';
import '../state/account_presentations.dart';
import '../state/account_view_key_values.dart';
import '../widgets/account_editor_fields.dart';
import '../widgets/account_identity.dart';
import '../widgets/account_sections.dart';
import '../widgets/acp_account_panel.dart';
import 'native_account_editor_view.dart' show AccountEditorFooter;

class AcpAccountEditorView extends StatelessWidget {
  const AcpAccountEditorView({
    required this.value,
    required this.onNameChanged,
    required this.onAction,
    required this.onLoginMethodChanged,
    required this.onSave,
    required this.onCancel,
    this.scrollController,
    this.templateSelector,
    super.key,
  });
  final AcpAccountEditorPresentation value;
  final ValueChanged<String> onNameChanged;
  final ValueChanged<AcpAccountAction> onAction;
  final ValueChanged<String> onLoginMethodChanged;
  final VoidCallback onSave;
  final VoidCallback onCancel;
  final ScrollController? scrollController;
  final Widget? templateSelector;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AccountEditorScaffold(
      title: value.accountKey == null
          ? l10n.settingsNewAccount
          : l10n.settingsEditAccount,
      dirty: value.dirty,
      scrollKey: PageStorageKey<String>(
        AccountViewKeyValues.editorScroll(AccountKind.acp.name, value.editorId),
      ),
      scrollController: scrollController,
      children: [
        AccountSection(
          title: l10n.settingsAccountTemplate,
          child: templateSelector == null
              ? AccountIdentity(
                  name: value.templateName,
                  iconKey: value.iconKey,
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(l10n.accountsTemplatesHint),
                    const SizedBox(height: 16),
                    templateSelector!,
                  ],
                ),
        ),
        if (value.error != null) AccountInlineError(message: value.error!),
        AccountSection(
          title: l10n.accountsSettingsSection,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AccountRawTextField(
                key: ValueKey<String>(
                  AccountViewKeyValues.editorField(value.editorId, 'name'),
                ),
                value: value.name,
                label: l10n.settingsDisplayName,
                enabled: !value.saving,
                onChanged: onNameChanged,
              ),
              if (value.accountKey != null)
                ExpansionTile(
                  key: PageStorageKey('acp-editor-advanced:${value.editorId}'),
                  title: Text(l10n.accountsAdvancedSection),
                  tilePadding: EdgeInsets.zero,
                  children: [
                    AccountFacts(
                      facts: [
                        AccountDisplayFact(
                          label: l10n.settingsAccountId,
                          value: value.accountKey!.id,
                        ),
                      ],
                    ),
                  ],
                ),
            ],
          ),
        ),
        AccountSection(
          title: l10n.acpAccountConnectionInfoTitle,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AcpAccountPanel(
                value: value.preparation,
                onAction: onAction,
                onLoginMethodChanged: onLoginMethodChanged,
              ),
              const Divider(height: 32),
              AccountEditorFooter(
                saving: value.saving,
                canSave: value.canSave,
                // The owner decides the single emphasized operation.
                saveIsPrimary:
                    value.canSave && !value.preparation.hasPrimaryAction,
                onSave: onSave,
                onCancel: onCancel,
                saveLabel: value.saveAndConnect
                    ? l10n.acpAccountSaveAndConnect
                    : l10n.commonSave,
              ),
            ],
          ),
        ),
      ],
    );
  }
}
