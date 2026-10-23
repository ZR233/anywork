import 'package:anywork_client/drafts.dart' show AttachmentMetadata;
import 'package:flutter/material.dart';

import '../../l10n/studio_l10n.dart';
import '../formatters/byte_format.dart';
import 'attachment_format.dart';
import 'attachment_preview.dart';
import 'attachment_thumbnail.dart';

/// Compact metadata for one immutable attachment. Callbacks only emit its ID;
/// admission, queries, ownership and native cleanup stay with the VM/domain.
class AttachmentMetadataView extends StatelessWidget {
  const AttachmentMetadataView({
    required this.attachment,
    this.preview = const AttachmentPreview.none(),
    this.enabled = true,
    this.onOpen,
    this.onRemove,
    this.modalityKey,
    this.removeKey,
    super.key,
  });

  final AttachmentMetadata attachment;
  final AttachmentPreview preview;
  final bool enabled;
  final ValueChanged<String>? onOpen;
  final ValueChanged<String>? onRemove;
  final Key? modalityKey;
  final Key? removeKey;

  @override
  Widget build(BuildContext context) {
    final label = attachment.filename.isEmpty
        ? context.l10n.attachmentFallback
        : attachment.filename;
    return Material(
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(10),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: enabled && onOpen != null
            ? () => onOpen!(attachment.id)
            : null,
        child: Padding(
          padding: const EdgeInsets.all(7),
          child: Row(
            children: [
              AttachmentThumbnail(
                modality: attachment.modality,
                preview: preview,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Tooltip(
                      message: attachmentDescription(context, attachment),
                      child: Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Text(
                      '${context.attachmentModalityLabel(attachment.modality)} · ${formatBytes(attachment.byteSize)}',
                      key: modalityKey ?? ValueKey<String>(
                        'attachment-modality-${attachment.id}',
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                  ],
                ),
              ),
              if (onRemove != null)
                IconButton(
                  key: removeKey ?? ValueKey<String>(
                    'attachment-remove-${attachment.id}',
                  ),
                  visualDensity: VisualDensity.compact,
                  tooltip: context.l10n.composerAttachmentRemoveTooltip,
                  onPressed: enabled ? () => onRemove!(attachment.id) : null,
                  icon: const Icon(Icons.close, size: 18),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
