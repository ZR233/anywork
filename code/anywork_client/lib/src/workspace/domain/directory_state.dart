import 'package:freezed_annotation/freezed_annotation.dart';

import 'package:anywork_client/resources.dart';

import 'directory_values.dart';

part 'directory_state.freezed.dart';

@freezed
abstract class ProjectDirectoryReadRef with _$ProjectDirectoryReadRef {
  const factory ProjectDirectoryReadRef({required int entry, required int revision}) =
      _ProjectDirectoryReadRef;
}

@freezed
abstract class ThreadDirectoryReadRef with _$ThreadDirectoryReadRef {
  const factory ThreadDirectoryReadRef({required int entry, required int revision}) =
      _ThreadDirectoryReadRef;
}

@freezed
abstract class AgentDirectoryReadRef with _$AgentDirectoryReadRef {
  const factory AgentDirectoryReadRef({required int entry, required int revision}) =
      _AgentDirectoryReadRef;
}

@freezed
abstract class ProjectDirectoryReadTarget with _$ProjectDirectoryReadTarget {
  const factory ProjectDirectoryReadTarget({
    required ProductReadOrigin origin,
    required ProjectDirectoryReadRef reference,
  }) = _ProjectDirectoryReadTarget;
}

@freezed
abstract class ThreadDirectoryReadTarget with _$ThreadDirectoryReadTarget {
  const factory ThreadDirectoryReadTarget({
    required ProductReadOrigin origin,
    required ThreadDirectoryReadRef reference,
  }) = _ThreadDirectoryReadTarget;
}

@freezed
abstract class AgentDirectoryReadTarget with _$AgentDirectoryReadTarget {
  const factory AgentDirectoryReadTarget({
    required ProductReadOrigin origin,
    required AgentDirectoryReadRef reference,
  }) = _AgentDirectoryReadTarget;
}

@freezed
abstract class ProjectDirectoryHeader with _$ProjectDirectoryHeader {
  const factory ProjectDirectoryHeader({
    required ObservedHeader source,
    required ProjectDirectoryReadRef? reference,
  }) = _ProjectDirectoryHeader;
}

@freezed
abstract class ThreadDirectoryHeader with _$ThreadDirectoryHeader {
  const factory ThreadDirectoryHeader({
    required ObservedHeader source,
    required ThreadDirectoryReadRef? reference,
    required int? directoryRevision,
    required int? searchProjectRevision,
    required bool? hasMore,
    required ReadText? nextCursor,
  }) = _ThreadDirectoryHeader;
}

@freezed
abstract class AgentDirectoryHeader with _$AgentDirectoryHeader {
  const factory AgentDirectoryHeader({
    required ObservedHeader source,
    required AgentDirectoryReadRef? reference,
  }) = _AgentDirectoryHeader;
}

@Freezed(toStringOverride: false)
abstract class ProjectDirectoryState with _$ProjectDirectoryState {
  const factory ProjectDirectoryState({
    required ProductProjection<ProjectDirectoryHeader> projection,
    required ReadValue<ProductSourceStatus, ProductSourceStatusRef>? sourceStatus,
    required CollectionMirror<ProjectRecord> projects,
  }) = _ProjectDirectoryState;
}

@Freezed(toStringOverride: false)
abstract class ThreadDirectoryState with _$ThreadDirectoryState {
  const factory ThreadDirectoryState({
    required ProductProjection<ThreadDirectoryHeader> projection,
    required ThreadDirectoryScope scope,
    required ReadValue<ProductSourceStatus, ProductSourceStatusRef>? sourceStatus,
    required CollectionMirror<WorkspaceThreadRecord> threads,
  }) = _ThreadDirectoryState;
}

@Freezed(toStringOverride: false)
abstract class AgentDirectoryState with _$AgentDirectoryState {
  const factory AgentDirectoryState({
    required ProductProjection<AgentDirectoryHeader> projection,
    required ReadValue<ProductSourceStatus, ProductSourceStatusRef>? sourceStatus,
    required CollectionMirror<AgentDirectoryEntry> agents,
  }) = _AgentDirectoryState;
}

@Freezed(toStringOverride: false)
abstract class ThreadMetadataState with _$ThreadMetadataState {
  const factory ThreadMetadataState({
    required ProductProjection<ThreadDirectoryHeader> projection,
    required ReadValue<ProductSourceStatus, ProductSourceStatusRef>? sourceStatus,
    required ReadValue<WorkspaceThreadRecord, ProductEntityRef>? value,
    StudioFailure? readError,
  }) = _ThreadMetadataState;
}
