import 'package:freezed_annotation/freezed_annotation.dart';

import 'package:anywork_client/resources.dart';

import '../domain/skills_state.dart';

part 'skills_frames.freezed.dart';

@freezed
abstract class SkillsBaseline with _$SkillsBaseline {
  const factory SkillsBaseline({required SkillsHeader header, required ProductCollectionRef? collection}) =
      _SkillsBaseline;
}

@Freezed(toStringOverride: false)
final class SkillsChange with _$SkillsChange {
  SkillsChange({required this.header, required this.baseCollectionRevision,
    required this.collection, required List<ProductEntityRef> upserted,
    required List<int> removedEntries})
      : upserted = List.unmodifiable(upserted), removedEntries = List.unmodifiable(removedEntries);
  final SkillsHeader header;
  final int? baseCollectionRevision;
  final ProductCollectionRef? collection;
  final List<ProductEntityRef> upserted;
  final List<int> removedEntries;
}

@freezed
sealed class SkillsEvent with _$SkillsEvent {
  const factory SkillsEvent.baseline({required ProductFeedIdentity identity,
    required ProductProjectionStamp stamp, required SkillsBaseline value}) = SkillsBaselineEvent;
  const factory SkillsEvent.change({required ProductProjectionStamp stamp,
    required int baseRevision, required SkillsChange value}) = SkillsChangeEvent;
}

@Freezed(toStringOverride: false)
sealed class SkillsFrame with _$SkillsFrame {
  const factory SkillsFrame.data({required int deliverySequence, required SkillsEvent event}) = SkillsData;
  const factory SkillsFrame.resyncRequired({required ProductFeedIdentity identity,
    required ProductResyncReason reason}) = SkillsResyncRequired;
  const factory SkillsFrame.failure({required ProductFeedIdentity identity,
    required StudioFailure error}) = SkillsFeedFailure;
  const factory SkillsFrame.closed({required ProductFeedIdentity identity,
    required ProductFeedCloseReason reason}) = SkillsClosed;
}
