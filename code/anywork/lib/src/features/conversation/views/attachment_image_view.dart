import 'package:flutter/material.dart';

import '../../../l10n/studio_l10n.dart';
import '../../../ui/attachments/attachment_preview.dart';

/// UI-only image material. Neither the byte query nor its domain owner crosses
/// this boundary; the ImageProvider is held only by the Smart overlay.
class AttachmentImageView extends StatelessWidget {
  const AttachmentImageView({required this.title, required this.preview,
    required this.onRetry, required this.onClose, super.key});
  final String title;
  final AttachmentPreview preview;
  final VoidCallback onRetry;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) => Dialog(child: ConstrainedBox(
    constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * .9,
      maxHeight: MediaQuery.sizeOf(context).height * .9),
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      Row(children: [Expanded(child: Padding(padding: const EdgeInsets.all(12),
        child: Text(title, maxLines: 2, overflow: TextOverflow.ellipsis))),
        IconButton(onPressed: onClose, icon: const Icon(Icons.close))]),
      Flexible(child: switch (preview) {
        NoAttachmentPreview() || LoadingAttachmentPreview() =>
          const Padding(padding: EdgeInsets.all(32), child: CircularProgressIndicator()),
        ReadyAttachmentPreview(:final image) => InteractiveViewer(
          minScale: .25, maxScale: 8, child: Image(image: image, fit: BoxFit.contain,
            errorBuilder: (context, error, stack) => TextButton.icon(
              onPressed: onRetry, icon: const Icon(Icons.broken_image_outlined),
              label: Text(context.l10n.sidebarRetry)))),
        FailedAttachmentPreview(:final message) => Padding(padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [Text(message),
            TextButton(onPressed: onRetry, child: Text(context.l10n.sidebarRetry))])),
      }),
    ])));
}
