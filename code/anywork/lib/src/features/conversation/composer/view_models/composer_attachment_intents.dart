import 'dart:typed_data';

import 'package:anywork_client/studio_client.dart';

import '../../../../platform/clipboard_image_reader.dart';
import '../../../../platform/dropped_attachments.dart';
import '../../../../platform/dropped_file.dart';
import '../../../../platform/file_picking.dart';
import '../state/composer_input_state.dart';
import '../state/composer_view_state.dart';
import 'composer_actions.dart';

/// Platform work bound to the originating target, never to global selection.
final class ComposerAttachmentIntents {
  const ComposerAttachmentIntents({
    required this.target,
    required this.client,
    required this.clipboard,
    required this.pickPaths,
    required this.input,
    required this.mode,
  });

  final ComposerTarget target;
  final AnyworkClient client;
  final ClipboardImageReader clipboard;
  final AttachmentPathPicker pickPaths;
  final ComposerInputState? Function() input;
  final ThreadModeId? mode;

  bool get _enabled => input()?.enabled ?? false;

  Future<void> _local(List<String> paths) {
    if (!_enabled) return Future.value();
    return switch (target) {
      ThreadComposerTarget(:final threadId) =>
        client.drafts.composer(threadId).addLocalAttachments(paths),
      StartComposerTarget(:final workspaceId) =>
        client.drafts.attachments.admitNewThread(
          workspaceId: workspaceId,
          mode: mode!,
          sources: [
            for (final path in paths) AttachmentDraftSource.localFile(path),
          ],
        ),
    };
  }

  Future<void> addUrl(String url) {
    if (!_enabled) return Future.value();
    return switch (target) {
      ThreadComposerTarget(:final threadId) =>
        client.drafts.composer(threadId).addRemoteAttachment(url),
      StartComposerTarget(:final workspaceId) =>
        client.drafts.attachments.addNewThreadRemote(
          workspaceId: workspaceId,
          mode: mode!,
          url: url,
        ),
    };
  }

  Future<void> remove(String draftId) {
    if (!_enabled) return Future.value();
    return switch (target) {
      ThreadComposerTarget(:final threadId) =>
        client.drafts.composer(threadId).removeAttachment(draftId),
      StartComposerTarget(:final workspaceId) =>
        client.drafts.attachments.removeNewThreadDraft(workspaceId, draftId),
    };
  }

  Future<void> _image(Uint8List bytes) => switch (target) {
    ThreadComposerTarget(:final threadId) =>
      client.drafts.composer(threadId).addClipboardImage(bytes),
    StartComposerTarget(:final workspaceId) =>
      client.drafts.attachments.addNewThreadClipboard(
        workspaceId: workspaceId,
        mode: mode!,
        pngBytes: bytes,
      ),
  };

  Future<void> paste(ComposerTextPaste textPaste) async {
    if (!_enabled || !textPaste.isCurrent()) return;
    final supportsImages = input()!.inputCapabilities.any(
      (capability) =>
          capability.modality == ModelModalityView.image &&
          capability.supportsSource(ModelInputSourceView.local),
    );
    Uint8List? bytes;
    try {
      bytes = await clipboard.readImage();
    } catch (_) {
      if (!_enabled || !textPaste.isCurrent()) return;
      throw ComposerClipboardFailure.readFailed;
    }
    if (!_enabled || !textPaste.isCurrent()) return;
    if (bytes == null) {
      await textPaste.invoke();
    } else {
      if (!supportsImages) throw ComposerClipboardFailure.unsupportedImage;
      await _image(bytes);
    }
  }

  Future<void> pick(
    List<ModelInputCapabilityView> capabilities,
    bool Function() isCurrent,
  ) async {
    if (!_enabled || !isCurrent()) return;
    final modalities = capabilities.map((item) => item.modality).toSet();
    final paths = await pickPaths(
      extensions: modalities.contains(ModelModalityView.file)
          ? const []
          : [
              if (modalities.contains(ModelModalityView.image)) ...[
                'png',
                'jpg',
                'jpeg',
                'gif',
                'webp',
              ],
              if (modalities.contains(ModelModalityView.video)) ...[
                'mp4',
                'mov',
                'webm',
                'mkv',
              ],
            ],
    );
    if (!_enabled || !isCurrent() || paths.isEmpty) return;
    await _local(paths);
  }

  Future<void> drop(
    List<DroppedFileTransfer> files,
    bool Function() isCurrent,
  ) async {
    if (!_enabled || !isCurrent()) return;
    await admitDroppedAttachments(files, (paths) {
      if (!_enabled || !isCurrent()) return Future<void>.value();
      return _local(paths);
    });
  }
}
