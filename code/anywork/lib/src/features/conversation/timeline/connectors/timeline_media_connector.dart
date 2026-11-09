import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:anywork_client/models.dart';
import 'package:material_ui/material_ui.dart';

import '../../../../platform/local_file_dialogs.dart';
import '../state/timeline_file_presentation.dart';
import 'file_reading_panel.dart';
import 'timeline_content_connector.dart';
import '../state/timeline_image_resources.dart';
import '../state/chat_item_presentation.dart';
import '../widgets/content_layout_witness.dart';
import '../widgets/timeline_attachments_view.dart';
import '../widgets/timeline_image_view.dart';

/// Mounted media borrows a lease-owned attempt. The item reference ledger, not
/// widget mount/unmount, determines when shared bytes are released.
class TimelineImageConnector extends StatefulWidget {
  const TimelineImageConnector({
    super.key,
    required this.itemId,
    required this.attachment,
    required this.isTool,
    required this.resources,
    required this.readBytes,
    required this.isActive,
  });

  final String itemId;
  final ThreadAttachmentView attachment;
  final bool isTool;
  final TimelineImageResources resources;
  final Future<Uint8List> Function() readBytes;
  final bool Function() isActive;

  @override
  State<TimelineImageConnector> createState() => _TimelineImageConnectorState();
}

class _TimelineImageConnectorState extends State<TimelineImageConnector> {
  late TimelineImageResource _resource;
  Future<(Uint8List, int, int)>? _read;

  ThreadAttachmentView get _attachment => widget.attachment;
  bool get _isTool => widget.isTool;

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
    final oldAttachment = oldWidget.attachment;
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
    final isActive = widget.isActive;
    final resource = _resource;
    if (!isActive()) {
      throw StateError('The image display generation retired');
    }
    final attempt = resource.load(widget.readBytes);
    final bytes = await attempt;
    if (!isActive() || !resource.owns(attempt)) {
      throw StateError('The image read no longer belongs to this display');
    }
    final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
    try {
      final descriptor = await ui.ImageDescriptor.encoded(buffer);
      try {
        if (!isActive() || !resource.owns(attempt)) {
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
        final image = snapshot.data;
        return TimelineImageView(
          itemId: widget.itemId,
          attachment: _attachment,
          isTool: _isTool,
          active: widget.isActive(),
          imageIdentity: (widget.resources.threadId, _attachment.id),
          bytes: image?.$1,
          width: image?.$2,
          height: image?.$3,
          error: snapshot.error,
          onRetry: _retry,
        );
      },
    );
  }
}

/// Media stays inside its single custom Message. The lease retains image-byte
/// resources, not another item collection; lazy rows declare only attachment ids.
class TimelineAttachmentsConnector extends StatefulWidget {
  const TimelineAttachmentsConnector({
    super.key,
    required this.item,
    required this.resources,
    required this.readAttachment,
    required this.isActive,
    this.readContent,
  });
  final ChatItemPresentation item;
  final TimelineImageResources resources;
  final Future<Uint8List> Function(String attachmentId)? readAttachment;
  final bool Function() isActive;
  final ChatContentRead? readContent;
  @override
  State<TimelineAttachmentsConnector> createState() =>
      _TimelineAttachmentsConnectorState();
}

class _TimelineAttachmentsConnectorState
    extends State<TimelineAttachmentsConnector> {
  final Object _imageOwner = Object();
  List<ThreadAttachmentView> _attachments = const [];
  Object? _error;
  TimelineFilesPresentation? _files;
  bool _loading = false;
  final Set<String> _busyIds = {};
  final Map<String, String> _operationErrors = {};
  int _generation = 0;
  @override
  void initState() {
    super.initState();
    _bind();
  }

  void _bind() {
    ++_generation;
    _busyIds.clear();
    _operationErrors.clear();
    _files = null;
    _error = null;
    _loading = false;
    if (widget.item.presentationContract == 'builtin.show_files@1') {
      final body = widget.item.body('tool.output-artifacts');
      if (body?.inline != null) {
        try {
          _acceptFiles(utf8.decode(body!.inline!));
        } catch (error) {
          _error = error;
        }
      } else if (body?.reference != null) {
        _loading = true;
        _loadFiles(body!, _generation);
      } else {
        _error = const FormatException('缺少文件展示回执');
      }
      return;
    }
    try {
      _attachments = widget.item.attachments;
      widget.resources.retainItem(_imageOwner, _attachments);
      _error = null;
    } on FormatException catch (error) {
      _error = error;
    }
  }

  void _acceptFiles(String artifacts) {
    final files = TimelineFilesPresentation.fromArtifacts(artifacts);
    _files = files;
    _attachments = [for (final file in files.files) ?file.attachment];
    widget.resources.retainItem(_imageOwner, _attachments);
  }

  Future<void> _loadFiles(ChatBodyPresentation body, int generation) async {
    bool current() => mounted && generation == _generation && widget.isActive();
    try {
      final read = widget.readContent;
      if (read == null || !current()) throw StateError('文件展示回执读取尚未就绪');
      final bytes = BytesBuilder(copy: false);
      String? revision;
      while (bytes.length < body.byteLength) {
        final offset = bytes.length;
        final remaining = body.byteLength - offset;
        final limit = remaining < 65536 ? remaining : 65536;
        final window = await read(
          body.reference!,
          ContentRange(offset: offset, maxBytes: limit),
        );
        if (!current()) return;
        if (window.offset != offset ||
            window.bytes.isEmpty ||
            window.bytes.length > limit ||
            window.availableThrough != body.byteLength ||
            (revision != null && revision != window.generation)) {
          throw const FormatException('文件展示回执读取不连续或已换代');
        }
        revision = window.generation;
        bytes.add(window.bytes);
      }
      if (!current()) return;
      setState(() {
        _acceptFiles(utf8.decode(bytes.takeBytes()));
        _loading = false;
      });
    } catch (error) {
      if (!current()) return;
      setState(() {
        _loading = false;
        _error = error;
      });
    }
  }

  @override
  void didUpdateWidget(covariant TimelineAttachmentsConnector oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.resources, widget.resources) ||
        oldWidget.item.id != widget.item.id ||
        (widget.item.raw == null && !identical(oldWidget.item, widget.item)) ||
        oldWidget.item.raw != widget.item.raw) {
      if (!identical(oldWidget.resources, widget.resources)) {
        oldWidget.resources.dropItem(_imageOwner);
      }
      // Equal immutable envelopes retain receipt reads, save operations and the
      // original image ledger even when a parent decodes a fresh value object.
      _bind();
    }
  }

  @override
  void dispose() {
    ++_generation;
    widget.resources.dropItem(_imageOwner);
    _attachments = const [];
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('附件读取失败：$_error'),
          TextButton(
            onPressed: widget.isActive() ? () => setState(_bind) : null,
            child: const Text('重试'),
          ),
        ],
      );
    }
    return TimelineAttachmentsView(
      attachments: _attachments,
      files: _files?.files,
      caption: _files?.caption,
      busyIds: _busyIds,
      errors: _operationErrors,
      onOpen: FileReadingScope.maybeOf(context) == null
          ? null
          : (file) {
              final read = widget.readAttachment;
              final attachment = file.attachment;
              if (read == null || attachment == null || !widget.isActive()) {
                return;
              }
              // The panel borrows the original attachment authority, not the
              // widget mount (virtualization may remove this row while reading).
              final active = widget.isActive;
              FileReadingScope.maybeOf(context)!.onOpen(
                FileReadingRequest(
                  identity: (
                    widget.resources.threadId,
                    widget.item.id,
                    attachment.id,
                  ),
                  filename: file.filename,
                  readBytes: () => read(attachment.id),
                  isActive: active,
                ),
              );
            },
      onSave: widget.readAttachment == null
          ? null
          : (file) => _operate(file, false),
      onReveal: (file) => _operate(file, true),
      imageBuilder: (attachment) {
        final read = widget.readAttachment;
        if (read == null) return const Text('图片读取尚未就绪');
        return TimelineImageConnector(
          key: ValueKey((widget.resources, attachment.id)),
          itemId: widget.item.id,
          attachment: attachment,
          isTool: widget.item.type == 'tool',
          resources: widget.resources,
          readBytes: () => read(attachment.id),
          isActive: widget.isActive,
        );
      },
    );
  }

  Future<void> _operate(TimelineFileEntry file, bool reveal) async {
    final id = file.attachment?.id;
    if (id == null || _busyIds.contains(id) || !widget.isActive()) return;
    final generation = _generation;
    final active = widget.isActive;
    bool current() => mounted && generation == _generation && active();
    setState(() {
      _busyIds.add(id);
      _operationErrors.remove(id);
    });
    try {
      if (reveal) {
        if (file.origin != TimelineFileOrigin.local || file.localPath == null) {
          throw StateError('文件没有有效的本地来源');
        }
        await revealLocalFile(file.localPath!, isActive: current);
      } else {
        final read = widget.readAttachment!;
        await saveArchivedFile(
          filename: file.filename,
          readBytes: () => read(id),
          isActive: current,
        );
      }
    } catch (error) {
      if (current()) setState(() => _operationErrors[id] = error.toString());
    } finally {
      if (current()) setState(() => _busyIds.remove(id));
    }
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
      return const MetaData(
        metaData: ContentLayoutWitness.nonContent,
        child: SelectionContainer.disabled(child: Text('外部图片不可加载')),
      );
    }
    if (!_load) {
      return MetaData(
        metaData: ContentLayoutWitness.nonContent,
        child: SelectionContainer.disabled(
          child: TextButton.icon(
            onPressed: () => setState(() => _load = true),
            icon: const Icon(Icons.image_outlined),
            label: Text('加载外部图片 · ${uri.host}'),
          ),
        ),
      );
    }
    return Image.network(
      widget.url,
      height: 240,
      fit: BoxFit.contain,
      errorBuilder: (_, _, _) => const MetaData(
        metaData: ContentLayoutWitness.nonContent,
        child: Text('外部图片加载失败'),
      ),
    );
  }
}
