import 'dart:async';

import 'package:anywork_client/models.dart';
import 'package:material_ui/material_ui.dart';

import '../../../../app/theme/studio_tokens.dart';
import '../../../../l10n/studio_l10n.dart';
import '../../../../shared/composer_action_button.dart';
import '../../../../shared/conversation_composer.dart';
import '../../../../shared/studio_chrome.dart';
import '../state/acp_view_state.dart';

/// Binds ACP eligibility and commands to the shared conversation editor.
class AcpConversationComposerView extends StatelessWidget {
  const AcpConversationComposerView({
    super.key,
    required this.state,
    required this.onDraftChanged,
    required this.onSubmit,
    required this.onInterrupt,
    required this.onPickLocalAttachments,
    required this.onAddRemoteAttachment,
    required this.onRemoveAttachment,
    this.configurationBar,
    this.onPasteClipboard,
    this.compact = false,
    this.dragging = false,
  });

  final AcpComposerViewState state;
  final ValueChanged<String> onDraftChanged;
  final VoidCallback onSubmit;
  final VoidCallback onInterrupt;
  final Future<void> Function(List<ModelInputCapabilityView>)
  onPickLocalAttachments;
  final Future<void> Function(String url) onAddRemoteAttachment;
  final ValueChanged<String> onRemoveAttachment;
  final Widget? configurationBar;
  final Future<void> Function(
    Future<void> Function() pasteText,
    bool supportsImages,
  )?
  onPasteClipboard;
  final bool compact;
  final bool dragging;

  String? _blockerMessage(BuildContext context, AcpComposerBlocker? blocker) {
    if (blocker == null) return null;
    final l10n = context.l10n;
    return switch (blocker.kind) {
      AcpComposerBlockerKind.opening => l10n.acpComposerBlockerOpening,
      AcpComposerBlockerKind.disconnected =>
        l10n.acpComposerBlockerDisconnected,
      AcpComposerBlockerKind.observationEnded => l10n.acpComposerBlockerEnded,
      AcpComposerBlockerKind.initializing =>
        l10n.acpComposerBlockerInitializing,
      AcpComposerBlockerKind.notReady => l10n.acpComposerBlockerNotReady,
      AcpComposerBlockerKind.configPending =>
        l10n.acpComposerBlockerConfigPending,
      AcpComposerBlockerKind.configError => l10n.acpComposerBlockerConfigError(
        blocker.detail ?? '',
      ),
      AcpComposerBlockerKind.sending || AcpComposerBlockerKind.running => null,
    };
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final canSubmit =
        state.canSend &&
        state.hasSendableInput &&
        !state.submitting &&
        !state.interrupting &&
        !state.isRunning;
    final blockerText = _blockerMessage(context, state.blocker);
    final isErrorBlocker =
        state.blocker?.kind == AcpComposerBlockerKind.configError ||
        state.blocker?.kind == AcpComposerBlockerKind.disconnected;
    final pasteHandler = onPasteClipboard;
    return ConversationComposer(
      identity: ('acp-session', state.threadId),
      text: state.draftText,
      inputKey: ValueKey(AcpViewKeyValues.composerInput(state.threadId)),
      onTextChanged: onDraftChanged,
      onSubmit: canSubmit ? onSubmit : null,
      compact: compact,
      dragging: dragging,
      configuration: configurationBar,
      attachments: state.attachments,
      onRemoveAttachment: state.submitting ? null : onRemoveAttachment,
      canAttach: state.canAttach,
      localCapabilities: state.localCapabilities,
      remoteCapabilities: state.remoteCapabilities,
      onPickLocal: (capabilities, isCurrent) async {
        if (isCurrent()) await onPickLocalAttachments(capabilities);
      },
      onAddUrl: (url, isCurrent) async {
        if (isCurrent()) await onAddRemoteAttachment(url);
      },
      onPaste: pasteHandler == null
          ? null
          : (pasteText, isCurrent) {
              unawaited(
                pasteHandler(() async {
                  if (isCurrent()) await pasteText();
                }, state.supportsImagePaste),
              );
            },
      primaryAction: ComposerActionPresentation(
        buttonKey: ValueKey(
          AcpViewKeyValues.composerPrimaryAction(state.threadId),
        ),
        state: state.submitting || state.interrupting
            ? ComposerActionButtonState.busy
            : state.isRunning
            ? ComposerActionButtonState.stop
            : ComposerActionButtonState.send,
        tooltip: state.interrupting
            ? l10n.acpStatusStopping
            : state.isRunning
            ? l10n.acpComposerInterruptTooltip
            : state.submitting
            ? l10n.acpComposerBlockerSending
            : blockerText ?? l10n.acpComposerSendTooltip,
        onPressed: state.isRunning
            ? state.canInterrupt
                  ? onInterrupt
                  : null
            : canSubmit
            ? onSubmit
            : null,
      ),
      diagnostics: [
        if (blockerText != null && isErrorBlocker)
          StudioInlineMessage(
            icon: Icons.error_outline_rounded,
            message: blockerText,
            color: context.colors.error,
          ),
        if (state.draftError case final error?)
          StudioInlineMessage(
            icon: Icons.error_outline_rounded,
            message: error,
            color: context.colors.error,
          ),
      ],
    );
  }
}
