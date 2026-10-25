import 'package:anywork_client/drafts.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/app_bindings.dart';
import '../../../l10n/studio_l10n.dart';
import '../../../platform/clipboard_image_reader.dart';
import '../../../platform/dropped_attachments.dart';
import '../../../platform/local_file_dialogs.dart';
import '../state/composer_view_state.dart';
import '../state/conversation_view_state.dart';
import '../state/editor_keys.dart';
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
        canSend: false,
        running: false,
        compact: compact,
      );
    }
    final provider = composerViewModelProvider(target);
    final value = ref.watch(provider);
    final vm = ref.read(provider.notifier);
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
        final editable =
            (target is StartComposerKey || conversation?.canCompose == true) &&
            !state.closing &&
            !state.pending &&
            !state.platformPending;
        final canSend =
            editable &&
            state.hasInput &&
            state.submission is! UnknownDraftSubmission &&
            state.submission is! SubmittingDraft;
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
          enabled: editable,
          onDrop: (details) async {
            final files = details.items.whereType<DropFileItem>().toList(
              growable: false,
            );
            await vm.withPlatformRead<void>(
              () => admitDroppedAttachments(files, vm.addLocalFiles),
            );
          },
          builder: (dragging) => ComposerView(
            key: ValueKey(target),
            state: state,
            enabled: editable,
            dragging: dragging,
            canSend: canSend,
            running: conversation?.running == true,
            compact: compact,
            onText: vm.setText,
            onSend: () => vm.send().ignore(),
            onStop: onStop,
            stopState: stopState,
            onAddLocal: () => vm.withPlatformRead<void>(() async {
              final paths = await pickLocalAttachmentPaths();
              if (paths.isNotEmpty) await vm.addLocalFiles(paths);
            }).ignore(),
            onPaste: () => vm.withPlatformRead<String?>(() async {
              final image = await clipboard.readImage();
              if (image != null) {
                await vm.addClipboardImage(image);
                return null;
              }
              return clipboard.readText();
            }),
            onAddUrl: () => vm
                .withPlatformRead<void>(
                  () => showDialog<void>(
                    context: context,
                    builder: (_) => _ComposerUrlConnector(target: target),
                  ),
                )
                .ignore(),
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
    child: widget.builder(_dragging),
  );
}

class _ComposerUrlConnector extends ConsumerWidget {
  const _ComposerUrlConnector({required this.target});
  final ComposerKey target;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final provider = composerViewModelProvider(target);
    final value = ref.watch(provider);
    final vm = ref.read(provider.notifier);
    return value.when(
      loading: () => const CircularProgressIndicator(),
      error: (error, stack) => const Icon(Icons.error_outline),
      data: (state) => AlertDialog(
        title: Text(context.l10n.composerAddUrlTitle),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              RawTextInput(
                raw: state.urlRaw,
                onChanged: vm.setUrl,
                enabled: !state.pending,
                onSubmit: () => vm.addRemoteUrl().ignore(),
                canSubmit: !state.pending,
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
            onPressed: state.pending ? null : () => vm.addRemoteUrl().ignore(),
            child: Text(context.l10n.composerAddUrlConfirm),
          ),
        ],
      ),
    );
  }
}
