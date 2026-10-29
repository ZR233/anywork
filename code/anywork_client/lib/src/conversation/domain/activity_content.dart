import '../../models/thread_activity_models.dart';
import '../../models/thread_wait_models.dart';

/// Identity is typed; the identifier is never interpreted to infer a region.
enum ActivityRegionKind { reasoning, response, toolArguments, toolOutput }

final class ActivityRegion {
  const ActivityRegion(this.kind, this.id)
    : partId = null,
      assert(kind != ActivityRegionKind.toolOutput);
  const ActivityRegion.toolOutput({
    required String callId,
    required String partId,
  }) : kind = ActivityRegionKind.toolOutput,
       id = callId,
       partId = partId;
  final ActivityRegionKind kind;
  final String id;
  final String? partId;
  @override
  bool operator ==(Object other) =>
      other is ActivityRegion &&
      kind == other.kind &&
      id == other.id &&
      partId == other.partId;
  @override
  int get hashCode => Object.hash(kind, id, partId);
}

final class ActivityPartMetadata {
  const ActivityPartMetadata({
    required this.itemId,
    required this.complete,
    required this.totalBytes,
  });
  final String itemId;
  final bool complete;
  final int totalBytes;
}

final class ActivityToolMetadata {
  ActivityToolMetadata({
    required this.callId,
    required this.name,
    required this.state,
    this.taskId,
    this.startedAt,
    this.sourceOrder,
    this.argumentsBytes,
    this.outputBytes,
    required List<ActivityToolOutputMetadata> outputParts,
    this.wait,
  }) : outputParts = List.unmodifiable(outputParts);
  final String callId;
  final String? taskId;
  final String name;
  final ThreadActivityToolState state;
  final int? startedAt;
  final int? sourceOrder;
  final int? argumentsBytes;
  final int? outputBytes;
  final List<ActivityToolOutputMetadata> outputParts;
  final ThreadWaitPresentationView? wait;
}

final class ActivityToolOutputMetadata {
  const ActivityToolOutputMetadata({
    required this.partId,
    required this.totalBytes,
  });
  final String partId;
  final int totalBytes;
}

sealed class ActivityTextOperation {
  const ActivityTextOperation(this.region);
  final ActivityRegion region;
}

final class ActivityAppend extends ActivityTextOperation {
  const ActivityAppend(super.region, this.text);
  final String text;
}

final class ActivityReplace extends ActivityTextOperation {
  const ActivityReplace(super.region, this.text);
  final String text;
}

final class ActivityRemove extends ActivityTextOperation {
  const ActivityRemove(super.region);
}

sealed class ActivityContentFrame {
  const ActivityContentFrame(this.generation, this.revision);
  final String generation;
  final int revision;
}

final class ActivityBegin extends ActivityContentFrame {
  ActivityBegin({
    required String generation,
    required int revision,
    required this.baseRevision,
    required this.activity,
    required List<ActivityPartMetadata> reasoning,
    required List<ActivityPartMetadata> response,
    required List<ActivityToolMetadata> tools,
    required this.totalBytes,
  }) : reasoning = List.unmodifiable(reasoning),
       response = List.unmodifiable(response),
       tools = List.unmodifiable(tools),
       super(generation, revision);
  final int? baseRevision;
  final ThreadActivityView? activity;
  final List<ActivityPartMetadata> reasoning;
  final List<ActivityPartMetadata> response;
  final List<ActivityToolMetadata> tools;
  final int totalBytes;
}

final class ActivityText extends ActivityContentFrame {
  ActivityText({
    required String generation,
    required int revision,
    required List<ActivityTextOperation> operations,
  }) : operations = List.unmodifiable(operations),
       super(generation, revision);
  final List<ActivityTextOperation> operations;
}

final class ActivityCommit extends ActivityContentFrame {
  const ActivityCommit({required String generation, required int revision})
    : super(generation, revision);
}

/// Committed current value; unlike the old detail query this is an observation snapshot.
final class CurrentActivity {
  CurrentActivity({
    required this.generation,
    required this.revision,
    required this.activity,
    required List<ThreadActivityContentPart> reasoning,
    required List<ThreadActivityContentPart> response,
    required List<ThreadActivityToolDetail> tools,
  }) : reasoning = List.unmodifiable(reasoning),
       response = List.unmodifiable(response),
       tools = List.unmodifiable(tools);
  final String generation;
  final int revision;
  final ThreadActivityView? activity;
  final List<ThreadActivityContentPart> reasoning;
  final List<ThreadActivityContentPart> response;
  final List<ThreadActivityToolDetail> tools;
}

enum ActivityRecoveryReason {
  continuity,
  invalidFrame,
  lengthMismatch,
  budgetExceeded,
}

/// The feed owner must request a fresh activity snapshot rather than query detail.
final class ActivitySnapshotRequired implements Exception {
  const ActivitySnapshotRequired(this.reason, this.message);
  final ActivityRecoveryReason reason;
  final String message;
  @override
  String toString() => 'Activity snapshot required ($reason): $message';
}
