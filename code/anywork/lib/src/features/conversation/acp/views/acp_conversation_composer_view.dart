import 'dart:async';

import 'package:anywork_client/models.dart';
import 'package:material_ui/material_ui.dart';

import '../../../../app/theme/studio_tokens.dart';
import '../../../../l10n/studio_l10n.dart';
import '../../../../shared/studio_chrome.dart';
import '../../composer/widgets/composer_attachments.dart';
import '../../../../shared/composer_input_frame.dart';
import '../../composer/widgets/multiline_enter_shortcuts.dart';
import '../../composer/widgets/composer_paste_action.dart';
import '../state/acp_view_state.dart';

/// Pure ACP session composer view matching Studio's `14px` [StudioPanel]
/// aesthetic, embedding dynamic configuration controls directly in its bottom
/// toolbar alongside attachment and circular Send/Interrupt actions.
class AcpConversationComposerView extends StatefulWidget {
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

  @override
  State<AcpConversationComposerView> createState() =>
      _AcpConversationComposerViewState();
}

class _AcpConversationComposerViewState
    extends State<AcpConversationComposerView> {
  final _focus = FocusNode();
  late TextEditingController _controller = TextEditingController(
    text: widget.state.draftText,
  );

  void _submit() {
    final state = widget.state;
    if (!state.canSend ||
        state.submitting ||
        state.interrupting ||
        state.isRunning ||
        !state.hasSendableInput ||
        !_controller.value.composing.isCollapsed) {
      return;
    }
    widget.onSubmit();
  }

  @override
  void didUpdateWidget(covariant AcpConversationComposerView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.state.threadId != widget.state.threadId) {
      _controller.dispose();
      _controller = TextEditingController(text: widget.state.draftText);
      return;
    }
    // Never disturb selection or IME composing when streaming updates do not
    // change the draft text.
    if (widget.state.draftText == _controller.text) return;
    final selection = _controller.selection;
    _controller.value = TextEditingValue(
      text: widget.state.draftText,
      selection: selection.isValid
          ? TextSelection(
              baseOffset: selection.baseOffset.clamp(
                0,
                widget.state.draftText.length,
              ),
              extentOffset: selection.extentOffset.clamp(
                0,
                widget.state.draftText.length,
              ),
            )
          : TextSelection.collapsed(offset: widget.state.draftText.length),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _promptRemoteUrl(BuildContext context) async {
    final textController = TextEditingController();
    final submitted = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(dialogContext.l10n.composerAddUrlTitle),
        content: TextField(
          controller: textController,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'https://…'),
          onSubmitted: (value) => Navigator.of(dialogContext).pop(value.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(dialogContext.l10n.settingsCancel),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.of(dialogContext).pop(textController.text.trim()),
            child: Text(dialogContext.l10n.composerAddUrlConfirm),
          ),
        ],
      ),
    );
    textController.dispose();
    if (submitted != null && submitted.isNotEmpty) {
      await widget.onAddRemoteAttachment(submitted);
    }
  }

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
      AcpComposerBlockerKind.sending => null,
      // While running, the bottom status bar and stop button already indicate
      // active generation without cluttering the composer with a warning line.
      AcpComposerBlockerKind.running => null,
    };
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final state = widget.state;
    final colors = context.colors;
    final canSubmitNow =
        state.canSend &&
        state.hasSendableInput &&
        !state.submitting &&
        !state.interrupting &&
        !state.isRunning;
    final blockerText = _blockerMessage(context, state.blocker);
    final isErrorBlocker =
        state.blocker?.kind == AcpComposerBlockerKind.configError ||
        state.blocker?.kind == AcpComposerBlockerKind.disconnected;

    Widget editor = MultilineEnterShortcuts(
      controller: _controller,
      child: TextField(
        key: ValueKey(AcpViewKeyValues.composerInput(state.threadId)),
        controller: _controller,
        focusNode: _focus,
        minLines: widget.compact ? 1 : 2,
        maxLines: widget.compact ? 4 : 8,
        textInputAction: TextInputAction.send,
        onChanged: widget.onDraftChanged,
        onEditingComplete: () {},
        onSubmitted: (_) => _submit(),
        style: context.text.bodyMedium?.copyWith(height: 1.5),
        decoration: InputDecoration(
          hintText: l10n.acpComposerHint,
          hintStyle: context.text.bodyMedium?.copyWith(
            color: colors.onSurfaceVariant.withValues(alpha: 0.72),
          ),
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          disabledBorder: InputBorder.none,
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(vertical: 4),
        ),
      ),
    );

    if (widget.onPasteClipboard case final pasteHandler?) {
      editor = Actions(
        actions: <Type, Action<Intent>>{
          PasteTextIntent: ComposerPasteAction(
            canPaste: () => true,
            paste: (pasteText) {
              final controller = _controller;
              unawaited(
                pasteHandler(() async {
                  if (!mounted || !identical(_controller, controller)) return;
                  await pasteText();
                }, widget.state.supportsImagePaste),
              );
            },
          ),
        },
        child: editor,
      );
    }

    return ComposerInputFrame(
      focusNode: _focus,
      compact: widget.compact,
      dragging: widget.dragging,
      configuration: widget.configurationBar,
      attachmentAction: AttachmentMenu(
        enabled: state.canAttach,
        localCapabilities: state.localCapabilities,
        remoteCapabilities: state.remoteCapabilities,
        onPickLocal: widget.onPickLocalAttachments,
        onAddUrl: () => _promptRemoteUrl(context),
      ),
      primaryAction: _PrimaryComposerButton(
        key: ValueKey(AcpViewKeyValues.composerPrimaryAction(state.threadId)),
        isRunning: state.isRunning,
        canInterrupt: state.canInterrupt,
        canSend: canSubmitNow,
        submitting: state.submitting,
        interrupting: state.interrupting,
        disabledTooltip: blockerText,
        onSend: _submit,
        onInterrupt: widget.onInterrupt,
      ),
      body: [
        if (state.attachments.isNotEmpty)
          AttachmentDraftRail(
            attachments: state.attachments,
            enabled: !state.submitting,
            onRemove: widget.onRemoveAttachment,
          ),
        editor,
        if (blockerText != null && isErrorBlocker)
          StudioInlineMessage(
            icon: Icons.error_outline_rounded,
            message: blockerText,
            color: colors.error,
          ),
        if (state.draftError case final error?)
          StudioInlineMessage(
            icon: Icons.error_outline_rounded,
            message: error,
            color: colors.error,
          ),
      ],
    );
  }
}

class _PrimaryComposerButton extends StatelessWidget {
  const _PrimaryComposerButton({
    super.key,
    required this.isRunning,
    required this.canInterrupt,
    required this.canSend,
    required this.submitting,
    required this.interrupting,
    this.disabledTooltip,
    required this.onSend,
    required this.onInterrupt,
  });

  final bool isRunning;
  final bool canInterrupt;
  final bool canSend;
  final bool submitting;
  final bool interrupting;
  final String? disabledTooltip;
  final VoidCallback onSend;
  final VoidCallback onInterrupt;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return SizedBox.square(
      dimension: 34,
      child: IconButton.filled(
        tooltip: interrupting
            ? l10n.acpStatusStopping
            : isRunning
            ? l10n.acpComposerInterruptTooltip
            : submitting
            ? l10n.acpComposerBlockerSending
            : disabledTooltip ?? l10n.acpComposerSendTooltip,
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints.tightFor(width: 34, height: 34),
        style: IconButton.styleFrom(
          shape: const CircleBorder(),
          minimumSize: const Size.square(34),
          maximumSize: const Size.square(34),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          backgroundColor: isRunning
              ? context.colors.surfaceContainerHighest
              : null,
          foregroundColor: isRunning ? context.colors.onSurface : null,
        ),
        onPressed: submitting || interrupting
            ? null
            : isRunning
            ? canInterrupt
                  ? onInterrupt
                  : null
            : canSend
            ? onSend
            : null,
        icon: submitting || interrupting
            ? SizedBox.square(
                dimension: 15,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: context.colors.onSurfaceVariant,
                ),
              )
            : Icon(
                isRunning ? Icons.stop_rounded : Icons.arrow_upward_rounded,
                size: 18,
                color: isRunning
                    ? context.colors.onSurface
                    : canSend
                    ? context.colors.onPrimary
                    : context.colors.onSurfaceVariant.withValues(alpha: 0.38),
              ),
      ),
    );
  }
}
