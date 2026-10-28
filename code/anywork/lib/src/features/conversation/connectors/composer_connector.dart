import 'package:anywork_client/conversation.dart' show studioFailureReason;
import 'package:anywork_client/drafts.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/app_bindings.dart';
import '../../../l10n/studio_l10n.dart';
import '../../../platform/clipboard_image_reader.dart';
import '../../../platform/dropped_attachments.dart';
import '../../../platform/local_file_dialogs.dart';
import '../state/composer_primary_action.dart';
import '../state/composer_view_state.dart';
import '../state/conversation_view_state.dart';
import '../state/editor_keys.dart';
import '../view_models/composer_attachment_view_model.dart';
import '../view_models/composer_view_model.dart';
import '../view_models/conversation_view_model.dart';
import '../views/composer_view.dart';
import '../widgets/raw_text_input.dart';
import 'attachment_image_connector.dart';
import 'draft_attachment_rail_item.dart';

/// Platform adapters are captured alongside the original VM synchronously.
/// D1, not this widget, owns admission, bytes, frozen submissions and cleanup.
class ComposerConnector extends ConsumerWidget {
  const ComposerConnector({
    required this.target,
    this.compact = false,
    this.onStop,
    this.stopState,
    super.key,
  });
  const ComposerConnector.disabled({this.compact = false, super.key})
    : target = null,
      onStop = null,
      stopState = null;
  final ComposerKey? target;
  final bool compact;
  final VoidCallback? onStop;
  final ConversationStopState? stopState;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final target = this.target;
    if (target == null) {
      return ComposerView(
        state: null,
        enabled: false,
        primaryAction: const ComposerPrimaryAction(
          kind: ComposerPrimaryActionKind.send,
          enabled: false,
        ),
        compact: compact,
      );
    }
    final provider = composerViewModelProvider(target);
    final value = ref.watch(provider);
    final vm = ref.read(provider.notifier);
    final capabilityProvider = composerAttachmentViewModelProvider(target);
    final capabilities = ref.watch(capabilityProvider).value;
    final capabilityVm = ref.read(capabilityProvider.notifier);
    final drafts = ref.read(draftsRepositoryProvider);
    final clipboard = ref.read(clipboardImageReaderProvider);
    final conversation = switch (target) {
      ThreadComposerKey(:final threadId) =>
        ref.watch(conversationViewModelProvider(threadId)).value,
      StartComposerKey() => null,
    };
    return value.when(
      loading: () => const LinearProgressIndicator(),
      error: (error, stack) => const Icon(Icons.error_outline),
      data: (state) {
        final ownsAttachmentTarget = vm.captureAttachmentTarget();
        bool allowsLocal() =>
            ownsAttachmentTarget() && capabilityVm.allowsLocal(capabilities);
        bool allowsRemote() =>
            ownsAttachmentTarget() && capabilityVm.allowsRemote(capabilities);
        Future<void> admitLocal(List<String> paths) async {
          if (!allowsLocal()) return;
          await vm.addLocalFiles(paths);
        }

        final editable =
            (target is StartComposerKey || conversation?.canCompose == true) &&
            !state.closing &&
            !state.platformPending;
        final submissionPending =
            state.pending ||
            state.platformPending ||
            state.submission is UnknownDraftSubmission ||
            state.submission is SubmittingDraft;
        final conversationVm = target is ThreadComposerKey
            ? ref.read(conversationViewModelProvider(target.threadId).notifier)
            : null;
        final primaryAction =
            conversationVm?.primaryAction(
              hasContent: state.hasInput,
              submissionPending: submissionPending,
            ) ??
            ComposerPrimaryAction.resolve(
              isChild: false,
              execution: null,
              continuation: null,
              hasContent: state.hasInput,
              submissionPending: submissionPending,
              stopAccepted: false,
              continuationAccepted: false,
            ).copyWith(
              enabled: editable && !submissionPending && state.hasInput,
            );
        final continueAction = conversationVm?.captureContinuation();
        final readContinuation = conversationVm?.captureContinuationRead();
        final failure =
            state.submissionFailure ??
            state.error ??
            conversation?.continuation?.error;
        final point = conversation?.execution?.value?.continuation;
        void continueConversation() {
          final latest = ref.read(provider).value;
          if (latest == null ||
              latest.hasInput ||
              latest.pending ||
              latest.platformPending ||
              !identical(ref.read(provider.notifier), vm)) {
            return;
          }
          continueAction?.call().ignore();
        }

        void removeAttachment(String id) => vm.removeAttachment(id).ignore();
        void openAttachment(String id) {
          final attachment = state.attachments
              .where((item) => item.id == id)
              .firstOrNull;
          if (attachment == null) return;
          if (attachment.modality == AttachmentModality.image) {
            openAttachmentImage(
              context,
              title: attachment.filename,
              read: () => drafts.readDraftAttachment(id),
            ).ignore();
          } else {
            showDialog<void>(
              context: context,
              builder: (context) => AlertDialog(
                title: Text(attachment.filename),
                content: Text(
                  '${attachment.mediaType} · ${attachment.byteSize} bytes',
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text(
                      MaterialLocalizations.of(context).closeButtonLabel,
                    ),
                  ),
                ],
              ),
            ).ignore();
          }
        }

        return _ComposerDropSurface(
          enabled: editable && capabilities?.local.isNotEmpty == true,
          onDrop: (details) async {
            if (!allowsLocal()) return;
            final files = details.items.whereType<DropFileItem>().toList(
              growable: false,
            );
            await vm.withPlatformRead<void>(
              () => admitDroppedAttachments(files, admitLocal),
            );
          },
          builder: (dragging) => ComposerView(
            key: ValueKey(target),
            state: state,
            attachmentState: capabilities,
            enabled: editable,
            dragging: dragging,
            primaryAction: primaryAction,
            compact: compact,
            onText: vm.setText,
            onSend: () => vm.send().ignore(),
            onStop: onStop,
            stopState: stopState,
            continuationState: conversation?.continuation,
            failure: failure == null
                ? null
                : ComposerFailureBlocker(studioFailureReason(failure)),
            continuationNote:
                point != null &&
                    conversation?.execution?.value?.execution == null
                ? context.composerContinuationReasonLabel(point.reason)
                : null,
            onContinue: continueAction == null ? null : continueConversation,
            onReadContinuation: readContinuation == null
                ? null
                : () => readContinuation().ignore(),
            onAddLocal: () {
              if (!allowsLocal()) return;
              final extensions = capabilities!.localExtensions;
              vm.withPlatformRead<void>(() async {
                final paths = await pickLocalAttachmentPaths(
                  extensions: extensions,
                );
                if (paths.isNotEmpty) {
                  await admitLocal(paths);
                }
              }).ignore();
            },
            onPaste: () => vm.withPlatformRead<String?>(() async {
              final image = await clipboard.readImage();
              if (image != null) {
                await vm.addClipboardImage(image);
                return null;
              }
              return clipboard.readText();
            }),
            onAddUrl: () {
              if (!allowsRemote()) return;
              vm
                  .withPlatformRead<void>(
                    () => showDialog<void>(
                      context: context,
                      builder: (_) => _ComposerUrlConnector(
                        target: target,
                        owner: vm,
                        initial: state,
                        ownsTarget: ownsAttachmentTarget,
                        allowsAdmission: allowsRemote,
                      ),
                    ),
                  )
                  .ignore();
            },
            onRemove: removeAttachment,
            onOpenAttachment: openAttachment,
            attachmentCard: (attachment) => DraftAttachmentRailItem(
              attachment: attachment,
              enabled: editable,
              onOpen: openAttachment,
              onRemove: removeAttachment,
              read: () => drafts.readDraftAttachment(attachment.id),
            ),
            preparation: _preparation(context, state),
          ),
        );
      },
    );
  }

  Widget? _preparation(BuildContext context, ComposerViewState state) {
    final preparation = state.startDraft?.preparation;
    if (preparation == null) return null;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (preparation.phase == NewThreadPreparationPhase.preparing)
          const LinearProgressIndicator(),
        if (preparation.progress case final progress?) ...[
          Text(progress.stage.name),
          if (progress.workspacePath != null) Text(progress.workspacePath!),
          if (progress.branch != null) Text(progress.branch!),
        ],
        if (preparation.failure != null) Text(preparation.failure!.message),
      ],
    );
  }
}

/// Drop admission stays with this connector; only the hover flag the composer
/// renders is local, exactly as the pre-refactor composer panel did.
class _ComposerDropSurface extends StatefulWidget {
  const _ComposerDropSurface({
    required this.enabled,
    required this.onDrop,
    required this.builder,
  });

  final bool enabled;
  final Future<void> Function(DropDetails details) onDrop;
  final Widget Function(bool dragging) builder;

  @override
  State<_ComposerDropSurface> createState() => _ComposerDropSurfaceState();
}

class _ComposerDropSurfaceState extends State<_ComposerDropSurface> {
  bool _dragging = false;

  @override
  Widget build(BuildContext context) => DropTarget(
    enabled: widget.enabled,
    acceptedKinds: const {DropItemKind.file},
    onEnter: (_) => setState(() => _dragging = true),
    onLeave: () {
      if (_dragging) setState(() => _dragging = false);
    },
    onDrop: widget.onDrop,
    child: widget.builder(_dragging && widget.enabled),
  );
}

class _ComposerUrlConnector extends ConsumerStatefulWidget {
  const _ComposerUrlConnector({
    required this.target,
    required this.owner,
    required this.initial,
    required this.ownsTarget,
    required this.allowsAdmission,
  });
  final ComposerKey target;
  final ComposerViewModel owner;
  final ComposerViewState initial;
  final bool Function() ownsTarget;
  final bool Function() allowsAdmission;
  @override
  ConsumerState<_ComposerUrlConnector> createState() =>
      _ComposerUrlConnectorState();
}

class _ComposerUrlConnectorState extends ConsumerState<_ComposerUrlConnector> {
  late ComposerViewState _shown = widget.initial;
  @override
  Widget build(BuildContext context) {
    final provider = composerViewModelProvider(widget.target);
    final value = ref.watch(provider);
    // This dialog is a separate route. Reuse the same capability observation
    // for rebuilds; admission still validates the original captured snapshot.
    ref.watch(composerAttachmentViewModelProvider(widget.target));
    final original =
        identical(ref.read(provider.notifier), widget.owner) &&
        widget.ownsTarget();
    if (original && value.asData != null) _shown = value.requireValue;
    final state = _shown;
    final enabled = original && !state.pending;
    void admit() {
      if (!widget.ownsTarget() || !widget.allowsAdmission()) return;
      widget.owner.addRemoteUrl().ignore();
    }

    return AlertDialog(
      title: Text(context.l10n.composerAddUrlTitle),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            RawTextInput(
              raw: state.urlRaw,
              onChanged: original ? widget.owner.setUrl : null,
              enabled: enabled,
              onSubmit: admit,
              canSubmit: enabled && widget.allowsAdmission(),
              decoration: const InputDecoration(hintText: 'https://'),
            ),
            if (state.error != null) Text(state.error!.message),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(MaterialLocalizations.of(context).cancelButtonLabel),
        ),
        TextButton(
          onPressed: enabled && widget.allowsAdmission() ? admit : null,
          child: Text(context.l10n.composerAddUrlConfirm),
        ),
      ],
    );
  }
}
