import 'package:freezed_annotation/freezed_annotation.dart';

part 'identity.freezed.dart';

/// Versions can only cover evidence from the same resource and owner.
sealed class ObservationStamp {
  const ObservationStamp();

  String get resourceKey;
  bool covers(ObservationStamp target);
}

@freezed
abstract class ResourceStamp extends ObservationStamp with _$ResourceStamp {
  const ResourceStamp._();

  @Assert('revision >= 0')
  const factory ResourceStamp({
    required String resourceKey,
    required String ownerEpoch,
    required int revision,
  }) = _ResourceStamp;

  @override
  bool covers(ObservationStamp target) =>
      target is ResourceStamp &&
      resourceKey == target.resourceKey &&
      ownerEpoch == target.ownerEpoch &&
      revision >= target.revision;
}

@freezed
abstract class ViewStamp extends ObservationStamp with _$ViewStamp {
  const ViewStamp._();

  @Assert('version >= 0')
  const factory ViewStamp({
    required String threadId,
    required String viewId,
    required String viewEpoch,
    required int version,
  }) = _ViewStamp;

  /// Human-readable label only; observation lookup uses the typed identity.
  @override
  String get resourceKey => 'chat:$threadId:$viewId';

  bool sameView(ViewStamp other) =>
      threadId == other.threadId &&
      viewId == other.viewId &&
      viewEpoch == other.viewEpoch;

  @override
  bool covers(ObservationStamp target) =>
      target is ViewStamp && sameView(target) && version >= target.version;

  ViewStamp atVersion(int next) => copyWith(version: next);
}

@freezed
abstract class AttemptId with _$AttemptId {
  const factory AttemptId(int value) = _AttemptId;
}

@freezed
abstract class OperationId with _$OperationId {
  const factory OperationId(String value) = _OperationId;
}

@freezed
abstract class DraftStamp with _$DraftStamp {
  @Assert('revision >= 0')
  const factory DraftStamp({required String draftId, required int revision}) =
      _DraftStamp;
}

@freezed
abstract class ReadScopeIdentity with _$ReadScopeIdentity {
  const factory ReadScopeIdentity({
    required String scopeId,
    required String runtimeEpoch,
    required int incarnation,
    required int sourceRevision,
  }) = _ReadScopeIdentity;
}
