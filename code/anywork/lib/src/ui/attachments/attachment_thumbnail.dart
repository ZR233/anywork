import 'package:anywork_client/drafts.dart' show AttachmentModality;
import 'package:flutter/material.dart';

import '../../l10n/studio_l10n.dart';
import 'attachment_format.dart';
import 'attachment_preview.dart';

/// Stable-sized preview. Decoding failures only change the glyph, not ownership
/// or action availability. A Smart owner supplies query loading/failure states.
class AttachmentThumbnail extends StatelessWidget {
  const AttachmentThumbnail({
    required this.modality,
    required this.preview,
    this.size = 48,
    super.key,
  });

  final AttachmentModality modality;
  final AttachmentPreview preview;
  final double size;

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: size,
    child: switch (preview) {
      NoAttachmentPreview() => Icon(attachmentIcon(modality)),
      LoadingAttachmentPreview() => const Center(
          child: SizedBox.square(
            dimension: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      ReadyAttachmentPreview(:final image) => ClipRRect(
          borderRadius: BorderRadius.circular(7),
          child: Image(
            image: image,
            fit: BoxFit.cover,
            errorBuilder: (_, error, stackTrace) => Tooltip(
              message: context.l10n.timelineImageLoadFailed,
              child: const Icon(Icons.broken_image_outlined),
            ),
          ),
        ),
      FailedAttachmentPreview(:final message) => Tooltip(
          message: message,
          child: const Icon(Icons.broken_image_outlined),
        ),
    },
  );
}
