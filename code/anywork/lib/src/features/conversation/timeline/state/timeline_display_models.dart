import 'package:anywork_client/models.dart';

/// Wall-clock interval owned by the producer, in Unix milliseconds.
final class WorkTiming {
  const WorkTiming({required this.startedAtMillis, this.finishedAtMillis});
  final int? startedAtMillis;
  final int? finishedAtMillis;

  @override
  bool operator ==(Object other) =>
      other is WorkTiming &&
      startedAtMillis == other.startedAtMillis &&
      finishedAtMillis == other.finishedAtMillis;
  @override
  int get hashCode => Object.hash(startedAtMillis, finishedAtMillis);
}

enum DisplayBlockState { open, sealed }

final class WorkDisplayBlock {
  const WorkDisplayBlock({
    required this.timing,
    required this.executionPresent,
    required this.memberCount,
    required this.unfinishedCount,
    required this.groupClosed,
    this.feedGroup,
    this.summary,
  });

  final WorkTiming timing;
  final bool executionPresent;
  final int memberCount;
  final int unfinishedCount;
  final bool groupClosed;
  final TimelineWorkGroup? feedGroup;
  final String? summary;
}

final class DisplayBlock {
  const DisplayBlock({
    required this.id,
    required this.blockOrder,
    required this.body,
  });
  final String id;
  final int blockOrder;
  final WorkDisplayBlock body;
}

bool sameDisplayBlock(DisplayBlock first, DisplayBlock second) =>
    first.id == second.id &&
    first.blockOrder == second.blockOrder &&
    first.body.timing == second.body.timing &&
    first.body.executionPresent == second.body.executionPresent &&
    first.body.memberCount == second.body.memberCount &&
    first.body.unfinishedCount == second.body.unfinishedCount &&
    first.body.groupClosed == second.body.groupClosed &&
    first.body.feedGroup == second.body.feedGroup &&
    first.body.summary == second.body.summary;
