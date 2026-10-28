import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:anywork_client/models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_chat_core/flutter_chat_core.dart';
import 'package:flyer_chat_image_message/flyer_chat_image_message.dart';

import '../../../../shared/studio_driver_keys.dart';
import '../../../../shared/studio_driver_key_values.dart';
import '../state/timeline_entry.dart';
import '../state/timeline_image_resources.dart';
import '../widgets/timeline_entry_view.dart';

/// Mounted media borrows a lease-owned attempt. The item reference ledger, not
/// widget mount/unmount, determines when shared bytes are released.
class TimelineImageConnector extends StatefulWidget {
  const TimelineImageConnector({
    super.key,
    required this.message,
    required this.index,
    required this.item,
    required this.resources,
    required this.readBytes,
    required this.isActive,
    required this.onDetail,
  });

  final ImageMessage message;
  final int index;
  final ConversationItem item;
  final TimelineImageResources resources;
  final Future<Uint8List> Function() readBytes;
  final bool Function() isActive;
  final TimelineDetailAction onDetail;

  @override
  State<TimelineImageConnector> createState() => _TimelineImageConnectorState();
}

class _TimelineImageConnectorState extends State<TimelineImageConnector> {
  late TimelineImageResource _resource;
  Future<(Uint8List, int, int)>? _read;

  ThreadAttachmentView get _attachment =>
      widget.message.metadata!['attachment'] as ThreadAttachmentView;
  String get _entryId =>
      StudioDriverKeys.toolImageEntryId(widget.item.id, _attachment.id);
  bool get _isTool => widget.item.descriptor is ConversationToolDescriptor;
  bool get _isImageCard => switch (widget.item.descriptor) {
    ConversationToolDescriptor(:final invocation) =>
      invocation.name == 'show_image',
    _ => false,
  };

  @override
  void initState() {
    super.initState();
    _bindResource();
  }

  void _bindResource() {
    _resource = widget.resources.borrow(_attachment.id);
    _resource.addListener(_attemptChanged);
    _read = _startThumbnail();
  }

  @override
  void didUpdateWidget(covariant TimelineImageConnector oldWidget) {
    super.didUpdateWidget(oldWidget);
    final oldAttachment =
        oldWidget.message.metadata!['attachment'] as ThreadAttachmentView;
    if (!identical(widget.resources, oldWidget.resources) ||
        _attachment.id != oldAttachment.id) {
      _resource.removeListener(_attemptChanged);
      _bindResource();
    }
  }

  @override
  void dispose() {
    _resource.removeListener(_attemptChanged);
    super.dispose();
  }

  void _attemptChanged() {
    if (!mounted) return;
    setState(() {
      _read = _startThumbnail();
    });
  }

  Future<(Uint8List, int, int)> _startThumbnail() {
    final read = _thumbnail();
    // Retry may fail before the next frame installs FutureBuilder's listener.
    // Observe immediately without changing the future/error presented by UI.
    read.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return read;
  }

  Future<(Uint8List, int, int)> _thumbnail() async {
    if (!widget.isActive()) {
      throw StateError('The image display generation retired');
    }
    final attempt = _resource.load(widget.readBytes);
    final bytes = await attempt;
    if (!widget.isActive() || !_resource.owns(attempt)) {
      throw StateError('The image read no longer belongs to this display');
    }
    final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
    try {
      final descriptor = await ui.ImageDescriptor.encoded(buffer);
      try {
        if (!widget.isActive() || !_resource.owns(attempt)) {
          throw StateError('The decoded image is no longer current');
        }
        return (bytes, descriptor.width, descriptor.height);
      } finally {
        descriptor.dispose();
      }
    } finally {
      buffer.dispose();
    }
  }

  void _retry() {
    if (!widget.isActive()) return;
    _resource.retry(widget.readBytes);
  }

  @override
  Widget build(BuildContext context) {
    _read ??= _startThumbnail();
    return FutureBuilder<(Uint8List, int, int)>(
      future: _read,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return TextButton.icon(
            key: _isImageCard
                ? StudioDriverKeys.imageCardRetry(_entryId)
                : StudioDriverKeys.timelineImageRetry(
                    _isTool ? _entryId : _attachment.id,
                  ),
            onPressed: widget.isActive() ? _retry : null,
            icon: const Icon(Icons.refresh),
            label: const Text('图片读取失败，重试'),
          );
        }
        final image = snapshot.data;
        if (image == null) {
          return const SizedBox(
            height: 120,
            child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
          );
        }
        final (bytes, width, height) = image;
        return GestureDetector(
          key: _isImageCard
              ? StudioDriverKeys.imageCardImage(_entryId)
              : StudioDriverKeys.viewImageThumbnail(
                  _isTool ? _entryId : _attachment.id,
                ),
          onTap: () => _showOriginal(context),
          child: FlyerChatImageMessage(
            key: ValueKey((widget.resources.threadId, _attachment.id)),
            // Complete dimensions before mounting stock image UI, preventing
            // its asynchronous size updater from writing an older Message back.
            message: widget.message.copyWith(
              width: width.toDouble(),
              height: height.toDouble(),
            ),
            index: widget.index,
            customImageProvider: ResizeImage.resizeIfNeeded(
              720,
              null,
              MemoryImage(bytes),
            ),
            showTime: false,
            showStatus: false,
            constraints: const BoxConstraints(maxHeight: 360),
          ),
        );
      },
    );
  }

  Future<void> _showOriginal(BuildContext context) async {
    if (!widget.isActive()) return;
    final read = _read ??= _startThumbnail();
    (Uint8List, int, int) image;
    try {
      image = await read;
    } catch (error) {
      if (context.mounted && widget.isActive() && identical(read, _read)) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.toString())));
      }
      return;
    }
    if (!context.mounted || !widget.isActive() || !identical(read, _read)) {
      return;
    }
    final bytes = image.$1;
    final detailFields = <ThreadContentFieldView>[
      const ThreadToolArgumentsFieldView(),
      const ThreadToolResultFieldView(),
    ].where((field) => widget.item.detailFor(field) != null).toList();
    await showDialog<void>(
      context: context,
      builder: (context) => Dialog(
        key: _isTool
            ? StudioDriverKeys.viewImageDialog(_entryId)
            : StudioDriverKeys.timelineImageDialog(_attachment.id),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(_attachment.filename ?? _attachment.mediaType),
                ),
                for (final field in detailFields)
                  TextButton(
                    key: StudioDriverKeys.timelineDetailOpen(
                      widget.item.id,
                      StudioDriverKeyValues.timelineDetailField(field),
                    ),
                    onPressed: () => widget.onDetail(widget.item.id, field),
                    child: Text(timelineFieldLabel(field)),
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
                child: Image.memory(bytes, fit: BoxFit.contain),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The activity entry already owns expansion intent. This connector only lays
/// out its typed image members; it does not add a second disclosure state.
class TimelineGroupMediaConnector extends StatelessWidget {
  const TimelineGroupMediaConnector({
    super.key,
    required this.item,
    required this.resources,
    required this.readAttachment,
    required this.isActive,
    required this.onDetail,
  });

  final ConversationItem item;
  final TimelineImageResources resources;
  final Future<Uint8List> Function(String attachmentId) readAttachment;
  final bool Function() isActive;
  final TimelineDetailAction onDetail;

  @override
  Widget build(BuildContext context) {
    final attachments = timelineAttachments(item)
        .where((value) => value.modality == AttachmentModalityView.image);
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final attachment in attachments)
          SizedBox(
            width: 120,
            height: 120,
            child: TimelineImageConnector(
              key: ValueKey((item.id, attachment.id)),
              index: 0,
              item: item,
              resources: resources,
              readBytes: () => readAttachment(attachment.id),
              isActive: isActive,
              onDetail: onDetail,
              message: ImageMessage(
                id: '${item.id}:attachment:${attachment.id}',
                authorId: 'assistant',
                source: 'anywork-attachment:${attachment.id}',
                width: attachment.width?.toDouble(),
                height: attachment.height?.toDouble(),
                metadata: {'attachment': attachment},
              ),
            ),
          ),
      ],
    );
  }
}

class TimelineRemoteImageConnector extends StatefulWidget {
  const TimelineRemoteImageConnector({super.key, required this.url});
  final String url;
  @override
  State<TimelineRemoteImageConnector> createState() =>
      _TimelineRemoteImageConnectorState();
}

class _TimelineRemoteImageConnectorState
    extends State<TimelineRemoteImageConnector> {
  bool _load = false;
  @override
  void didUpdateWidget(covariant TimelineRemoteImageConnector oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.url != oldWidget.url) _load = false;
  }

  @override
  Widget build(BuildContext context) {
    final uri = Uri.tryParse(widget.url);
    final allowed =
        widget.url.length <= 8192 &&
        !widget.url.codeUnits.any((unit) => unit < 0x20 || unit == 0x7f) &&
        uri != null &&
        uri.scheme == 'https' &&
        uri.host.isNotEmpty &&
        uri.userInfo.isEmpty;
    if (!allowed) {
      return const SelectionContainer.disabled(child: Text('外部图片不可加载'));
    }
    if (!_load) {
      return SelectionContainer.disabled(
        child: TextButton.icon(
          onPressed: () => setState(() => _load = true),
          icon: const Icon(Icons.image_outlined),
          label: Text('加载外部图片 · ${uri.host}'),
        ),
      );
    }
    return Image.network(
      widget.url,
      height: 240,
      fit: BoxFit.contain,
      errorBuilder: (_, _, _) => const Text('外部图片加载失败'),
    );
  }
}
