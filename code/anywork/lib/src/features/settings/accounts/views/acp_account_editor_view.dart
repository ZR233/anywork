import 'package:flutter/material.dart';

import '../../../../l10n/app_localizations.dart';
import '../../../../shared/account_brand.dart';
import '../state/account_presentations.dart';
import '../state/account_view_key_values.dart';
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
    super.key,
  });
  final AcpAccountEditorPresentation value;
  final ValueChanged<String> onNameChanged;
  final ValueChanged<AcpAccountAction> onAction;
  final ValueChanged<String> onLoginMethodChanged;
  final VoidCallback onSave;
  final VoidCallback onCancel;
  final ScrollController? scrollController;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: ListView(
            key: PageStorageKey<String>(
              AccountViewKeyValues.editorScroll(
                AccountKind.acp.name,
                value.editorId,
              ),
            ),
            controller: scrollController,
            padding: const EdgeInsets.all(24),
            children: [
              Row(
                children: [
                  AccountBrandMark(
                    fallbackName: value.templateName,
                    iconKey: value.iconKey,
                    size: 48,
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Text(
                      value.templateName,
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                  ),
                ],
              ),
              if (value.dirty)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(l10n.accountsDirty),
                ),
              const SizedBox(height: 24),
              if (value.error != null)
                AccountInlineError(message: value.error!),
              AccountSection(
                title: l10n.accountsSettingsSection,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    AccountRawTextField(
                      key: ValueKey<String>(
                        AccountViewKeyValues.editorField(
                          value.editorId,
                          'name',
                        ),
                      ),
                      value: value.name,
                      label: l10n.settingsDisplayName,
                      onChanged: onNameChanged,
                    ),
                    if (value.accountKey != null)
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
              ),
              AccountSection(
                title: l10n.acpAccountConnectionInfoTitle,
                child: AcpAccountPanel(
                  value: value.preparation,
                  onAction: onAction,
                  onLoginMethodChanged: onLoginMethodChanged,
                ),
              ),
            ],
          ),
        ),
        AccountEditorFooter(
          saving: value.saving,
          canSave: value.canSave,
          // The VM chooses the panel operation; only one area emphasizes an action.
          saveIsPrimary: value.canSave && !value.preparation.hasPrimaryAction,
          onSave: onSave,
          onCancel: onCancel,
          saveLabel: value.saveAndConnect
              ? l10n.acpAccountSaveAndConnect
              : l10n.commonSave,
        ),
      ],
    );
  }
}
