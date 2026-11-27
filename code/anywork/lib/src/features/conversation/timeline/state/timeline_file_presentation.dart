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
    this.deferredSize,
    this.networkImageUrl,
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
  final int? deferredSize;
  final String? networkImageUrl;

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
      if (artifact is! Map<String, Object?> ||
          !artifact.containsKey('fileDisplay')) {
        continue;
      }
      receipts.add(chatObject(artifact['fileDisplay'], 'fileDisplay'));
    }
    if (receipts.length != 1) {
      throw const FormatException('缺少唯一的 fileDisplay 回执');
    }
    return _decode(receipts.single);
  }

  static TimelineFilesPresentation _decode(Map<String, Object?> payload) {
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
    if (item['status'] == 'deferred') {
      final target = chatObject(item['target'], 'file.target');
      final size = chatInteger(target['size'], 'file.target.size');
      if (size < 0) throw const FormatException('file.target.size 不能为负数');
      return TimelineFileEntry(filename: filename, deferredSize: size);
    }
    if (item['status'] == 'networkImage') {
      return TimelineFileEntry(
        filename: filename,
        networkImageUrl: chatString(item['url'], 'file.url'),
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
