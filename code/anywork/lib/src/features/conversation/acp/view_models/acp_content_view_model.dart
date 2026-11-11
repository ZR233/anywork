import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:anywork_client/acp_sessions.dart';
import 'package:anywork_client/models.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../timeline/state/patch_presentation.dart';
import '../../timeline/state/tool_presentation.dart';

final acpImageViewModelProvider = FutureProvider.autoDispose
    .family<AcpImagePresentation, AcpImageContentView>((ref, content) async {
      final bytes = base64Decode(content.data);
      final codec = await ui.instantiateImageCodec(bytes);
      try {
        final frame = await codec.getNextFrame();
        try {
          return AcpImagePresentation(
            bytes,
            ThreadAttachmentView(
              id: content.uri ?? 'acp-image',
              modality: AttachmentModalityView.image,
              mediaType: content.mimeType,
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
    });

final class AcpImagePresentation {
  const AcpImagePresentation(this.bytes, this.attachment);
  final Uint8List bytes;
  final ThreadAttachmentView attachment;
}

/// Only adapts display values. Tool updates are already merged by the Client.
TimelineToolPresentation acpToolPresentation(
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
  arguments: acpJsonText(fields.rawInput),
  output: acpJsonText(fields.rawOutput),
);

String acpJsonText(AcpJsonValue? value) => switch (value) {
  null => '',
  AcpJsonNull() => 'null',
  AcpJsonBool(:final value) => '$value',
  AcpJsonInteger(:final value) => '$value',
  AcpJsonDecimal(:final value) => '$value',
  AcpJsonString(:final value) => jsonEncode(value),
  AcpJsonArray(:final values) => '[${values.map(acpJsonText).join(', ')}]',
  AcpJsonObject(:final values) =>
    '{${values.entries.map((entry) => '${jsonEncode(entry.key)}: ${acpJsonText(entry.value)}').join(', ')}}',
};

TimelinePatchDocument acpDiffPresentation(AcpToolDiffView diff) =>
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
