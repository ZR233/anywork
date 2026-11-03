import 'package:anywork_client/models.dart';
import 'package:flutter/material.dart';

import '../../../../l10n/studio_l10n.dart';

/// One attachment layout for production and component previews.
///
/// Admitted attachment values are immutable. The image child owns its local
/// presentation state; its Connector owns reads, eligibility and byte leases.
class TimelineAttachmentsView extends StatelessWidget {
  const TimelineAttachmentsView({
    super.key,
    required this.attachments,
    required this.imageBuilder,
  });

  final List<ThreadAttachmentView> attachments;
  final Widget Function(ThreadAttachmentView attachment) imageBuilder;

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 8,
    runSpacing: 8,
    children: [
      for (final attachment in attachments)
        if (attachment.modality == AttachmentModalityView.image)
          SizedBox(width: 120, height: 120, child: imageBuilder(attachment))
        else
          SizedBox(
            width: 280,
            child: Material(
              type: MaterialType.transparency,
              child: ListTile(
                leading: Icon(
                  attachment.modality == AttachmentModalityView.video
                      ? Icons.movie_outlined
                      : Icons.insert_drive_file_outlined,
                ),
                title: Text(
                  attachment.filename ??
                      context.attachmentModalityLabel(attachment.modality),
                ),
                subtitle: Text(
                  '${attachment.mediaType} · ${attachment.byteSize} B',
                ),
              ),
            ),
          ),
    ],
  );
}
