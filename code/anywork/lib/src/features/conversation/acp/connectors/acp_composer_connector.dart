import 'dart:async';

import 'package:anywork_client/models.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../../l10n/studio_l10n.dart';
import '../../../../platform/clipboard_image_reader.dart';
import '../../../../platform/desktop_drop_adapter.dart';
import '../../../../platform/dropped_attachments.dart';
import '../../../../platform/dropped_file.dart';
import '../../../../platform/file_picking.dart';
import '../view_models/acp_composer_view_model.dart';
import '../views/acp_conversation_composer_view.dart';
import 'acp_configuration_connector.dart';

/// Thin Riverpod connector binding [AcpComposerViewModel], desktop file-drop,
/// native file pickers, and clipboard image paste to [AcpConversationComposerView].
class AcpComposerConnector extends ConsumerStatefulWidget {
  const AcpComposerConnector({
    super.key,
    required this.threadId,
    this.compact = false,
  });

  final String threadId;
  final bool compact;

  @override
  ConsumerState<AcpComposerConnector> createState() =>
      _AcpComposerConnectorState();
}

class _AcpComposerConnectorState extends ConsumerState<AcpComposerConnector> {
  bool _dragging = false;
  int _targetGeneration = 0;

  @override
  void didUpdateWidget(covariant AcpComposerConnector oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.threadId != widget.threadId) {
      _dragging = false;
      _targetGeneration++;
    }
  }

  Future<void> _pickLocalAttachments(
    String originThreadId,
    List<ModelInputCapabilityView> capabilities,
  ) {
    final picker = ref.read(attachmentPathPickerProvider);
    final notifier = ref.read(
      acpComposerViewModelProvider(originThreadId).notifier,
    );
    final modalities = capabilities.map((item) => item.modality).toSet();
    final acceptsFiles = modalities.contains(ModelModalityView.file);
    final extensions = acceptsFiles
        ? const <String>[]
        : <String>[
            if (modalities.contains(ModelModalityView.image)) ...[
              'png',
              'jpg',
              'jpeg',
              'gif',
              'webp',
            ],
          ];
    return notifier.pickLocalAttachments(() => picker(extensions: extensions));
  }

  Future<void> _handleDroppedFiles(
    String originThreadId,
    List<DroppedFileTransfer> files,
  ) async {
    final notifier = ref.read(
      acpComposerViewModelProvider(originThreadId).notifier,
    );
    try {
      await admitDroppedAttachments(files, notifier.addLocalAttachments);
    } catch (error) {
      notifier.reportFailure(error);
    }
  }

  Future<void> _handleClipboardPaste(
    String originThreadId,
    Future<void> Function() pasteText,
    bool supportsImages,
  ) async {
    final generation = _targetGeneration;
    bool isCurrent() =>
        mounted &&
        widget.threadId == originThreadId &&
        _targetGeneration == generation;
    final clipboard = ref.read(clipboardImageReaderProvider);
    final notifier = ref.read(
      acpComposerViewModelProvider(originThreadId).notifier,
    );
    try {
      final image = await clipboard.readImage();
      if (!isCurrent()) return;
      if (image != null) {
        if (!supportsImages) {
          notifier.reportFailure(
            StateError(context.l10n.composerClipboardImageUnsupported),
          );
          return;
        }
        await notifier.pasteImage(image);
        return;
      }
      await pasteText();
    } catch (_) {
      // Clipboard plugin failures fall back to a user-visible draft diagnostic.
      if (!isCurrent()) return;
      notifier.reportFailure(
        StateError(context.l10n.composerClipboardReadFailed),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final threadId = widget.threadId;
    final provider = acpComposerViewModelProvider(threadId);
    final state = ref.watch(provider);
    final notifier = ref.read(provider.notifier);

    return DesktopFileDropTarget(
      enabled: state.canAttach,
      onEnter: () => setState(() => _dragging = true),
      onLeave: () => setState(() => _dragging = false),
      onDrop: (files) {
        setState(() => _dragging = false);
        return _handleDroppedFiles(threadId, files);
      },
      child: AcpConversationComposerView(
        state: state,
        compact: widget.compact,
        dragging: _dragging && state.canAttach,
        configurationBar: AcpConfigurationConnector(threadId: threadId),
        onDraftChanged: notifier.updateDraft,
        onSubmit: () => unawaited(notifier.submit()),
        onInterrupt: () => unawaited(notifier.interrupt()),
        onPickLocalAttachments: (capabilities) =>
            _pickLocalAttachments(threadId, capabilities),
        onAddRemoteAttachment: notifier.addRemoteAttachment,
        onRemoveAttachment: (draftId) =>
            unawaited(notifier.removeAttachment(draftId)),
        onPasteClipboard: (defaultPaste, supportsImages) =>
            _handleClipboardPaste(threadId, defaultPaste, supportsImages),
      ),
    );
  }
}
