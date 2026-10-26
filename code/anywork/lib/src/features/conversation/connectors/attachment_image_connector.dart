import 'dart:typed_data';

import 'package:anywork_client/resources.dart';
import 'package:flutter/material.dart';

import '../../../ui/attachments/attachment_preview.dart';
import '../views/attachment_image_view.dart';

Future<void> openAttachmentImage(
  BuildContext context, {
  required String title,
  required Future<Uint8List> Function() read,
  bool Function()? current,
}) => showDialog<void>(
  context: context,
  builder: (_) =>
      _AttachmentImageConnector(title: title, read: read, current: current),
);

class _AttachmentImageConnector extends StatefulWidget {
  const _AttachmentImageConnector({
    required this.title,
    required this.read,
    this.current,
  });
  final String title;
  final Future<Uint8List> Function() read;
  final bool Function()? current;
  @override
  State<_AttachmentImageConnector> createState() =>
      _AttachmentImageConnectorState();
}

class _AttachmentImageConnectorState extends State<_AttachmentImageConnector> {
  AttachmentPreview _preview = const AttachmentPreview.loading();
  bool _reading = false;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (_reading) return;
    _reading = true;
    if (mounted) {
      setState(() {
        _preview = const AttachmentPreview.loading();
      });
    }
    try {
      if (widget.current?.call() == false) throw _retired;
      final bytes = await widget.read();
      if (!mounted) return;
      if (widget.current?.call() == false) throw _retired;
      setState(() {
        _preview = AttachmentPreview.ready(image: MemoryImage(bytes));
      });
    } on StudioFailure catch (failure) {
      if (mounted) {
        setState(() {
          _preview = AttachmentPreview.failed(message: failure.message);
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _preview = const AttachmentPreview.failed(
            message: 'The original image could not be read',
          );
        });
      }
    } finally {
      _reading = false;
    }
  }

  static const _retired = StudioFailure(
    code: StudioFailureCode.superseded,
    message: 'This conversation display has retired',
    retryable: false,
    correlationId: 'attachment-display-retired',
  );

  @override
  Widget build(BuildContext context) => AttachmentImageView(
    title: widget.title,
    preview: _preview,
    onRetry: () => _load().ignore(),
    onClose: () => Navigator.of(context).pop(),
  );
}
