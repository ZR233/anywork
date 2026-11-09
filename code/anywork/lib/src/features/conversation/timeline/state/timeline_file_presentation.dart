import 'dart:convert';

import 'package:anywork_client/models.dart';
import 'package:path/path.dart' as p;

import 'chat_payload_reading.dart';

enum TimelineFileOrigin { local, remote, archive }

/// Immutable presentation facts. Bytes belong to the original attachment owner,
/// not this value or the timeline's view state.
final class TimelineFileEntry {
  const TimelineFileEntry({
    required this.filename,
    this.attachment,
    this.origin = TimelineFileOrigin.archive,
    this.localPath,
    this.error,
  });

  factory TimelineFileEntry.archived(ThreadAttachmentView attachment) =>
      TimelineFileEntry(
        filename: attachment.filename ?? attachment.mediaType,
        attachment: attachment,
      );

  final String filename;
  final ThreadAttachmentView? attachment;
  final TimelineFileOrigin origin;
  final String? localPath;
  final String? error;

  bool get isMarkdown =>
      const {'.md', '.markdown'}.contains(p.extension(filename).toLowerCase());
}

final class TimelineFilesPresentation {
  const TimelineFilesPresentation({required this.files, this.caption});

  final String? caption;
  final List<TimelineFileEntry> files;

  static TimelineFilesPresentation fromArtifacts(String text) {
    final artifacts = jsonDecode(text);
    if (artifacts is! List) {
      throw const FormatException('tool.output-artifacts 必须是数组');
    }
    final receipts = <Map<String, Object?>>[];
    for (final artifact in artifacts) {
      if (artifact is! Map<String, Object?> || artifact['kind'] != 'opaque') {
        continue;
      }
      final payload = chatObject(artifact['payload'], 'opaque.payload');
      if (payload['format'] == 'pl.tool.files') receipts.add(payload);
    }
    if (receipts.length != 1 || receipts.single['version'] != 1) {
      throw const FormatException('缺少或不支持 pl.tool.files@1 回执');
    }
    final content = chatString(
      receipts.single['content'],
      'opaque.payload.content',
    );
    return decode(jsonDecode(content));
  }

  /// Decodes only the producer's `pl.tool.files@1` payload, after the existing
  /// completion adapter has selected the explicit opaque format/version.
  static TimelineFilesPresentation decode(Object? value) {
    final payload = chatObject(value, 'pl.tool.files');
    final entries = payload['files'];
    if (entries is! List) {
      throw const FormatException('files 必须是数组');
    }
    return TimelineFilesPresentation(
      caption: chatOptionalString(payload['caption'], 'caption'),
      files: List.unmodifiable(entries.map(_entry)),
    );
  }

  static TimelineFileEntry _entry(Object? value) {
    final item = chatObject(value, 'file');
    final filename = chatString(item['filename'], 'file.filename');
    if (item['status'] == 'failed') {
      return TimelineFileEntry(
        filename: filename,
        error: chatString(item['message'], 'file.message'),
      );
    }
    if (item['status'] != 'ready') {
      throw const FormatException('未知文件展示状态');
    }
    final resource = chatObject(item['resource'], 'file.resource');
    final origin = chatObject(item['origin'], 'file.origin');
    final kind = chatEnum(
      TimelineFileOrigin.values,
      origin['kind'],
      'file.origin.kind',
    );
    final path = kind == TimelineFileOrigin.local
        ? chatString(origin['path'], 'file.origin.path')
        : null;
    if (path != null && !p.isAbsolute(path)) {
      throw const FormatException('本地文件来源必须是当前设备绝对路径');
    }
    // ResourceReference's canonical serde names come from pl-core; an
    // attachment id is that original resource id, never a synthetic card id.
    chatString(resource['contentDigest'], 'resource.contentDigest');
    return TimelineFileEntry(
      filename: filename,
      origin: kind,
      localPath: path,
      attachment: ThreadAttachmentView(
        id: chatString(resource['id'], 'resource.id'),
        modality: chatEnum(
          AttachmentModalityView.values,
          item['modality'],
          'file.modality',
        ),
        mediaType: chatString(resource['mediaType'], 'resource.mediaType'),
        byteSize: chatInteger(resource['byteLen'], 'resource.byteLen'),
        filename: filename,
      ),
    );
  }
}
