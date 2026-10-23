import 'dart:async';
import 'dart:typed_data';

import 'package:anywork_client/conversation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/app_bindings.dart';
import '../../../diagnostics/studio_driver_keys.dart';
import '../../../ui/attachments/attachment_preview.dart';
import '../timeline/display_binding.dart';
import '../views/timeline_image_card_view.dart';

/// A mounted card borrows one original typed attachment read. The repository
/// owns its actual query/join; this widget only owns publication and UI media.
class TimelineImageCardMediaConnector extends ConsumerStatefulWidget {
  const TimelineImageCardMediaConnector({
    required this.display,
    required this.attachment,
    required this.callId,
    required this.entryId,
    super.key,
  });

  final TimelineDisplayBinding display;
  final ThreadAttachmentView attachment;
  final String callId;
  final String entryId;

  @override
  ConsumerState<TimelineImageCardMediaConnector> createState() =>
      _TimelineImageCardMediaConnectorState();
}

class _TimelineImageCardMediaConnectorState
    extends ConsumerState<TimelineImageCardMediaConnector> {
  Future<Uint8List>? _image;
  AttachmentPreview _preview = const AttachmentPreview.none();
  int _readGeneration = 0;

  @override
  void initState() {
    super.initState();
    widget.display.addRetireListener(_retired);
    _readImage();
  }

  @override
  void didUpdateWidget(covariant TimelineImageCardMediaConnector oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.display, widget.display) ||
        oldWidget.display.threadId != widget.display.threadId ||
        oldWidget.display.generation != widget.display.generation ||
        oldWidget.attachment.id != widget.attachment.id ||
        oldWidget.callId != widget.callId || oldWidget.entryId != widget.entryId) {
      oldWidget.display.removeRetireListener(_retired);
      _clearPublication();
      widget.display.addRetireListener(_retired);
      _readImage();
    }
  }

  void _clearPublication() {
    _readGeneration++;
    _image = null;
    _preview = const AttachmentPreview.none();
  }

  void _retired() {
    if (mounted) setState(_clearPublication);
  }

  bool _current(TimelineDisplayBinding display, String attachmentId,
      String callId, String entryId, int generation) =>
      mounted && !display.retired && identical(widget.display, display) &&
      widget.display.threadId == display.threadId &&
      widget.display.generation == display.generation &&
      widget.attachment.id == attachmentId && widget.callId == callId &&
      widget.entryId == entryId && _readGeneration == generation;

  void _readImage() {
    if (widget.display.retired) return;
    final display = widget.display;
    final attachmentId = widget.attachment.id;
    final callId = widget.callId;
    final entryId = widget.entryId;
    final generation = _readGeneration;
    final repository = ref.read(draftsRepositoryProvider);
    _preview = const AttachmentPreview.loading();
    final image = Future<Uint8List>.sync(
      () => repository.readThreadAttachment(display.threadId, attachmentId),
    );
    // A synchronous repository callback may already have retired this binding.
    // Observe that original future even then, without restoring its UI rights.
    if (_current(display, attachmentId, callId, entryId, generation)) _image = image;
    unawaited(_observe(image, display, attachmentId, callId, entryId, generation));
  }

  Future<void> _observe(Future<Uint8List> image, TimelineDisplayBinding display,
      String attachmentId, String callId, String entryId, int generation) async {
    Uint8List bytes;
    try {
      bytes = await image;
    } on Object {
      if (_owns(image, display, attachmentId, callId, entryId, generation)) {
        setState(() => _preview = const AttachmentPreview.failed(message: ''));
      }
      return;
    }
    if (_owns(image, display, attachmentId, callId, entryId, generation)) {
      setState(() => _preview = AttachmentPreview.ready(image: MemoryImage(bytes)));
    }
  }

  bool _owns(Future<Uint8List> image, TimelineDisplayBinding display,
      String attachmentId, String callId, String entryId, int generation) =>
      identical(_image, image) &&
      _current(display, attachmentId, callId, entryId, generation);

  void _retry(Future<Uint8List> failed, TimelineDisplayBinding display,
      String attachmentId, String callId, String entryId, int generation) {
    // This callback is exposed only by a failed read/decode surface. A stale
    // failure cannot invalidate a newer read, and no shared cache is cleared.
    if (!_owns(failed, display, attachmentId, callId, entryId, generation)) return;
    setState(() {
      _clearPublication();
      _readImage();
    });
  }

  Future<void> _open(Future<Uint8List> image, TimelineDisplayBinding display,
      ThreadAttachmentView attachment, String callId, String entryId,
      int generation) async {
    Uint8List bytes;
    try {
      bytes = await image;
    } on Object {
      return;
    }
    if (!_owns(image, display, attachment.id, callId, entryId, generation)) return;
    await showDialog<void>(context: context, builder: (dialogContext) => TimelineImageCardDialog(
      key: StudioDriverKeys.timelineImageDialog(attachment.id),
      image: MemoryImage(bytes), filename: attachment.filename,
      onClose: () => Navigator.of(dialogContext).pop(),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final image = _image;
    final display = widget.display;
    final attachment = widget.attachment;
    final callId = widget.callId;
    final entryId = widget.entryId;
    final generation = _readGeneration;
    return TimelineImageCardMediaView(
      entryId: entryId, preview: _preview,
      width: attachment.width, height: attachment.height,
      onOpen: image == null || display.retired ? null : () => _open(
        image, display, attachment, callId, entryId, generation).ignore(),
      onRetry: image == null || display.retired ? null : () => _retry(
        image, display, attachment.id, callId, entryId, generation),
    );
  }

  @override
  void dispose() {
    widget.display.removeRetireListener(_retired);
    _clearPublication();
    super.dispose();
  }
}
