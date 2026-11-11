import 'dart:convert';
import 'dart:ui' as ui;

import 'package:anywork_client/acp_sessions.dart';
import 'package:anywork_client/models.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../timeline/state/patch_presentation.dart';
import '../../timeline/state/tool_presentation.dart';
import '../state/acp_view_state.dart';

part 'acp_content_view_model.g.dart';

const int _maxSafeExternalUrlBytes = 8 * 1024;
final RegExp _controlCharacters = RegExp(r'[\u0000-\u001F\u007F-\u009F]');

bool isSafeAcpExternalWebUrl(String value) {
  if (utf8.encode(value).length > _maxSafeExternalUrlBytes) {
    return false;
  }
  final sanitized = value.replaceAll(_controlCharacters, '');
  final uri = Uri.tryParse(sanitized);
  if (uri == null || uri.host.isEmpty) {
    return false;
  }
  final scheme = uri.scheme.toLowerCase();
  return scheme == 'http' || scheme == 'https';
}

@riverpod
Future<AcpDecodedImagePresentation> acpDecodedImage(
  Ref ref,
  AcpImagePayload image,
) async {
  final bytes = base64Decode(image.dataBase64);
  final codec = await ui.instantiateImageCodec(bytes);
  try {
    final frame = await codec.getNextFrame();
    try {
      return AcpDecodedImagePresentation(
        bytes: bytes,
        attachment: ThreadAttachmentView(
          id: image.uri ?? image.cacheKey,
          modality: AttachmentModalityView.image,
          mediaType: image.mimeType,
          byteSize: bytes.length,
          width: frame.image.width,
          height: frame.image.height,
        ),
      );
    } finally {
      frame.image.dispose();
    }
  } finally {
    codec.dispose();
  }
}

AcpContentBlockPresentation mapAcpContentBlock(
  AcpContentBlockView content, {
  required String fallbackKey,
}) => switch (content) {
  AcpTextContentView(:final text) => AcpContentBlockPresentation.text(
    text: text,
  ),
  AcpImageContentView(:final data, :final mimeType, :final uri) =>
    AcpContentBlockPresentation.image(
      cacheKey: uri ?? fallbackKey,
      dataBase64: data,
      mimeType: mimeType,
      uri: uri,
    ),
  AcpAudioContentView(:final mimeType) => AcpContentBlockPresentation.audio(
    mimeType: mimeType,
  ),
  AcpResourceLinkView(
    :final title,
    :final name,
    :final uri,
    :final description,
    :final mimeType,
  ) =>
    AcpContentBlockPresentation.resourceLink(
      label: (title != null && title.trim().isNotEmpty) ? title : name,
      uri: uri,
      description: description,
      mimeType: mimeType,
      canOpenExternal: isSafeAcpExternalWebUrl(uri),
    ),
  AcpEmbeddedResourceView(
    resource: AcpTextResourceContentsView(
      :final uri,
      :final text,
      :final mimeType,
    ),
  ) =>
    AcpContentBlockPresentation.textResource(
      uri: uri,
      text: text,
      mimeType: mimeType,
    ),
  AcpEmbeddedResourceView(
    resource: AcpBlobResourceContentsView(
      :final uri,
      :final blob,
      :final mimeType,
    ),
  ) =>
    AcpContentBlockPresentation.blobResource(
      uri: uri,
      mimeType: mimeType,
      byteCount: _decodedBase64Length(blob),
    ),
};

int _decodedBase64Length(String encoded) {
  if (encoded.isEmpty) return 0;
  try {
    return base64Decode(encoded).length;
  } on FormatException {
    return (encoded.length * 3) ~/ 4;
  }
}

/// Adjacent text chunks form one Markdown document without mutating or trimming
/// canonical Client chunks.
List<AcpContentBlockPresentation> mapAcpMessageBlocks(
  AcpConversationMessageItem item, {
  required String itemId,
}) {
  final blocks = <AcpContentBlockPresentation>[];
  var text = StringBuffer();
  var blockIndex = 0;

  void flush() {
    if (text.isEmpty) return;
    blocks.add(AcpContentBlockPresentation.text(text: text.toString()));
    text = StringBuffer();
    blockIndex++;
  }

  for (final chunk in item.chunks) {
    if (chunk.content case AcpTextContentView(text: final value)) {
      text.write(value);
    } else {
      flush();
      blocks.add(
        mapAcpContentBlock(
          chunk.content,
          fallbackKey: '$itemId:block:$blockIndex',
        ),
      );
      blockIndex++;
    }
  }
  flush();
  return blocks;
}

String summarizeThoughtBlocks(List<AcpContentBlockPresentation> blocks) {
  for (final block in blocks) {
    if (block case AcpTextBlockPresentation(:final text)) {
      for (final rawLine in text.split('\n')) {
        final cleaned = rawLine
            .replaceAll(RegExp(r'^[#*>\-\s`]+'), '')
            .replaceAll('`', '')
            .trim();
        if (cleaned.isNotEmpty) {
          return cleaned;
        }
      }
    }
  }
  return '';
}

/// Only adapts display values. Tool updates are already merged by the Client.
TimelineToolPresentation mapAcpToolPresentation(
  AcpToolCallId id,
  AcpToolCallUpdateFieldsView fields,
) => TimelineToolPresentation(
  id: id.value,
  toolCallId: id.value,
  name: fields.title ?? fields.name ?? id.value,
  presentationContract: 'acp.tool',
  statusString: switch (fields.status) {
    AcpToolCallStatusView.completed => 'succeeded',
    AcpToolCallStatusView.failed => 'failed',
    AcpToolCallStatusView.pending => 'pending',
    AcpToolCallStatusView.inProgress => 'running',
    null => 'unknown',
  },
  arguments: formatAcpJsonText(fields.rawInput),
  output: formatAcpJsonText(fields.rawOutput),
);

AcpToolStatusKind mapAcpToolStatus(AcpToolCallStatusView? status) =>
    switch (status) {
      AcpToolCallStatusView.pending => AcpToolStatusKind.pending,
      AcpToolCallStatusView.inProgress => AcpToolStatusKind.inProgress,
      AcpToolCallStatusView.completed => AcpToolStatusKind.completed,
      AcpToolCallStatusView.failed => AcpToolStatusKind.failed,
      null => AcpToolStatusKind.unknown,
    };

String formatAcpJsonText(AcpJsonValue? value) => switch (value) {
  null => '',
  AcpJsonNull() => 'null',
  AcpJsonBool(:final value) => '$value',
  AcpJsonInteger(:final value) => '$value',
  AcpJsonDecimal(:final value) => '$value',
  AcpJsonString(:final value) => jsonEncode(value),
  AcpJsonArray(:final values) =>
    '[${values.map(formatAcpJsonText).join(', ')}]',
  AcpJsonObject(:final values) =>
    '{${values.entries.map((entry) => '${jsonEncode(entry.key)}: ${formatAcpJsonText(entry.value)}').join(', ')}}',
};

TimelinePatchDocument mapAcpDiffPresentation(AcpToolDiffView diff) =>
    TimelinePatchDocument(
      files: [
        TimelinePatchFile(
          op: diff.oldText == null
              ? TimelinePatchFileOp.add
              : TimelinePatchFileOp.update,
          path: diff.path,
          chunks: [
            TimelinePatchChunk(
              context: null,
              lines: [
                if (diff.oldText case final old?)
                  for (final line in old.split('\n'))
                    TimelinePatchLine(
                      kind: TimelinePatchLineKind.deletion,
                      text: line,
                    ),
                for (final line in diff.newText.split('\n'))
                  TimelinePatchLine(
                    kind: TimelinePatchLineKind.addition,
                    text: line,
                  ),
              ],
            ),
          ],
        ),
      ],
    );

String formatCompactBigIntTokens(BigInt value) {
  if (value < BigInt.from(1000)) return value.toString();
  final intVal = value.toInt();
  if (intVal >= 1000000) {
    final millions = intVal / 1000000;
    return '${millions.toStringAsFixed(millions >= 10 ? 0 : 1)}M';
  }
  final thousands = intVal / 1000;
  return '${thousands.toStringAsFixed(thousands >= 100 ? 0 : 1)}k';
}

bool hasConversationalAcpContent(List<AcpConversationContentItem> content) {
  for (final item in content) {
    switch (item) {
      case AcpConversationMessageItem():
      case AcpConversationToolItem():
        return true;
      case AcpConversationUpdateItem(:final update):
        if (update is AcpNoticeView || update is AcpCompactionUpdateView) {
          return true;
        }
    }
  }
  return false;
}

AcpUpdatePresentation mapAcpUpdatePresentation(
  AcpSessionUpdateView update, {
  bool superseded = false,
}) => switch (update) {
  AcpNoticeView(:final title, :final description) =>
    AcpUpdatePresentation.notice(title: title, description: description),
  AcpUsageUpdateView(:final used, :final size, :final cost) =>
    superseded
        ? const AcpUpdatePresentation.superseded()
        : AcpUpdatePresentation.usage(
            usedFormatted: formatCompactBigIntTokens(used),
            sizeFormatted: formatCompactBigIntTokens(size),
            costLabel: cost == null ? null : '${cost.amount} ${cost.currency}',
          ),
  AcpCompactionUpdateView(:final status, :final error) =>
    AcpUpdatePresentation.compaction(
      statusLabel: status.other ?? status.kind.name,
      errorMessage: error is AcpFieldValue<String> ? error.value : null,
    ),
  AcpAvailableCommandsUpdateView(:final commands) =>
    superseded || commands.isEmpty
        ? const AcpUpdatePresentation.superseded()
        : AcpUpdatePresentation.availableCommands(
            commands: [
              for (final command in commands)
                (name: command.name, description: command.description),
            ],
          ),
  AcpSessionInfoUpdateView() => const AcpUpdatePresentation.superseded(),
  _ => const AcpUpdatePresentation.generic(),
};

AcpTimelineItemPresentation mapAcpTimelineItem({
  required String threadId,
  required int index,
  required AcpConversationContentItem item,
  required bool isLastAndRunning,
  bool supersededUpdate = false,
}) {
  final itemId = '$threadId:$index';
  return switch (item) {
    AcpConversationMessageItem(kind: AcpConversationMessageKind.user) =>
      AcpTimelineItemPresentation.userMessage(
        id: itemId,
        blocks: mapAcpMessageBlocks(item, itemId: itemId),
      ),
    AcpConversationMessageItem(kind: AcpConversationMessageKind.assistant) =>
      AcpTimelineItemPresentation.assistantMessage(
        id: itemId,
        blocks: mapAcpMessageBlocks(item, itemId: itemId),
      ),
    AcpConversationMessageItem(kind: AcpConversationMessageKind.thought) => () {
      final blocks = mapAcpMessageBlocks(item, itemId: itemId);
      return AcpTimelineItemPresentation.thought(
        id: itemId,
        summary: summarizeThoughtBlocks(blocks),
        blocks: blocks,
        active: isLastAndRunning,
      );
    }(),
    AcpConversationToolItem(:final toolCallId, :final fields) => () {
      final locations = <String>[
        for (final loc in fields.locations ?? const <AcpToolCallLocationView>[])
          '${loc.path}${loc.line == null ? '' : ':${loc.line}'}',
      ];
      final terminals = <String>[];
      final diffs = <TimelinePatchDocument>[];
      final contentBlocks = <AcpContentBlockPresentation>[];
      final toolContents = fields.content ?? const <AcpToolCallContentView>[];
      for (var i = 0; i < toolContents.length; i++) {
        switch (toolContents[i]) {
          case AcpToolTerminalView(:final terminalId):
            terminals.add(terminalId.value);
          case final AcpToolDiffView diff:
            diffs.add(mapAcpDiffPresentation(diff));
          case AcpToolContentView(:final content):
            contentBlocks.add(
              mapAcpContentBlock(
                content,
                fallbackKey: '$itemId:tool:${toolCallId.value}:$i',
              ),
            );
        }
      }
      return AcpTimelineItemPresentation.toolCall(
        id: itemId,
        toolCallId: toolCallId.value,
        tool: mapAcpToolPresentation(toolCallId, fields),
        status: mapAcpToolStatus(fields.status),
        kindLabel: fields.kind?.name,
        locations: locations,
        terminals: terminals,
        diffs: diffs,
        contentBlocks: contentBlocks,
      );
    }(),
    AcpConversationUpdateItem(:final update) =>
      AcpTimelineItemPresentation.sessionUpdate(
        id: itemId,
        update: mapAcpUpdatePresentation(update, superseded: supersededUpdate),
      ),
  };
}

AcpUsagePresentation? extractLatestAcpUsage(
  List<AcpConversationContentItem> content,
) {
  for (var i = content.length - 1; i >= 0; i--) {
    final entry = content[i];
    if (entry case AcpConversationUpdateItem(
      update: AcpUsageUpdateView(:final used, :final size, :final cost),
    )) {
      final denom = size > BigInt.zero ? size.toDouble() : 0.0;
      final ratio = denom > 0 ? (used.toDouble() / denom).clamp(0.0, 1.0) : 0.0;
      return AcpUsagePresentation(
        usedFormatted: formatCompactBigIntTokens(used),
        sizeFormatted: formatCompactBigIntTokens(size),
        ratio: ratio,
        costLabel: cost == null ? null : '${cost.amount} ${cost.currency}',
      );
    }
  }
  return null;
}
