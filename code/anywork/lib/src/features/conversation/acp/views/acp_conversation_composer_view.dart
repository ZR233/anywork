import 'dart:async';

import 'package:anywork_client/models.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../../../../app/theme/studio_tokens.dart';
import '../../../../l10n/studio_l10n.dart';
import '../../../../shared/composer_action_button.dart';
import '../../../../shared/conversation_composer.dart';
import '../../../../shared/studio_chrome.dart';
import '../state/acp_view_state.dart';
import '../widgets/acp_slash_command_menu.dart';

/// Binds ACP eligibility and commands to the shared conversation editor,
/// hosting a `/` slash-command autocomplete palette above the input when
/// server-advertised commands are present.
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
  int _highlightedIndex = 0;
  String? _dismissedDraft;

  @override
  void didUpdateWidget(covariant AcpConversationComposerView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.state.threadId != widget.state.threadId) {
      _highlightedIndex = 0;
      _dismissedDraft = null;
      return;
    }
    if (oldWidget.state.draftText != widget.state.draftText) {
      _highlightedIndex = 0;
      if (_dismissedDraft != null &&
          _dismissedDraft != widget.state.draftText) {
        _dismissedDraft = null;
      }
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
      AcpComposerBlockerKind.sending || AcpComposerBlockerKind.running => null,
    };
  }

  void _selectSlashCommand(AcpSlashCommandPresentation command) {
    setState(() {
      _highlightedIndex = 0;
      _dismissedDraft = null;
    });
    widget.onDraftChanged('/${command.name} ');
  }

  KeyEventResult _handleMenuKeyEvent(
    KeyEvent event,
    List<AcpSlashCommandPresentation> filtered,
  ) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.escape) {
      setState(() => _dismissedDraft = widget.state.draftText);
      return KeyEventResult.handled;
    }
    if (filtered.isEmpty) {
      return KeyEventResult.ignored;
    }
    if (key == LogicalKeyboardKey.arrowDown) {
      setState(() {
        _highlightedIndex = (_highlightedIndex + 1) % filtered.length;
      });
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowUp) {
      setState(() {
        _highlightedIndex =
            (_highlightedIndex - 1 + filtered.length) % filtered.length;
      });
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.tab ||
        key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter) {
      final index = _highlightedIndex.clamp(0, filtered.length - 1);
      _selectSlashCommand(filtered[index]);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final state = widget.state;
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
    final pasteHandler = widget.onPasteClipboard;

    final slashQuery = state.availableCommands.isEmpty
        ? null
        : matchAcpSlashTrigger(state.draftText);
    final menuVisible =
        slashQuery != null && _dismissedDraft != state.draftText;
    final filteredCommands = menuVisible
        ? rankAcpSlashCommands(state.availableCommands, slashQuery)
        : const <AcpSlashCommandPresentation>[];
    final clampedIndex = filteredCommands.isEmpty
        ? 0
        : _highlightedIndex.clamp(0, filteredCommands.length - 1);

    final composer = ConversationComposer(
      identity: ('acp-session', state.threadId),
      text: state.draftText,
      inputKey: ValueKey(AcpViewKeyValues.composerInput(state.threadId)),
      onTextChanged: widget.onDraftChanged,
      onSubmit: canSubmit ? widget.onSubmit : null,
      onKeyEvent: menuVisible
          ? (_, event) => _handleMenuKeyEvent(event, filteredCommands)
          : null,
      compact: widget.compact,
      dragging: widget.dragging,
      configuration: widget.configurationBar,
      attachments: state.attachments,
      onRemoveAttachment: state.submitting ? null : widget.onRemoveAttachment,
      canAttach: state.canAttach,
      localCapabilities: state.localCapabilities,
      remoteCapabilities: state.remoteCapabilities,
      onPickLocal: (capabilities, isCurrent) async {
        if (isCurrent()) await widget.onPickLocalAttachments(capabilities);
      },
      onAddUrl: (url, isCurrent) async {
        if (isCurrent()) await widget.onAddRemoteAttachment(url);
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
                  ? widget.onInterrupt
                  : null
            : canSubmit
            ? widget.onSubmit
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

    // Keep Column mounted unconditionally so toggling the slash menu never
    // unmounts ConversationComposer or drops its FocusNode and cursor state.
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (menuVisible)
          AcpSlashCommandMenu(
            commands: filteredCommands,
            highlightedIndex: clampedIndex,
            onHighlightedChanged: (index) =>
                setState(() => _highlightedIndex = index),
            onSelect: _selectSlashCommand,
          )
        else
          const SizedBox.shrink(),
        composer,
      ],
    );
  }
}
