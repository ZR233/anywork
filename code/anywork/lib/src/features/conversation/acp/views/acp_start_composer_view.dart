import 'package:material_ui/material_ui.dart';

import '../../../../app/theme/studio_tokens.dart';
import '../../../../l10n/studio_l10n.dart';
import '../../../../shared/composer_action_button.dart';
import '../../../../shared/conversation_composer.dart';
import '../../../../shared/studio_chrome.dart';
import '../state/acp_view_state.dart';

/// Binds ACP draft eligibility and diagnostics to the shared conversation editor.
class AcpStartComposerView extends StatelessWidget {
  const AcpStartComposerView({
    super.key,
    required this.state,
    required this.onDraftChanged,
    required this.onSubmit,
    this.configurationBar,
    this.onRetryPreparation,
    this.onAcceptConfiguration,
    this.onRemoveAttachment,
  });

  final AcpStartComposerViewState state;
  final ValueChanged<String> onDraftChanged;
  final VoidCallback onSubmit;
  final Widget? configurationBar;
  final VoidCallback? onRetryPreparation;
  final VoidCallback? onAcceptConfiguration;
  final ValueChanged<String>? onRemoveAttachment;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return ConversationComposer(
      identity: ('acp-start', state.workspaceId),
      text: state.text,
      inputKey: ValueKey(AcpViewKeyValues.startInput(state.workspaceId)),
      onTextChanged: onDraftChanged,
      onSubmit: state.canCreate ? onSubmit : null,
      enabled: state.canEditDraft,
      autofocus: true,
      creationCard: true,
      configuration: configurationBar,
      attachments: state.stagedAttachments,
      onRemoveAttachment: state.submitting ? null : onRemoveAttachment,
      primaryAction: ComposerActionPresentation(
        buttonKey: ValueKey(AcpViewKeyValues.startSubmit(state.workspaceId)),
        state: state.submitting || state.preparing
            ? ComposerActionButtonState.busy
            : ComposerActionButtonState.send,
        tooltip: state.preparing
            ? l10n.acpComposerBlockerInitializing
            : state.submitting
            ? l10n.acpStartCreatingAction
            : l10n.composerSend,
        onPressed: state.canCreate ? onSubmit : null,
      ),
      diagnostics: [
        if (state.failureMessage case final failure?)
          Row(
            children: [
              Expanded(
                child: StudioInlineMessage(
                  icon: Icons.error_outline_rounded,
                  message: failure,
                  color: context.colors.error,
                ),
              ),
              if (onRetryPreparation != null)
                IconButton(
                  tooltip: l10n.composerRetrySubmission,
                  onPressed: onRetryPreparation,
                  icon: const Icon(Icons.refresh),
                ),
              if (onAcceptConfiguration != null)
                TextButton(
                  onPressed: onAcceptConfiguration,
                  child: Text(l10n.acpDraftUseCurrentConfiguration),
                ),
            ],
          ),
      ],
    );
  }
}
