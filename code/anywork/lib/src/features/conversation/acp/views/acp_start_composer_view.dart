import 'package:material_ui/material_ui.dart';

import '../../../../app/theme/studio_tokens.dart';
import '../../../../l10n/studio_l10n.dart';
import '../../../../shared/account_brand.dart';
import '../../../../shared/studio_chrome.dart';
import '../../composer/widgets/composer_attachments.dart';
import '../../composer/widgets/multiline_enter_shortcuts.dart';
import '../state/acp_view_state.dart';

void _ignoreAttachmentRemove(String _) {}

/// Pure start-page creation card for ACP sessions, matching the concentric
/// warm-white [StudioPanel] geometry of `PromptComposerView(creationCard: true)`.
class AcpStartComposerView extends StatefulWidget {
  const AcpStartComposerView({
    super.key,
    required this.state,
    required this.onDraftChanged,
    required this.onSubmit,
  });

  final AcpStartComposerViewState state;
  final ValueChanged<String> onDraftChanged;
  final VoidCallback onSubmit;

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
              enabled: false,
              onRemove: _ignoreAttachmentRemove,
            ),
            const SizedBox(height: 6),
            StudioInlineMessage(
              icon: Icons.info_outline_rounded,
              message: l10n.acpStartExistingAttachmentsHint,
            ),
            const SizedBox(height: 8),
          ],
          MultilineEnterShortcuts(
            controller: _controller,
            child: TextField(
              key: ValueKey(AcpViewKeyValues.startInput(state.workspaceId)),
              controller: _controller,
              enabled: state.canEditDraft,
              minLines: 3,
              maxLines: 8,
              textInputAction: TextInputAction.send,
              onChanged: widget.onDraftChanged,
              onSubmitted: (_) {
                if (state.canCreate) {
                  widget.onSubmit();
                }
              },
              style: context.text.bodyMedium?.copyWith(height: 1.5),
              decoration: InputDecoration(
                hintText: l10n.acpStartDraftHint,
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
          if (state.isRemoteSsh) ...[
            StudioInlineMessage(
              icon: Icons.lan_outlined,
              message: l10n.acpStartSshUnsupported,
              color: StudioTone.warning.foreground(context),
            ),
            const SizedBox(height: 8),
          ],
          if (state.failureMessage case final failure?) ...[
            StudioInlineMessage(
              icon: Icons.error_outline_rounded,
              message: failure,
              color: colors.error,
            ),
            const SizedBox(height: 8),
          ],
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              if (state.serviceName case final name? when name.isNotEmpty) ...[
                AccountBrandMark(
                  fallbackName: name,
                  iconKey: state.brandKey,
                  size: 22,
                  active: true,
                ),
                const SizedBox(width: 8),
              ],
              Expanded(
                child: Text(
                  l10n.acpStartHandshakeNote,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: context.text.labelSmall?.copyWith(
                    color: colors.onSurfaceVariant,
                    height: 1.35,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              FilledButton.icon(
                key: ValueKey(AcpViewKeyValues.startSubmit(state.workspaceId)),
                onPressed: state.canCreate ? widget.onSubmit : null,
                icon: state.submitting
                    ? SizedBox.square(
                        dimension: 14,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: colors.onPrimary,
                        ),
                      )
                    : const Icon(Icons.arrow_forward_rounded, size: 16),
                label: Text(
                  state.submitting
                      ? l10n.acpStartCreatingAction
                      : l10n.acpStartCreateAction,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
