import 'package:anywork_client/conversation.dart' show studioFailureReason;
import 'package:anywork_client/drafts.dart' show AttachmentMetadata;
import 'package:flutter/material.dart';

import '../../../app/theme/studio_tokens.dart';
import '../../../diagnostics/studio_driver_keys.dart';
import '../../../l10n/studio_l10n.dart';
import '../../../ui/attachments/attachment_metadata_view.dart';
import '../../../ui/layout/studio_panel.dart';
import '../state/composer_view_state.dart';
import '../state/composer_primary_action.dart';
import '../state/conversation_view_state.dart';
import '../widgets/raw_text_input.dart';

class ComposerView extends StatelessWidget {
  const ComposerView({
    required this.state,
    required this.enabled,
    required this.primaryAction,
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
    this.continuationState,
    this.onContinue,
    this.onReadContinuation,
    this.failure,
    this.continuationNote,
    this.selectors,
    this.preparation,
    this.compact = false,
    this.dragging = false,
    super.key,
  }) : assert(state != null || !enabled);

  /// No target means no logical draft, rather than a fabricated project key.
  final ComposerViewState? state;
  final bool enabled;
  final ComposerPrimaryAction primaryAction;
  final bool compact;

  /// A file drag hovers this composer. Presentation only: admission stays with
  /// the connector's platform adapter.
  final bool dragging;
  final ValueChanged<String>? onText;
  final VoidCallback? onSend;
  final VoidCallback? onStop;
  final ConversationStopState? stopState;
  final ConversationContinuationState? continuationState;
  final VoidCallback? onContinue;
  final VoidCallback? onReadContinuation;
  final ComposerBlocker? failure;
  final String? continuationNote;
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
    if (primaryAction.kind == ComposerPrimaryActionKind.readOnly) {
      return const SizedBox.shrink();
    }
    final colors = Theme.of(context).colorScheme;
    final value = state;
    final attachments = value?.attachments ?? const <AttachmentMetadata>[];
    final kind = primaryAction.kind;
    final stop = kind == ComposerPrimaryActionKind.stop;
    final pending =
        kind == ComposerPrimaryActionKind.stopping ||
        kind == ComposerPrimaryActionKind.continuing ||
        (kind == ComposerPrimaryActionKind.send ||
                kind == ComposerPrimaryActionKind.sendAndContinue) &&
            value?.pending == true ||
        // The original request is really in flight; the spinner is not a claim
        // that Stop has been accepted or that execution is already stopping.
        (stopState?.pending == true &&
            stopState?.unknown != true &&
            stopState?.accepted != true);
    final onPrimary = switch (kind) {
      ComposerPrimaryActionKind.stop => onStop,
      ComposerPrimaryActionKind.continueConversation => onContinue,
      ComposerPrimaryActionKind.send ||
      ComposerPrimaryActionKind.sendAndContinue => onSend,
      _ => null,
    };
    final primaryTooltip = switch (kind) {
      ComposerPrimaryActionKind.stop => context.l10n.composerStop,
      ComposerPrimaryActionKind.stopping => context.l10n.composerStopping,
      ComposerPrimaryActionKind.continueConversation =>
        context.l10n.composerContinueTooltip,
      ComposerPrimaryActionKind.continuing => context.l10n.composerContinuing,
      ComposerPrimaryActionKind.sendAndContinue =>
        context.l10n.composerSendAndContinue,
      _ => context.l10n.composerSend,
    };
    final primaryKey = switch (kind) {
      ComposerPrimaryActionKind.stop => StudioDriverKeys.composerStop,
      ComposerPrimaryActionKind.stopping => const ValueKey(
        'composer-stopping-disabled',
      ),
      ComposerPrimaryActionKind.continueConversation =>
        StudioDriverKeys.composerContinue,
      ComposerPrimaryActionKind.continuing => const ValueKey(
        'composer-continuing-disabled',
      ),
      _ =>
        primaryAction.enabled
            ? StudioDriverKeys.composerSubmit
            : const ValueKey('composer-submit-disabled'),
    };
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
                  canSubmit: primaryAction.enterSubmits,
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
                ?_reasonRegion(context),
                if (continuationState?.unknown == true)
                  TextButton(
                    onPressed: continuationState?.reading == true
                        ? null
                        : onReadContinuation,
                    child: Text(context.l10n.modelDetailRetry),
                  ),
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
                    if (kind == ComposerPrimaryActionKind.stopping ||
                        kind == ComposerPrimaryActionKind.continuing) ...[
                      Text(
                        kind == ComposerPrimaryActionKind.stopping
                            ? context.l10n.composerStopping
                            : context.l10n.composerContinuing,
                        key: kind == ComposerPrimaryActionKind.stopping
                            ? StudioDriverKeys.composerStopping
                            : StudioDriverKeys.composerContinuing,
                        style: Theme.of(context).textTheme.labelMedium
                            ?.copyWith(color: colors.onSurfaceVariant),
                      ),
                      const SizedBox(width: 8),
                    ],
                    if (kind == ComposerPrimaryActionKind.continueConversation)
                      Tooltip(
                        message: context.l10n.composerContinueTooltip,
                        child: FilledButton.icon(
                          key: StudioDriverKeys.composerContinue,
                          icon: const Icon(Icons.play_arrow_rounded, size: 18),
                          label: Text(context.l10n.composerContinue),
                          onPressed: primaryAction.enabled ? onContinue : null,
                        ),
                      )
                    else
                      IconButton.filled(
                        key: primaryKey,
                        tooltip: primaryTooltip,
                        onPressed: primaryAction.enabled ? onPrimary : null,
                        style: IconButton.styleFrom(
                          fixedSize: const Size.square(40),
                          shape: const CircleBorder(),
                          backgroundColor: stop
                              ? colors.surfaceContainerHighest
                              : colors.primary,
                          foregroundColor: stop
                              ? colors.onSurface
                              : colors.onPrimary,
                          disabledBackgroundColor:
                              colors.surfaceContainerHighest,
                          disabledForegroundColor: colors.onSurface.withValues(
                            alpha: 0.32,
                          ),
                        ),
                        icon: pending
                            ? const SizedBox.square(
                                key: StudioDriverKeys.composerPending,
                                dimension: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
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

  /// Main's three independent reason lanes keep their keys and bounded layout;
  /// a canonical prerequisite never hides the previous failure or interruption.
  Widget? _reasonRegion(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    Widget line(String text, Key key, {bool emphasized = true}) => Text(
      text,
      key: key,
      maxLines: 3,
      overflow: TextOverflow.ellipsis,
      style: Theme.of(context).textTheme.bodySmall?.copyWith(
        color: emphasized ? colors.error : colors.onSurfaceVariant,
      ),
    );
    final blocker = primaryAction.blocker;
    final previousFailure =
        failure ?? (blocker is ComposerFailureBlocker ? blocker : null);
    final stopFailure = stopState?.failure;
    final lines = <Widget>[
      if (blocker != null && blocker is! ComposerFailureBlocker)
        line(
          context.composerBlockerLabel(blocker),
          StudioDriverKeys.composerBlocker,
        ),
      if (previousFailure != null)
        line(
          context.composerBlockerLabel(previousFailure),
          const ValueKey('composer-failure'),
        ),
      if (stopFailure != null)
        line(
          context.composerFailureReasonLabel(studioFailureReason(stopFailure)),
          const ValueKey('composer-stop-failure'),
        ),
      if (stopState?.unknown == true)
        line(
          context.l10n.conversationStopUnknown,
          const ValueKey('composer-stop-unconfirmed'),
          emphasized: false,
        ),
      if (continuationNote != null)
        line(
          continuationNote!,
          const ValueKey('composer-continuation-reason'),
          emphasized: false,
        ),
      if (continuationState?.unknown == true)
        line(
          context.l10n.composerBlockerUnknown,
          const ValueKey('composer-continuation-unknown'),
          emphasized: false,
        ),
    ];
    if (lines.isEmpty) return null;
    return Align(
      alignment: Alignment.centerLeft,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 2, 8, 6),
        child: ConstrainedBox(
          key: const ValueKey('composer-reasons'),
          constraints: const BoxConstraints(maxHeight: 84),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: lines,
            ),
          ),
        ),
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
