/// Stamps are comparable only inside the same owner and resource domain.
sealed class ObservationStamp {
  const ObservationStamp();

  String get resourceKey;

  bool covers(ObservationStamp target);
}

final class ResourceStamp extends ObservationStamp {
  const ResourceStamp({
    required this.resourceKey,
    required this.ownerEpoch,
    required this.revision,
  }) : assert(revision >= 0);

  @override
  final String resourceKey;
  final String ownerEpoch;
  final int revision;

  @override
  bool covers(ObservationStamp target) =>
      target is ResourceStamp &&
      resourceKey == target.resourceKey &&
      ownerEpoch == target.ownerEpoch &&
      revision >= target.revision;

  @override
  bool operator ==(Object other) =>
      other is ResourceStamp &&
      resourceKey == other.resourceKey &&
      ownerEpoch == other.ownerEpoch &&
      revision == other.revision;

  @override
  int get hashCode => Object.hash(resourceKey, ownerEpoch, revision);
}

final class ViewStamp extends ObservationStamp {
  const ViewStamp({
    required this.threadId,
    required this.viewId,
    required this.viewEpoch,
    required this.version,
  }) : assert(version >= 0);

  final String threadId;
  final String viewId;
  final String viewEpoch;
  final int version;

  @override
  String get resourceKey => 'chat:$threadId:$viewId';

  bool sameView(ViewStamp other) =>
      threadId == other.threadId &&
      viewId == other.viewId &&
      viewEpoch == other.viewEpoch;

  @override
  bool covers(ObservationStamp target) =>
      target is ViewStamp && sameView(target) && version >= target.version;

  ViewStamp atVersion(int next) => ViewStamp(
    threadId: threadId,
    viewId: viewId,
    viewEpoch: viewEpoch,
    version: next,
  );

  @override
  bool operator ==(Object other) =>
      other is ViewStamp && sameView(other) && version == other.version;

  @override
  int get hashCode => Object.hash(threadId, viewId, viewEpoch, version);
}

final class AttemptId {
  const AttemptId(this.value);
  final int value;

  @override
  bool operator ==(Object other) => other is AttemptId && value == other.value;

  @override
  int get hashCode => value.hashCode;
}

final class OperationId {
  const OperationId(this.value);
  final String value;

  @override
  bool operator ==(Object other) =>
      other is OperationId && value == other.value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => value;
}

final class DraftStamp {
  const DraftStamp({required this.draftId, required this.revision})
    : assert(revision >= 0);

  final String draftId;
  final int revision;

  @override
  bool operator ==(Object other) =>
      other is DraftStamp &&
      draftId == other.draftId &&
      revision == other.revision;

  @override
  int get hashCode => Object.hash(draftId, revision);
}
