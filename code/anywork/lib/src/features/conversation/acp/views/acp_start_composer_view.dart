import 'package:material_ui/material_ui.dart';

import '../../../../app/theme/studio_tokens.dart';

import '../../../../l10n/studio_l10n.dart';
import '../../../../shared/studio_chrome.dart';
import '../../composer/widgets/composer_attachments.dart';
import '../../../../shared/composer_input_frame.dart';
import '../../composer/widgets/multiline_enter_shortcuts.dart';
import '../state/acp_view_state.dart';

/// Pure start-page creation card for ACP sessions, matching the concentric
/// warm-white [StudioPanel] geometry of `PromptComposerView(creationCard: true)`.
class AcpStartComposerView extends StatefulWidget {
  const AcpStartComposerView({
    super.key,
    required this.state,
    required this.onDraftChanged,
    required this.onSubmit,
    this.modelSelector,
    this.configurationBar,
    this.onRetryPreparation,
    this.onAcceptConfiguration,
    this.onRemoveAttachment,
  });

  final AcpStartComposerViewState state;
  final ValueChanged<String> onDraftChanged;
  final VoidCallback onSubmit;
  final Widget? modelSelector;
  final Widget? configurationBar;
  final VoidCallback? onRetryPreparation;
  final VoidCallback? onAcceptConfiguration;
  final ValueChanged<String>? onRemoveAttachment;

  @override
  State<AcpStartComposerView> createState() => _AcpStartComposerViewState();
}

class _AcpStartComposerViewState extends State<AcpStartComposerView> {
  late TextEditingController _controller = TextEditingController(
    text: widget.state.text,
  );

  @override
  void didUpdateWidget(covariant AcpStartComposerView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.state.workspaceId != widget.state.workspaceId) {
      _controller.dispose();
      _controller = TextEditingController(text: widget.state.text);
      return;
    }
    if (widget.state.text == _controller.text) return;
    final selection = _controller.selection;
    _controller.value = TextEditingValue(
      text: widget.state.text,
      selection: selection.isValid
          ? TextSelection(
              baseOffset: selection.baseOffset.clamp(
                0,
                widget.state.text.length,
              ),
              extentOffset: selection.extentOffset.clamp(
                0,
                widget.state.text.length,
              ),
            )
          : TextSelection.collapsed(offset: widget.state.text.length),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    if (!widget.state.canCreate || _controller.value.composing.isValid) return;
    widget.onSubmit();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final state = widget.state;
    final colors = context.colors;

    return ComposerInputFrame(
      creationCard: true,

      configuration: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (widget.modelSelector != null) widget.modelSelector!,
          if (widget.configurationBar != null) widget.configurationBar!,
        ],
      ),
      primaryAction: IconButton.filled(
        key: ValueKey(AcpViewKeyValues.startSubmit(state.workspaceId)),
        tooltip: state.preparing
            ? l10n.acpComposerBlockerInitializing
            : state.submitting
            ? l10n.acpStartCreatingAction
            : l10n.composerSend,
        onPressed: state.canCreate ? _submit : null,
        padding: EdgeInsets.zero,
        style: IconButton.styleFrom(
          shape: const CircleBorder(),
          minimumSize: const Size.square(34),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        icon: state.submitting || state.preparing
            ? const SizedBox.square(
                dimension: 14,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.arrow_upward_rounded, size: 18),
      ),
      body: [
        if (state.stagedAttachments.isNotEmpty)
          AttachmentDraftRail(
            attachments: state.stagedAttachments,
            enabled: !state.submitting && widget.onRemoveAttachment != null,
            onRemove: (id) => widget.onRemoveAttachment?.call(id),
          ),
        MultilineEnterShortcuts(
          controller: _controller,
          child: TextField(
            key: ValueKey(AcpViewKeyValues.startInput(state.workspaceId)),
            controller: _controller,

            autofocus: true,
            enabled: state.canEditDraft,
            minLines: 3,
            maxLines: 8,
            textInputAction: TextInputAction.send,

            onChanged: widget.onDraftChanged,
            onSubmitted: (_) => _submit(),
            style: context.text.bodyMedium?.copyWith(height: 1.5),
            decoration: InputDecoration(
              hintText: l10n.composerHint,
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              disabledBorder: InputBorder.none,
              isDense: true,
              filled: false,
              contentPadding: const EdgeInsets.symmetric(vertical: 8),
            ),
          ),
        ),
        if (state.failureMessage case final failure?)
          Row(
            children: [
              Expanded(
                child: StudioInlineMessage(
                  icon: Icons.error_outline_rounded,
                  message: failure,
                  color: colors.error,
                ),
              ),
              if (widget.onRetryPreparation != null)
                IconButton(
                  tooltip: l10n.composerRetrySubmission,
                  onPressed: widget.onRetryPreparation,
                  icon: const Icon(Icons.refresh),
                ),
              if (widget.onAcceptConfiguration != null)
                TextButton(
                  onPressed: widget.onAcceptConfiguration,
                  child: Text(l10n.acpDraftUseCurrentConfiguration),
                ),
            ],
          ),
      ],
    );
  }
}
