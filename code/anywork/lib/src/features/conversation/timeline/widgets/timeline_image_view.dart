import 'dart:typed_data';

import 'package:anywork_client/models.dart';
import 'package:material_ui/material_ui.dart';

import '../../../../shared/studio_driver_keys.dart';

/// Pure media presentation for immutable, already-admitted image bytes.
class TimelineImageView extends StatefulWidget {
  const TimelineImageView({
    super.key,
    required this.itemId,
    required this.attachment,
    required this.isTool,
    required this.active,
    required this.imageIdentity,
    this.bytes,
    this.width,
    this.height,
    this.error,
    this.onRetry,
  });

  final String itemId;
  final ThreadAttachmentView attachment;
  final bool isTool;
  final bool active;
  final Object imageIdentity;
  final Uint8List? bytes;
  final int? width;
  final int? height;
  final Object? error;
  final VoidCallback? onRetry;

  String get _entryId =>
      StudioDriverKeys.toolImageEntryId(itemId, attachment.id);
  String get _displayId => isTool ? _entryId : attachment.id;

  @override
  State<TimelineImageView> createState() => _TimelineImageViewState();
}

class _TimelineImageViewState extends State<TimelineImageView> {
  MemoryImage? _imageProvider;

  @override
  void initState() {
    super.initState();
    _prepareImage();
  }

  @override
  void didUpdateWidget(covariant TimelineImageView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.bytes, widget.bytes) ||
        oldWidget.imageIdentity != widget.imageIdentity) {
      _prepareImage();
    }
  }

  void _prepareImage() {
    final source = widget.bytes;
    if (source == null) {
      _imageProvider = null;
      return;
    }
    final owned = Uint8List.fromList(source);
    _imageProvider = MemoryImage(owned);
  }

  @override
  Widget build(BuildContext context) {
    final error = widget.error;
    if (error != null) {
      return TextButton.icon(
        key: StudioDriverKeys.timelineImageRetry(widget._displayId),
        onPressed: widget.active ? widget.onRetry : null,
        icon: const Icon(Icons.refresh),
        label: Text('图片读取失败：$error，重试', softWrap: true),
      );
    }
    final provider = _imageProvider;
    final width = widget.width;
    final height = widget.height;
    if (provider == null || width == null || height == null) {
      return const SizedBox.square(
        dimension: 120,
        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }
    // Thumbnail states own the bounded image cell. Errors above are text, not
    // thumbnails, and must grow within the attachment Wrap's available width.
    return SizedBox.square(
      dimension: 120,
      child: GestureDetector(
        key: StudioDriverKeys.viewImageThumbnail(widget._displayId),
        onTap: widget.active ? () => _showOriginal(context, provider) : null,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 360),
          child: Image(
            key: ValueKey(widget.imageIdentity),
            image: ResizeImage.resizeIfNeeded(720, null, provider),
            fit: BoxFit.contain,
            width: width.toDouble(),
            height: height.toDouble(),
            errorBuilder: (context, error, stack) => Tooltip(
              message: error.toString(),
              child: TextButton.icon(
                onPressed: widget.active ? widget.onRetry : null,
                icon: const Icon(Icons.broken_image_outlined),
                label: const Text('图片解码失败，重试'),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _showOriginal(BuildContext context, MemoryImage provider) =>
      showDialog<void>(
        context: context,
        builder: (context) => Dialog(
          key: widget.isTool
              ? StudioDriverKeys.viewImageDialog(widget._entryId)
              : StudioDriverKeys.timelineImageDialog(widget.attachment.id),
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.attachment.filename ?? widget.attachment.mediaType,
                    ),
                  ),
                  IconButton(
                    key: StudioDriverKeys.timelineImageClose,
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              Expanded(
                child: InteractiveViewer(
                  maxScale: 8,
                  child: Image(
                    image: provider,
                    fit: BoxFit.contain,
                    errorBuilder: (_, error, _) => Text('图片解码失败：$error'),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
}
