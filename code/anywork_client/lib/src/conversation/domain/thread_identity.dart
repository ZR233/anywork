import 'package:freezed_annotation/freezed_annotation.dart';

part 'thread_identity.freezed.dart';

enum ThreadFacet { execution, metrics, context, configuration, authoring }
enum ThreadObservationMode { live, cold }
enum ThreadResyncReason { sourceLagged, reliableQueueFull, revisionGap }
enum ThreadFeedClosedReason { requested, ownerReplaced, runtimeStopped }

@freezed
abstract class ThreadFacetStamp with _$ThreadFacetStamp {
  const factory ThreadFacetStamp({
    required String runtimeEpoch,
    required int incarnation,
    required ThreadFacet facet,
    required int revision,
  }) = _ThreadFacetStamp;
}

@freezed
abstract class ThreadFeedIdentity with _$ThreadFeedIdentity {
  const factory ThreadFeedIdentity({
    required String feedId,
    required String runtimeEpoch,
    required int incarnation,
    required ThreadFacet facet,
    required ThreadObservationMode mode,
  }) = _ThreadFeedIdentity;
}

// These indices are scoped to a projection incarnation. They are never command IDs.
@freezed
abstract class TurnReadRef with _$TurnReadRef {
  const factory TurnReadRef({required int entry, required int revision}) = _TurnReadRef;
}

@freezed
abstract class InteractionReadRef with _$InteractionReadRef {
  const factory InteractionReadRef({required int entry, required int revision}) = _InteractionReadRef;
}

@freezed
abstract class InteractionIndexRef with _$InteractionIndexRef {
  const factory InteractionIndexRef({required int entry, required int revision}) = _InteractionIndexRef;
}

@freezed
abstract class ActivityReadRef with _$ActivityReadRef {
  const factory ActivityReadRef({required int entry, required int revision}) = _ActivityReadRef;
}

@freezed
abstract class StorageReadRef with _$StorageReadRef {
  const factory StorageReadRef({required int entry, required int revision}) = _StorageReadRef;
}

@freezed
abstract class MetricsIdentityRef with _$MetricsIdentityRef {
  const factory MetricsIdentityRef({required int entry}) = _MetricsIdentityRef;
}

@freezed
abstract class ContextReadRef with _$ContextReadRef {
  const factory ContextReadRef({required int entry, required int revision}) = _ContextReadRef;
}

@freezed
abstract class ThreadConfigurationReadRef with _$ThreadConfigurationReadRef {
  const factory ThreadConfigurationReadRef({required int entry, required int revision}) = _ThreadConfigurationReadRef;
}

@freezed
abstract class TodoReadRef with _$TodoReadRef {
  const factory TodoReadRef({required int entry, required int revision}) = _TodoReadRef;
}

@freezed
abstract class WorkflowReadRef with _$WorkflowReadRef {
  const factory WorkflowReadRef({required int entry, required int revision}) = _WorkflowReadRef;
}
