import 'dart:typed_data';

import 'package:anywork_client/drafts.dart'
    show AttachmentMetadata, AttachmentModality;
import 'package:flutter/material.dart';

import '../../../diagnostics/studio_driver_keys.dart';
import '../../../l10n/studio_l10n.dart';
import '../../../ui/attachments/attachment_metadata_view.dart';
import '../../../ui/attachments/attachment_preview.dart';

/// One composer rail card.
///
/// The pre-refactor rail rendered the preview bytes the composer already held.
/// The paged read has no preview store, so this card borrows the existing
/// authorized draft binary read once per attachment and decodes it at thumbnail
/// width; ownership stays with the repository, and the bytes are dropped with
/// this State.
class DraftAttachmentRailItem extends StatefulWidget {
  const DraftAttachmentRailItem({
    required this.attachment,
    required this.read,
    this.enabled = true,
    this.onOpen,
    this.onRemove,
    super.key,
  });

  final AttachmentMetadata attachment;
  final Future<Uint8List> Function() read;
  final bool enabled;
  final ValueChanged<String>? onOpen;
  final ValueChanged<String>? onRemove;

  @override
  State<DraftAttachmentRailItem> createState() =>
      _DraftAttachmentRailItemState();
}

class _DraftAttachmentRailItemState extends State<DraftAttachmentRailItem> {
  /// 48 logical pixels at 2x: enough for the thumbnail, far cheaper than the
  /// original decode. `ResizeImage` keeps its own cache entry per byte list.
  static const _thumbnailDecodeWidth = 96;

  Uint8List? _bytes;
  bool _loading = false;
  bool _failed = false;

  /// The original read failure. The rail only ever shows a generic message, so
  /// this keeps the cause discoverable in debug instead of dropping it.
  Object? _cause;
  StackTrace? _trace;

  @override
  void initState() {
    super.initState();
    if (widget.attachment.modality == AttachmentModality.image) {
      _loading = true;
      _read().ignore();
    }
  }

  @override
  void didUpdateWidget(covariant DraftAttachmentRailItem oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.attachment.id == widget.attachment.id) return;
    _bytes = null;
    _failed = false;
    _loading = false;
    _cause = null;
    _trace = null;
    if (widget.attachment.modality == AttachmentModality.image) {
      setState(() => _loading = true);
      _read().ignore();
    } else {
      setState(() {});
    }
  }

  @override
  void dispose() {
    // Drop the borrowed bytes with the card; the repository keeps the original.
    _bytes = null;
    _cause = null;
    _trace = null;
    super.dispose();
  }

  Future<void> _read() async {
    final id = widget.attachment.id;
    try {
      final bytes = await widget.read();
      if (!mounted || widget.attachment.id != id) return;
      setState(() {
        _bytes = bytes;
        _failed = false;
        _loading = false;
        _cause = null;
      });
    } catch (error, stack) {
      if (!mounted || widget.attachment.id != id) return;
      setState(() {
        _bytes = null;
        _failed = true;
        _loading = false;
        _cause = error;
        _trace = stack;
      });
    }
  }

  AttachmentPreview _previewFor(BuildContext context) {
    if (_bytes case final bytes?) {
      return AttachmentPreview.ready(
        image: ResizeImage(MemoryImage(bytes), width: _thumbnailDecodeWidth),
      );
    }
    if (_failed) {
      return AttachmentPreview.failed(message: _failureMessage(context));
    }
    return _loading
        ? const AttachmentPreview.loading()
        : const AttachmentPreview.none();
  }

  String _failureMessage(BuildContext context) {
    final cause = _cause;
    if (cause != null) {
      // Debug-only: the visible text stays generic, the cause stays reachable.
      assert(() {
        debugPrint('Draft attachment preview read failed: $cause\n$_trace');
        return true;
      }());
    }
    return context.l10n.timelineImageLoadFailed;
  }

  @override
  Widget build(BuildContext context) => AttachmentMetadataView(
    attachment: widget.attachment,
    preview: _previewFor(context),
    enabled: widget.enabled,
    onOpen: widget.onOpen,
    onRemove: widget.onRemove,
    modalityKey: StudioDriverKeys.attachmentModality(widget.attachment.id),
    removeKey: StudioDriverKeys.attachmentRemove(widget.attachment.id),
  );
}
