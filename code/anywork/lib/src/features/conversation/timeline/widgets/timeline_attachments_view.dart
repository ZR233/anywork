import 'package:anywork_client/models.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as p;

import '../../../../l10n/studio_l10n.dart';
import '../connectors/timeline_deferred_file_connector.dart';
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
    this.itemId,
    this.isActive,
    this.networkImageBuilder,
    this.onOpen,
    this.onSave,
    this.onReveal,
    this.busyIds = const {},
    this.errors = const {},
  });

  final List<ThreadAttachmentView> attachments;
  final List<TimelineFileEntry>? files;
  final String? caption;
  final String? itemId;
  final bool Function()? isActive;
  final Widget Function(ThreadAttachmentView attachment) imageBuilder;
  final Widget Function(TimelineFileEntry file)? networkImageBuilder;
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
        Text(
          caption,
          style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
        ),
        const SizedBox(height: 8),
      ],
      Wrap(
        spacing: 12,
        runSpacing: 12,
        children: [
          for (final (index, file)
              in (files ?? attachments.map(TimelineFileEntry.archived)).indexed)
            _cell(index, file),
        ],
      ),
    ],
  );

  Widget _cell(int index, TimelineFileEntry file) {
    final attachment = file.attachment;
    final archivedImage = attachment?.modality == AttachmentModalityView.image;
    Widget cell([TimelineDeferredFileState? download]) => _FileCell(
      file: file,
      image: archivedImage
          ? imageBuilder(attachment!)
          : file.networkImageUrl == null
          ? null
          : networkImageBuilder?.call(file),
      archivedImage: archivedImage,
      onOpen: attachment != null && file.isMarkdown ? onOpen : null,
      onSave: onSave,
      onReveal: onReveal,
      busy: busyIds.contains(attachment?.id),
      operationError: download?.error ?? errors[attachment?.id],
      download: download,
    );

    final size = file.deferredSize;
    if (size == null) return cell();
    final id = itemId;
    final active = isActive;
    if (id == null || active == null) {
      return cell(const TimelineDeferredFileState());
    }
    return TimelineDeferredFileConnector(
      key: ValueKey(index),
      itemId: id,
      index: index,
      filename: file.filename,
      size: size,
      isActive: active,
      builder: cell,
    );
  }
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
    required this.image,
    required this.archivedImage,
    required this.onOpen,
    required this.onSave,
    required this.onReveal,
    required this.busy,
    required this.operationError,
    required this.download,
  });
  final TimelineFileEntry file;
  final Widget? image;
  final bool archivedImage;
  final ValueChanged<TimelineFileEntry>? onOpen;
  final ValueChanged<TimelineFileEntry>? onSave;
  final ValueChanged<TimelineFileEntry>? onReveal;
  final bool busy;
  final String? operationError;
  final TimelineDeferredFileState? download;

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
    final colors = Theme.of(context).colorScheme;
    final download = widget.download;
    final canSave = attachment != null && widget.onSave != null;
    final canReveal =
        file.origin == TimelineFileOrigin.local &&
        file.localPath != null &&
        widget.onReveal != null;
    final menuEnabled = (canSave || canReveal) && !widget.busy;
    final thumbnail = error != null
        ? Tooltip(
            message: error,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.error_outline, color: colors.error),
                  const SizedBox(height: 8),
                  Flexible(
                    child: Text(
                      error,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: colors.onSurface),
                    ),
                  ),
                ],
              ),
            ),
          )
        : widget.image ??
              InkWell(
                onTap: widget.onOpen == null
                    ? null
                    : () => widget.onOpen!(file),
                child: Center(child: _fileGlyph(context)),
              );
    return SizedBox(
      width: 144,
      child: Material(
        color: colors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(8),
        clipBehavior: Clip.antiAlias,
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
                      child: widget.archivedImage
                          // Successful thumbnails bound themselves. Image
                          // failures must keep their complete diagnosis and
                          // retry reachable rather than clip to a square.
                          ? SizedBox(width: 120, child: thumbnail)
                          : SizedBox.square(dimension: 120, child: thumbnail),
                    ),
                    if (download != null)
                      PositionedDirectional(
                        top: 0,
                        end: 0,
                        child: _downloadActions(context, download),
                      ),
                    if (canSave || canReveal)
                      PositionedDirectional(
                        top: 0,
                        end: 0,
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
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Tooltip(
                        message: file.filename,
                        child: InkWell(
                          onTap: widget.onOpen == null
                              ? null
                              : () => widget.onOpen!(file),
                          child: Text(
                            file.filename,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(color: colors.onSurface),
                          ),
                        ),
                      ),
                      if (widget.operationError case final message?)
                        Text(message, style: TextStyle(color: colors.error)),
                    ],
                  ),
                ),
                if (widget.busy && widget.archivedImage)
                  const LinearProgressIndicator(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _fileGlyph(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final download = widget.download;
    if (download?.completed ?? false) {
      return Tooltip(
        message: context.l10n.timelineFileDownloadComplete,
        child: Icon(
          Icons.check_circle_outline,
          size: 44,
          color: colors.primary,
        ),
      );
    }
    final progress = download?.progress;
    if (widget.busy || download?.selecting == true || progress != null) {
      final percentage = progress == null
          ? null
          : '${(progress * 100).floor()}%';
      return SizedBox.square(
        dimension: 60,
        child: Stack(
          alignment: Alignment.center,
          fit: StackFit.expand,
          children: [
            CircularProgressIndicator(
              value: progress,
              strokeWidth: 4,
              strokeCap: StrokeCap.round,
              color: colors.primary,
              backgroundColor: colors.outlineVariant,
              semanticsLabel: download == null
                  ? null
                  : context.l10n.timelineFileDownload,
              semanticsValue: percentage,
            ),
            Center(
              child: ExcludeSemantics(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      download?.paused == true
                          ? Icons.pause
                          : timelineFileIcon(widget.file.filename),
                      size: percentage == null ? 25 : 18,
                      color: colors.onSurfaceVariant,
                    ),
                    if (percentage != null)
                      SizedBox(
                        width: 44,
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            percentage,
                            style: Theme.of(context).textTheme.labelSmall
                                ?.copyWith(
                                  color: colors.onSurface,
                                  fontWeight: FontWeight.w700,
                                ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
    }
    return Icon(
      timelineFileIcon(widget.file.filename),
      size: 44,
      color: colors.onSurfaceVariant,
    );
  }

  Widget _downloadActions(
    BuildContext context,
    TimelineDeferredFileState download,
  ) {
    final l10n = context.l10n;
    IconButton action(String label, IconData icon, VoidCallback? onPressed) =>
        IconButton(
          tooltip: label,
          visualDensity: VisualDensity.compact,
          onPressed: onPressed,
          icon: Icon(icon, size: 20),
        );
    if (download.progress == null) {
      return action(
        l10n.timelineFileDownload,
        Icons.download,
        download.onDownload,
      );
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        action(
          download.paused
              ? l10n.timelineFileDownloadResume
              : l10n.timelineFileDownloadPause,
          download.paused ? Icons.play_arrow : Icons.pause,
          download.onPauseOrResume,
        ),
        action(l10n.timelineFileDownloadStop, Icons.stop, download.onStop),
      ],
    );
  }
}
