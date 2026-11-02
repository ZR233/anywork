import 'package:flutter/material.dart';

import '../../../../app/theme/studio_semantic_colors.dart';
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
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final semantic = theme.extension<StudioSemanticColors>();
    final isCreating = value.accountKey == null;
    final stepHint = !isCreating
        ? null
        : value.prepared
        ? (
            icon: Icons.verified_outlined,
            color: semantic?.success ?? scheme.primary,
            text: l10n.acpInstallReadyConfirmedHint,
          )
        : value.preparation.primaryAction == AcpAccountAction.usePrepared
        ? (
            icon: Icons.touch_app_outlined,
            color: scheme.primary,
            text: l10n.acpInstallClaimHint,
          )
        : value.preparation.phase == AcpPresentationPhase.idle
        ? (
            icon: Icons.download_for_offline_outlined,
            color: scheme.primary,
            text: l10n.acpInstallIdleHint,
          )
        : null;

    return AccountEditorScaffold(
      title: isCreating ? l10n.settingsNewAccount : l10n.settingsEditAccount,
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
          title: isCreating
              ? l10n.acpEditorStepBasicTitle
              : l10n.accountsSettingsSection,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (isCreating) ...[
                Text(
                  l10n.acpEditorStepBasicSubtitle,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 14),
              ],
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
          title: isCreating
              ? l10n.acpEditorStepPrepareTitle
              : l10n.acpAccountConnectionInfoTitle,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (isCreating) ...[
                Text(
                  l10n.acpEditorStepPrepareSubtitle,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 12),
              ],
              if (stepHint != null) ...[
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: Color.alphaBlend(
                      stepHint.color.withValues(alpha: 0.08),
                      scheme.surfaceContainerLowest,
                    ),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: stepHint.color.withValues(alpha: 0.30),
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Icon(stepHint.icon, size: 18, color: stepHint.color),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            stepHint.text,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: scheme.onSurface,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
              ],
              AcpAccountPanel(
                value: value.preparation,
                onAction: onAction,
                onLoginMethodChanged: onLoginMethodChanged,
              ),
              const Divider(height: 32),
              if (isCreating) ...[
                Text(
                  l10n.acpEditorStepConnectTitle,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  l10n.acpEditorStepConnectSubtitle,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 16),
              ],
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
