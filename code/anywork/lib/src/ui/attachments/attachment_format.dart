import 'package:anywork_client/drafts.dart'
    show AttachmentMetadata, AttachmentModality;
import 'package:flutter/material.dart';

import '../../l10n/studio_l10n.dart';
import '../formatters/byte_format.dart';

IconData attachmentIcon(AttachmentModality modality) => switch (modality) {
  AttachmentModality.image => Icons.image_outlined,
  AttachmentModality.video => Icons.movie_outlined,
  AttachmentModality.file => Icons.insert_drive_file_outlined,
};

String attachmentDescription(
  BuildContext context,
  AttachmentMetadata attachment,
) {
  final name = attachment.filename.isEmpty
      ? context.l10n.attachmentFallback
      : attachment.filename;
  final dimensions = attachment.width != null && attachment.height != null
      ? ' · ${attachment.width}×${attachment.height}'
      : '';
  return '$name$dimensions · ${formatBytes(attachment.byteSize)}';
}
