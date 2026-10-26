import 'package:freezed_annotation/freezed_annotation.dart';

import 'package:anywork_client/resources.dart';

import 'skills_values.dart';

part 'skills_state.freezed.dart';

@freezed
abstract class SkillsReadRef with _$SkillsReadRef {
  const factory SkillsReadRef({required int entry, required int revision}) =
      _SkillsReadRef;
}

@freezed
abstract class SkillsReadTarget with _$SkillsReadTarget {
  const factory SkillsReadTarget({
    required ProductReadOrigin origin,
    required SkillsReadRef reference,
  }) = _SkillsReadTarget;
}

@freezed
abstract class SkillsHeader with _$SkillsHeader {
  const factory SkillsHeader({
    required ObservedHeader source,
    required SkillsReadRef? reference,
    required int? catalogRevision,
    required bool? complete,
  }) = _SkillsHeader;
}

@Freezed(toStringOverride: false)
abstract class SkillsState with _$SkillsState {
  const factory SkillsState({
    required ProductProjection<SkillsHeader> projection,
    required String projectId,
    required ReadValue<ProductSourceStatus, ProductSourceStatusRef>?
    sourceStatus,
    required CollectionMirror<SkillSummary> skills,
    required ReadValue<List<String>, SkillsReadRef>? warnings,
    required ReadValue<String, SkillsReadRef>? projectDirectory,
    required ReadValue<String, SkillsReadRef>? configFingerprint,
  }) = _SkillsState;
}
