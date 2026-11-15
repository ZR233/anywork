import 'package:material_ui/material_ui.dart';

import '../../../../app/theme/studio_tokens.dart';
import '../../../../l10n/studio_l10n.dart';
import '../../../../shared/account_brand.dart';
import '../../../../shared/studio_chrome.dart';
import '../../composer/widgets/composer_attachments.dart';
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
    this.onRemoveAttachment,
  });

  final AcpStartComposerViewState state;
  final ValueChanged<String> onDraftChanged;
  final VoidCallback onSubmit;
  final Widget? modelSelector;
  final ValueChanged<String>? onRemoveAttachment;

  @override
  State<AcpStartComposerView> createState() => _AcpStartComposerViewState();
}

class _AcpStartComposerViewState extends State<AcpStartComposerView> {
  final _focus = FocusNode();
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
    _focus.dispose();
    super.dispose();
  }

  void _submit() {
    if (!widget.state.canCreate || _controller.value.composing.isValid) return;
    widget.onSubmit();
    _focus.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final state = widget.state;
    final colors = context.colors;

    return StudioPanel(
      backgroundColor: colors.surfaceContainerLowest,
      borderColor: colors.outlineVariant,
      radius: StudioRadii.md,
      padding: const EdgeInsets.fromLTRB(14, 12, 12, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (state.stagedAttachments.isNotEmpty) ...[
            AttachmentDraftRail(
              attachments: state.stagedAttachments,
              enabled: !state.submitting && widget.onRemoveAttachment != null,
              onRemove: (id) => widget.onRemoveAttachment?.call(id),
            ),
            const SizedBox(height: 6),
          ],
          MultilineEnterShortcuts(
            controller: _controller,
            child: TextField(
              key: ValueKey(AcpViewKeyValues.startInput(state.workspaceId)),
              controller: _controller,
              focusNode: _focus,
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
          ),
          const SizedBox(height: 10),
          if (state.failureMessage case final failure?) ...[
            StudioInlineMessage(
              icon: Icons.error_outline_rounded,
              message: failure,
              color: colors.error,
            ),
            const SizedBox(height: 8),
          ],
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const Spacer(),
              if (widget.modelSelector case final selector?)
                Flexible(child: selector)
              else if (state.serviceName case final name? when name.isNotEmpty)
                Flexible(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      AccountBrandMark(
                        fallbackName: name,
                        iconKey: state.brandKey,
                        size: 18,
                        active: state.serviceEnabled,
                      ),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              const SizedBox(width: 8),
              SizedBox.square(
                dimension: 34,
                child: IconButton.filled(
                  key: ValueKey(
                    AcpViewKeyValues.startSubmit(state.workspaceId),
                  ),
                  tooltip: state.submitting
                      ? l10n.acpStartCreatingAction
                      : l10n.composerSend,
                  onPressed: state.canCreate ? _submit : null,
                  style: IconButton.styleFrom(shape: const CircleBorder()),
                  icon: state.submitting
                      ? SizedBox.square(
                          dimension: 14,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: colors.onSurfaceVariant,
                          ),
                        )
                      : Icon(
                          Icons.arrow_upward_rounded,
                          size: 18,
                          color: state.canCreate
                              ? colors.onPrimary
                              : colors.onSurfaceVariant.withValues(alpha: 0.38),
                        ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
