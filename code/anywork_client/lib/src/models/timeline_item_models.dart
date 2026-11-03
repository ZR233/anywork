part of 'chat_models.dart';

/// Studio's display projection, not a client grouping instruction.
enum TimelineItemKind { text, workGroup, status }

enum TimelineCategory {
  thinking,
  read,
  image,
  command,
  search,
  edit,
  wait,
  other,
}

final class TimelineCategoryCount {
  const TimelineCategoryCount({required this.category, required this.count});
  final TimelineCategory category;
  final int count;
}

final class TimelineGroupSummary {
  TimelineGroupSummary({
    required this.memberCount,
    required this.activeCount,
    required this.failedCount,
    required this.cancelledCount,
    required List<TimelineCategoryCount> categories,
    this.startedAt,
    this.finishedAt,
  }) : categories = List.unmodifiable(categories);

  final int memberCount;
  final int activeCount;
  final int failedCount;
  final int cancelledCount;
  final List<TimelineCategoryCount> categories;
  final int? startedAt;
  final int? finishedAt;
}

/// The original reader validates all four fields before opening a member scope.
final class TimelineMembersRef {
  const TimelineMembersRef({
    required this.databaseId,
    required this.projectionVersion,
    required this.projectionGeneration,
    required this.itemId,
  });

  final String databaseId;
  final int projectionVersion;
  final String projectionGeneration;
  final String itemId;

  @override
  bool operator ==(Object other) =>
      other is TimelineMembersRef &&
      databaseId == other.databaseId &&
      projectionVersion == other.projectionVersion &&
      projectionGeneration == other.projectionGeneration &&
      itemId == other.itemId;

  @override
  int get hashCode =>
      Object.hash(databaseId, projectionVersion, projectionGeneration, itemId);
}

/// One Main message. A folded work group contains only a summary and member ref.
final class TimelineItem {
  TimelineItem({
    required this.id,
    required this.kind,
    required this.source,
    this.atomKind,
    required this.delivery,
    this.outcome,
    this.textChannel,
    this.turnId,
    this.startedAt,
    this.finishedAt,
    this.summary,
    this.members,
    required List<ChatAtomContent> contents,
    this.payload,
    this.contentItemId,
    this.position,
    required this.admissionClosed,
  }) : contents = List.unmodifiable(contents);

  final String id;
  final TimelineItemKind kind;
  final ChatSourceId source;
  final ChatAtomKind? atomKind;
  final ChatDeliveryKind delivery;

  /// The original text/status terminal outcome, never an inferred group result.
  final ChatTerminalOutcome? outcome;
  final ThreadTextChannel? textChannel;
  final String? turnId;
  final int? startedAt;
  final int? finishedAt;
  final TimelineGroupSummary? summary;
  final TimelineMembersRef? members;
  final List<ChatAtomContent> contents;
  final PayloadData? payload;
  final String? contentItemId;
  final int? position;
  final bool admissionClosed;
}
