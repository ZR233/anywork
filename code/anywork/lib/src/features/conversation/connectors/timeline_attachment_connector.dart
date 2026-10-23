import 'package:anywork_client/conversation.dart';
import 'package:anywork_client/drafts.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/app_bindings.dart';
import '../../../diagnostics/studio_driver_keys.dart';
import '../../../ui/attachments/attachment_metadata_view.dart';
import '../../../ui/attachments/attachment_preview.dart';
import '../timeline/display_binding.dart';
import '../views/attachment_image_view.dart';

class TimelineAttachmentConnector extends ConsumerStatefulWidget {
  const TimelineAttachmentConnector({required this.display, required this.attachment,
    required this.entryId, super.key});
  final TimelineDisplayBinding display;
  final ThreadAttachmentView attachment;
  final String entryId;
  @override
  ConsumerState<TimelineAttachmentConnector> createState() => _TimelineAttachmentConnectorState();
}

class _TimelineAttachmentConnectorState extends ConsumerState<TimelineAttachmentConnector> {
  AttachmentPreview _preview = const AttachmentPreview.none();
  bool _reading = false;
  int _attempt = 0;
  @override
  void didUpdateWidget(covariant TimelineAttachmentConnector oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.display, widget.display) || oldWidget.attachment.id != widget.attachment.id) {
      _attempt++; _reading = false; _preview = const AttachmentPreview.none();
    }
  }

  Future<void> _open() async {
    final preview = _preview;
    if (preview is ReadyAttachmentPreview) {
      await showDialog<void>(context: context, builder: (context) => AttachmentImageView(
        title: widget.attachment.filename ?? widget.attachment.id, preview: preview,
        onRetry: () { Navigator.of(context).pop(); _load().ignore(); },
        onClose: () => Navigator.of(context).pop()));
    } else { await _load(); }
  }

  Future<void> _load() async {
    if (_reading || widget.display.retired || widget.attachment.modality != AttachmentModality.image) return;
    final display = widget.display;
    final id = widget.attachment.id;
    final drafts = ref.read(draftsRepositoryProvider);
    final attempt = ++_attempt;
    _reading = true;
    setState(() { _preview = const AttachmentPreview.loading(); });
    try {
      final bytes = await drafts.readThreadAttachment(display.threadId, id);
      if (!mounted || attempt != _attempt || display.retired) return;
      setState(() { _preview = AttachmentPreview.ready(image: MemoryImage(bytes)); });
    } catch (_) {
      if (mounted && attempt == _attempt && !display.retired) setState(() {
        _preview = const AttachmentPreview.failed(message: 'The original image could not be read');
      });
    } finally { if (attempt == _attempt) _reading = false; }
  }

  @override
  Widget build(BuildContext context) {
    final attachment = widget.attachment;
    final metadata = AttachmentMetadata(id: attachment.id, modality: attachment.modality,
      filename: attachment.filename ?? '', mediaType: attachment.mediaType,
      byteSize: attachment.byteSize, width: attachment.width, height: attachment.height);
    return Column(mainAxisSize: MainAxisSize.min, children: [
      AttachmentMetadataView(key: StudioDriverKeys.historyAttachment(widget.entryId),
        attachment: metadata, preview: _preview, enabled: !widget.display.retired,
        onOpen: attachment.modality == AttachmentModality.image ? (_) => _open().ignore() : null),
    ]);
  }
}
