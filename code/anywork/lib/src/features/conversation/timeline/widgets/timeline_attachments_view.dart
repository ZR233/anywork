import 'package:anywork_client/models.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as p;

import '../state/timeline_file_presentation.dart';

/// One file grid for production and previews. IO and receipt decoding stay in
/// the connector; images retain the original image view and byte owner.
class TimelineAttachmentsView extends StatelessWidget {
  const TimelineAttachmentsView({
    super.key,
    required this.attachments,
    required this.imageBuilder,
    this.files,
    this.caption,
    this.onOpen,
    this.onSave,
    this.onReveal,
    this.busyIds = const {},
    this.errors = const {},
  });

  final List<ThreadAttachmentView> attachments;
  final List<TimelineFileEntry>? files;
  final String? caption;
  final Widget Function(ThreadAttachmentView attachment) imageBuilder;
  final ValueChanged<TimelineFileEntry>? onOpen;
  final ValueChanged<TimelineFileEntry>? onSave;
  final ValueChanged<TimelineFileEntry>? onReveal;
  final Set<String> busyIds;
  final Map<String, String> errors;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      if (caption case final caption?) ...[
        Text(caption),
        const SizedBox(height: 8),
      ],
      Wrap(
        spacing: 12,
        runSpacing: 12,
        children: [
          for (final file
              in files ?? attachments.map(TimelineFileEntry.archived))
            _FileCell(
              file: file,
              imageBuilder: imageBuilder,
              onOpen: file.isMarkdown ? onOpen : null,
              onSave: onSave,
              onReveal: onReveal,
              busy: busyIds.contains(file.attachment?.id),
              operationError: errors[file.attachment?.id],
            ),
        ],
      ),
    ],
  );
}

IconData timelineFileIcon(String filename) => switch (p
    .extension(filename)
    .toLowerCase()) {
  '.md' || '.markdown' => Icons.article_outlined,
  '.pdf' ||
  '.doc' ||
  '.docx' ||
  '.odt' ||
  '.rtf' ||
  '.txt' => Icons.description_outlined,
  '.xls' || '.xlsx' || '.csv' || '.ods' => Icons.table_chart_outlined,
  '.ppt' || '.pptx' || '.odp' => Icons.slideshow_outlined,
  '.zip' || '.gz' || '.tar' || '.7z' || '.rar' => Icons.folder_zip_outlined,
  '.mp3' || '.wav' || '.ogg' || '.flac' || '.m4a' => Icons.audio_file_outlined,
  '.mp4' || '.mov' || '.webm' || '.mkv' || '.avi' => Icons.video_file_outlined,
  _ => Icons.insert_drive_file_outlined,
};

class _FileCell extends StatefulWidget {
  const _FileCell({
    required this.file,
    required this.imageBuilder,
    required this.onOpen,
    required this.onSave,
    required this.onReveal,
    required this.busy,
    required this.operationError,
  });
  final TimelineFileEntry file;
  final Widget Function(ThreadAttachmentView) imageBuilder;
  final ValueChanged<TimelineFileEntry>? onOpen;
  final ValueChanged<TimelineFileEntry>? onSave;
  final ValueChanged<TimelineFileEntry>? onReveal;
  final bool busy;
  final String? operationError;

  @override
  State<_FileCell> createState() => _FileCellState();
}

class _FileCellState extends State<_FileCell> {
  final _menu = MenuController();

  @override
  void didUpdateWidget(covariant _FileCell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.file.attachment?.id != oldWidget.file.attachment?.id ||
        widget.file.filename != oldWidget.file.filename ||
        widget.file.origin != oldWidget.file.origin) {
      _menu.close();
    }
  }

  @override
  Widget build(BuildContext context) {
    final file = widget.file;
    final attachment = file.attachment;
    final error = file.error;
    final canSave = attachment != null && widget.onSave != null;
    final canReveal =
        file.origin == TimelineFileOrigin.local &&
        file.localPath != null &&
        widget.onReveal != null;
    final menuEnabled = (canSave || canReveal) && !widget.busy;
    final thumbnail = error != null
        ? Tooltip(
            message: error,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.error_outline,
                  color: Theme.of(context).colorScheme.error,
                ),
                const SizedBox(height: 8),
                Text(error, maxLines: 3, overflow: TextOverflow.ellipsis),
              ],
            ),
          )
        : attachment?.modality == AttachmentModalityView.image
        ? widget.imageBuilder(attachment!)
        : InkWell(
            onTap: widget.onOpen == null ? null : () => widget.onOpen!(file),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    timelineFileIcon(file.filename),
                    size: 44,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                  if (!file.isMarkdown) ...[
                    const SizedBox(height: 8),
                    Text(
                      '无内置预览',
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                  ],
                ],
              ),
            ),
          );
    return SizedBox(
      width: 144,
      child: Material(
        type: MaterialType.transparency,
        child: MenuAnchor(
          controller: _menu,
          menuChildren: [
            if (canSave)
              MenuItemButton(
                onPressed: widget.busy ? null : () => widget.onSave!(file),
                leadingIcon: const Icon(Icons.save_alt),
                child: Text(
                  file.origin == TimelineFileOrigin.remote
                      ? '下载'
                      : file.origin == TimelineFileOrigin.local
                      ? '另存为'
                      : '保存',
                ),
              ),
            if (canReveal)
              MenuItemButton(
                onPressed: widget.busy ? null : () => widget.onReveal!(file),
                leadingIcon: const Icon(Icons.folder_open_outlined),
                child: const Text('在文件管理器中显示'),
              ),
          ],
          builder: (context, controller, child) => GestureDetector(
            onSecondaryTapDown: menuEnabled
                ? (details) => controller.open(position: details.localPosition)
                : null,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Stack(
                  children: [
                    Center(
                      child:
                          attachment?.modality == AttachmentModalityView.image
                          // Successful thumbnails bound themselves. Image
                          // failures must keep their complete diagnosis and
                          // retry reachable rather than clip to a square.
                          ? SizedBox(width: 120, child: thumbnail)
                          : SizedBox.square(dimension: 120, child: thumbnail),
                    ),
                    if (canSave || canReveal)
                      Positioned(
                        top: 0,
                        right: 0,
                        child: IconButton(
                          tooltip: '文件操作',
                          visualDensity: VisualDensity.compact,
                          onPressed: menuEnabled
                              ? () => controller.isOpen
                                    ? controller.close()
                                    : controller.open()
                              : null,
                          icon: const Icon(Icons.more_horiz, size: 18),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 6),
                Tooltip(
                  message: file.filename,
                  child: InkWell(
                    onTap: widget.onOpen == null || attachment == null
                        ? null
                        : () => widget.onOpen!(file),
                    child: Text(
                      file.filename,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                ),
                if (widget.busy) const LinearProgressIndicator(),
                if (widget.operationError case final message?)
                  Text(
                    message,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
