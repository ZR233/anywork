import 'package:anywork_client/conversation.dart';

/// GUI grouping from the current display, not another grouping implementation.
/// All canonical members remain present even when one visible skill row takes
/// over its paired skill_view invocation.
final class TimelinePresentationFacts {
  TimelinePresentationFacts({
    required this.id,
    required this.kind,
    required this.ordinal,
    required List<String> memberIds,
    required List<String> visibleMemberIds,
    required Map<String, String> skillPairs,
    required this.expanded,
    required this.activeCount,
    required this.issueCount,
  }) : memberIds = List.unmodifiable(memberIds),
       visibleMemberIds = List.unmodifiable(visibleMemberIds),
       skillPairs = Map.unmodifiable(skillPairs);

  final String id;
  final String kind;
  final int ordinal;
  final List<String> memberIds;
  final List<String> visibleMemberIds;
  final Map<String, String> skillPairs;
  final bool expanded;
  final int activeCount;
  final int issueCount;
}

/// A request-local, already bounded and redacted canonical preview.
/// Never include secret answers, complete records, raw/expanded detail payloads
/// or a controller Message. The producer uses the existing display payload;
/// diagnostics does not parse tool arguments or build another row projection.
final class TimelineItemFacts {
  TimelineItemFacts({
    required this.id,
    required this.ordinal,
    required this.revision,
    required this.saved,
    required this.terminal,
    required this.omittedBytes,
    required this.kind,
    required this.status,
    required this.text,
    required this.channel,
    required List<TimelineDetailFacts> details,
    required List<TimelineAttachmentFacts> attachments,
    required this.tool,
    required this.userInput,
  }) : details = List.unmodifiable(details),
       attachments = List.unmodifiable(attachments);

  final String id;
  final int ordinal;
  final int revision;
  final bool saved;
  final bool terminal;
  final int omittedBytes;
  final String kind;
  final String status;
  final String text;

  /// Actual ThreadTextItemStateView.channel; non-text items have null.
  /// agentMessage alone does not distinguish commentary from finalAnswer.
  final ThreadTextChannel? channel;
  final List<TimelineDetailFacts> details;
  final List<TimelineAttachmentFacts> attachments;
  final TimelineToolFacts? tool;
  final TimelineUserInputFacts? userInput;
}

/// Existing bounded tool preview, not a detail read or complete arguments.
final class TimelineToolFacts {
  TimelineToolFacts({
    required this.name,
    required this.status,
    required this.callId,
    required this.arguments,
    required this.result,
    required this.progressBytes,
    required this.itemRevision,
    required this.denialReason,
    required this.workingDirectory,
    required this.exitCode,
    required List<TimelineAttachmentFacts> attachments,
  }) : attachments = List.unmodifiable(attachments);

  final String name;
  final String status;
  final String callId;
  final String arguments;
  final String? result;
  final int progressBytes;
  final int itemRevision;
  final String? denialReason;
  final String? workingDirectory;
  final int? exitCode;
  final List<TimelineAttachmentFacts> attachments;
}

/// Stable typed-field token plus byte counts, never the full detail body.
final class TimelineDetailFacts {
  const TimelineDetailFacts({
    required this.field,
    required this.revision,
    required this.totalBytes,
    required this.previewBytes,
  });
  final String field;
  final int revision;
  final int totalBytes;
  final int previewBytes;
}

/// Metadata only: no original image bytes, path lease, or native resource handle.
final class TimelineAttachmentFacts {
  const TimelineAttachmentFacts({
    required this.id,
    required this.modality,
    required this.filename,
    required this.byteSize,
    required this.source,
  });
  final String id;
  final String modality;
  final String filename;
  final int byteSize;
  final String? source;
}

/// Identity/disposition only. Questions and answers (secret or otherwise) are
/// not fields of this diagnostic. Plan identity is from the same typed receipt,
/// not guessed from a current Plan or from tool text.
final class TimelineUserInputFacts {
  const TimelineUserInputFacts({
    required this.interactionId,
    required this.state,
    required this.isPlanConfirmation,
    required this.planDecision,
  });
  final String interactionId;
  final String state;
  final bool isPlanConfirmation;
  final String? planDecision;
}
