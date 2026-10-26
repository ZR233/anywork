import 'package:anywork_client/drafts.dart' show AttachmentMetadata;
import 'package:flutter/material.dart';

import '../../../app/theme/studio_tokens.dart';
import '../../../diagnostics/studio_driver_keys.dart';
import '../../../l10n/studio_l10n.dart';
import '../../../ui/attachments/attachment_metadata_view.dart';
import '../../../ui/layout/studio_panel.dart';
import '../state/composer_view_state.dart';
import '../state/conversation_view_state.dart';
import '../widgets/conversation_stop_control.dart';
import '../widgets/raw_text_input.dart';

class ComposerView extends StatelessWidget {
  const ComposerView({
    required this.state,
    required this.enabled,
    required this.canSend,
    required this.running,
    this.onText,
    this.onSend,
    this.onAddLocal,
    this.onAddUrl,
    this.attachmentState,
    this.onRemove,
    this.onOpenAttachment,
    this.attachmentCard,
    this.onPaste,
    this.onStop,
    this.stopState,
    this.selectors,
    this.preparation,
    this.compact = false,
    this.dragging = false,
    super.key,
  }) : assert(state != null || (!enabled && !canSend && !running));

  /// No target means no logical draft, rather than a fabricated project key.
  final ComposerViewState? state;
  final bool enabled;
  final bool canSend;
  final bool running;
  final bool compact;

  /// A file drag hovers this composer. Presentation only: admission stays with
  /// the connector's platform adapter.
  final bool dragging;
  final ValueChanged<String>? onText;
  final VoidCallback? onSend;
  final VoidCallback? onStop;
  final ConversationStopState? stopState;
  final VoidCallback? onAddLocal;
  final VoidCallback? onAddUrl;
  final ComposerAttachmentState? attachmentState;
  final ValueChanged<String>? onRemove;
  final ValueChanged<String>? onOpenAttachment;

  /// Smart-owned rail card. The connector supplies it so a card can borrow the
  /// draft binary read without the view knowing any repository.
  final Widget Function(AttachmentMetadata attachment)? attachmentCard;
  final Future<String?> Function()? onPaste;
  final Widget? selectors;
  final Widget? preparation;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final value = state;
    final attachments = value?.attachments ?? const <AttachmentMetadata>[];
    final stop = running && value?.hasInput != true;
    final pending = stop ? stopState?.pending == true : value?.pending == true;
    final errorText = value == null
        ? null
        : value.error?.message ??
              value.platformError?.message ??
              attachmentState?.error?.message ??
              value.inputIssue?.message;
    final submissionFailure = value?.submissionFailure;
    return SafeArea(
      top: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ?preparation,
          StudioPanel(
            backgroundColor: colors.surfaceContainerLowest,
            borderColor: dragging
                ? colors.primary
                : colors.outlineVariant.withValues(alpha: 0.86),
            radius: StudioRadii.lg,
            shadow: false,
            padding: compact
                ? const EdgeInsets.fromLTRB(12, 6, 10, 6)
                : const EdgeInsets.fromLTRB(12, 8, 10, 10),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (attachments.isNotEmpty)
                  _AttachmentDraftRail(
                    attachments: attachments,
                    enabled: enabled,
                    onOpen: onOpenAttachment,
                    onRemove: onRemove,
                    cardBuilder: attachmentCard,
                  ),
                RawTextInput(
                  raw: value?.text ?? '',
                  onChanged: onText,
                  enabled: enabled,
                  minLines: compact ? 2 : 3,
                  maxLines: 8,
                  canSubmit: canSend,
                  onSubmit: onSend,
                  onStop: onStop,
                  onPaste: onPaste,
                  inputKey: StudioDriverKeys.composerInput,
                  decoration: InputDecoration(
                    hintText: context.l10n.composerHint,
                    hintStyle: TextStyle(color: colors.onSurfaceVariant),
                    isDense: true,
                    filled: false,
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(vertical: 8),
                  ),
                ),
                if (errorText != null)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(12, 2, 8, 6),
                      child: Text(
                        errorText,
                        key: StudioDriverKeys.composerError,
                        style: Theme.of(context).textTheme.bodySmall
                            ?.copyWith(color: colors.error),
                      ),
                    ),
                  ),
                if (submissionFailure != null &&
                    submissionFailure != value?.error)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(12, 2, 8, 6),
                      child: Text(
                        submissionFailure.message,
                        style: Theme.of(context).textTheme.bodySmall
                            ?.copyWith(color: colors.error),
                      ),
                    ),
                  ),
                ConversationStopStatus(state: stopState),
                Row(
                  children: [
                    _AttachmentMenu(
                      enabled: enabled,
                      local: attachmentState?.local.isNotEmpty == true,
                      remote: attachmentState?.remote.isNotEmpty == true,
                      onPickLocal: onAddLocal,
                      onAddUrl: onAddUrl,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Wrap(
                        alignment: WrapAlignment.end,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: 2,
                        runSpacing: 4,
                        children: [?selectors],
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton.filled(
                      key: stop
                          ? StudioDriverKeys.composerStop
                          : canSend
                          ? StudioDriverKeys.composerSubmit
                          : const ValueKey('composer-submit-disabled'),
                      tooltip: stop
                          ? context.l10n.composerStop
                          : running
                          ? context.l10n.composerSendAndContinue
                          : context.l10n.composerSend,
                      onPressed: stop
                          ? onStop
                          : canSend
                          ? onSend
                          : null,
                      style: IconButton.styleFrom(
                        fixedSize: const Size.square(40),
                        shape: const CircleBorder(),
                        backgroundColor: stop
                            ? colors.surfaceContainerHighest
                            : colors.primary,
                        foregroundColor: stop
                            ? colors.onSurface
                            : colors.onPrimary,
                        disabledBackgroundColor: colors.surfaceContainerHighest,
                        disabledForegroundColor: colors.onSurface.withValues(
                          alpha: 0.32,
                        ),
                      ),
                      icon: pending
                          ? const SizedBox.square(
                              key: StudioDriverKeys.composerPending,
                              dimension: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Icon(
                              stop
                                  ? Icons.stop_rounded
                                  : Icons.arrow_upward_rounded,
                            ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The pre-refactor attachment entry: one anchor, two explicit sources.
class _AttachmentMenu extends StatefulWidget {
  const _AttachmentMenu({
    required this.enabled,
    required this.local,
    required this.remote,
    required this.onPickLocal,
    required this.onAddUrl,
  });

  final bool enabled;
  final bool local;
  final bool remote;
  final VoidCallback? onPickLocal;
  final VoidCallback? onAddUrl;

  @override
  State<_AttachmentMenu> createState() => _AttachmentMenuState();
}

class _AttachmentMenuState extends State<_AttachmentMenu> {
  final MenuController _controller = MenuController();

  @override
  Widget build(BuildContext context) {
    final hasAny = widget.local || widget.remote;
    return MenuAnchor(
      key: StudioDriverKeys.attachmentEntry,
      controller: _controller,
      alignmentOffset: const Offset(6, 6),
      menuChildren: [
        if (widget.local)
          MenuItemButton(
            key: StudioDriverKeys.attachmentLocal,
            overflowAxis: Axis.vertical,
            onPressed: widget.enabled ? widget.onPickLocal : null,
            child: ListTile(
              leading: const Icon(Icons.folder_open_outlined),
              title: Text(context.l10n.composerAttachmentPickLocal),
            ),
          ),
        if (widget.remote)
          MenuItemButton(
            key: StudioDriverKeys.attachmentUrl,
            overflowAxis: Axis.vertical,
            onPressed: widget.enabled ? widget.onAddUrl : null,
            child: ListTile(
              leading: const Icon(Icons.link),
              title: Text(context.l10n.composerAddUrlTitle),
            ),
          ),
      ],
      child: IconButton(
        tooltip: hasAny
            ? context.l10n.composerAttachmentAddTooltip
            : context.l10n.composerAttachmentUnsupportedTooltip,
        onPressed: widget.enabled && hasAny
            ? () {
                if (_controller.isOpen) {
                  _controller.close();
                } else {
                  _controller.open();
                }
              }
            : null,
        icon: const Icon(Icons.attach_file),
      ),
    );
  }
}

/// One fixed-height horizontal rail: 210px cards, 48px thumbnail, 8px gap.
class _AttachmentDraftRail extends StatelessWidget {
  const _AttachmentDraftRail({
    required this.attachments,
    required this.enabled,
    this.onOpen,
    this.onRemove,
    this.cardBuilder,
  });

  final List<AttachmentMetadata> attachments;
  final bool enabled;
  final ValueChanged<String>? onOpen;
  final ValueChanged<String>? onRemove;
  final Widget Function(AttachmentMetadata attachment)? cardBuilder;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      key: StudioDriverKeys.attachmentDraftRail,
      height: 72,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: attachments.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final attachment = attachments[index];
          final card =
              cardBuilder?.call(attachment) ??
              AttachmentMetadataView(
                attachment: attachment,
                enabled: enabled,
                onOpen: onOpen,
                onRemove: onRemove,
                modalityKey: StudioDriverKeys.attachmentModality(attachment.id),
                removeKey: StudioDriverKeys.attachmentRemove(attachment.id),
              );
          return SizedBox(
            key: StudioDriverKeys.attachmentDraft(attachment.id),
            width: 210,
            child: card,
          );
        },
      ),
    );
  }
}
