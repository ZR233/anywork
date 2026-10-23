import 'package:flutter/painting.dart';
import 'package:flutter/foundation.dart';

/// UI-only preview state. ImageProvider never enters a domain or Freezed value.
@immutable
sealed class AttachmentPreview {
  const AttachmentPreview();

  const factory AttachmentPreview.none() = NoAttachmentPreview;
  const factory AttachmentPreview.loading() = LoadingAttachmentPreview;
  const factory AttachmentPreview.ready({required ImageProvider image}) =
      ReadyAttachmentPreview;
  const factory AttachmentPreview.failed({required String message}) =
      FailedAttachmentPreview;
}

final class NoAttachmentPreview extends AttachmentPreview {
  const NoAttachmentPreview();
}

final class LoadingAttachmentPreview extends AttachmentPreview {
  const LoadingAttachmentPreview();
}

final class ReadyAttachmentPreview extends AttachmentPreview {
  const ReadyAttachmentPreview({required this.image});
  final ImageProvider image;
}

final class FailedAttachmentPreview extends AttachmentPreview {
  const FailedAttachmentPreview({required this.message});
  final String message;
}
