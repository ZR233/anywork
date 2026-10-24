import 'dart:typed_data';

import 'collection_equality.dart';

import 'studio_enums.dart';

enum AttachmentModalityView { image, video, file }

/// Fixed product safety limits from design/17-studio-storage.md. Platform
/// transfer staging uses these to bound its own I/O; native admission remains
/// canonical and revalidates the complete batch, including borrowed files.
abstract final class AttachmentInputLimits {
  static const maxFiles = 32;
  static const maxFileBytes = 50 * 1024 * 1024;
  static const maxBatchBytes = 128 * 1024 * 1024;
}

/// Platform clipboard data, not paths inferred from ordinary clipboard text.
abstract interface class ComposerClipboardReader {
  /// Real native file-list paths. Sources are borrowed, not owned staging.
  Future<List<String>> readFiles();

  /// Clipboard pixels encoded as PNG, or null when no image is available.
  /// File-list images are not decoded or re-encoded through this method.
  Future<Uint8List?> readImage();

  /// Plain text, including path-looking strings which remain ordinary text.
  Future<String?> readText();
}

sealed class AttachmentAdmissionContext {
  const AttachmentAdmissionContext();

  const factory AttachmentAdmissionContext.existingThread(String threadId) =
      ExistingThreadAttachmentAdmissionContext;
  const factory AttachmentAdmissionContext.newThread(ThreadModeId mode) =
      NewThreadAttachmentAdmissionContext;
}

final class ExistingThreadAttachmentAdmissionContext
    extends AttachmentAdmissionContext {
  const ExistingThreadAttachmentAdmissionContext(this.threadId);
  final String threadId;
}

final class NewThreadAttachmentAdmissionContext
    extends AttachmentAdmissionContext {
  const NewThreadAttachmentAdmissionContext(this.mode);
  final ThreadModeId mode;
}

sealed class AttachmentDraftSource {
  const AttachmentDraftSource();

  const factory AttachmentDraftSource.localFile(String path) =
      LocalFileAttachmentDraftSource;
  const factory AttachmentDraftSource.remoteUrl(
    String url, {
    String? filename,
  }) = RemoteUrlAttachmentDraftSource;
}

final class LocalFileAttachmentDraftSource extends AttachmentDraftSource {
  const LocalFileAttachmentDraftSource(this.path);
  final String path;
}

final class RemoteUrlAttachmentDraftSource extends AttachmentDraftSource {
  const RemoteUrlAttachmentDraftSource(this.url, {this.filename});
  final String url;
  final String? filename;
}

class AttachmentDraftView {
  const AttachmentDraftView({
    required this.id,
    required this.modality,
    required this.mediaType,
    required this.filename,
    required this.byteSize,
    this.width,
    this.height,
    this.previewBytes,
  });

  final String id;
  final AttachmentModalityView modality;
  final String mediaType;
  final String filename;
  final int byteSize;
  final int? width;
  final int? height;
  final Uint8List? previewBytes;

  AttachmentDraftView copyWith({Uint8List? previewBytes}) =>
      AttachmentDraftView(
        id: id,
        modality: modality,
        mediaType: mediaType,
        filename: filename,
        byteSize: byteSize,
        width: width,
        height: height,
        previewBytes: previewBytes ?? this.previewBytes,
      );

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is AttachmentDraftView &&
            id == other.id &&
            modality == other.modality &&
            mediaType == other.mediaType &&
            filename == other.filename &&
            byteSize == other.byteSize &&
            width == other.width &&
            height == other.height &&
            listEquals(previewBytes, other.previewBytes);
  }

  @override
  int get hashCode => Object.hash(
    id,
    modality,
    mediaType,
    filename,
    byteSize,
    width,
    height,
    previewBytes == null ? null : Object.hashAll(previewBytes!),
  );
}

class StudioPromptInput {
  const StudioPromptInput({
    required this.inputId,
    required this.text,
    required this.attachmentDraftIds,
  });

  final String inputId;
  final String text;
  final List<String> attachmentDraftIds;
}
