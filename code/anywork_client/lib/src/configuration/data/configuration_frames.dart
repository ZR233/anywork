import 'package:freezed_annotation/freezed_annotation.dart';

import '../../../resources.dart';
import '../domain/configuration_state.dart';

part 'configuration_frames.freezed.dart';

@Freezed(toStringOverride: false)
sealed class ConfigurationFrame with _$ConfigurationFrame {
  const factory ConfigurationFrame.data({required int deliverySequence, required ConfigurationEvent event}) = ConfigurationData;
  const factory ConfigurationFrame.resyncRequired({required ProductFeedIdentity identity, required ProductResyncReason reason}) = ConfigurationResyncRequired;
  const factory ConfigurationFrame.failure({required ProductFeedIdentity identity, required StudioFailure error}) = ConfigurationFeedFailure;
  const factory ConfigurationFrame.closed({required ProductFeedIdentity identity, required ProductFeedCloseReason reason}) = ConfigurationClosed;
}

@Freezed(toStringOverride: false)
sealed class ConfigurationEvent with _$ConfigurationEvent {
  const factory ConfigurationEvent.baseline({required ProductFeedIdentity identity, required ProductProjectionStamp stamp, required ConfigurationBaseline value}) = ConfigurationBaselineEvent;
  const factory ConfigurationEvent.change({required ProductProjectionStamp stamp, required int baseRevision, required ConfigurationChange value}) = ConfigurationChangeEvent;
}

@Freezed(toStringOverride: false)
abstract class ConfigurationBaseline with _$ConfigurationBaseline {
  const factory ConfigurationBaseline({required ConfigurationHeader header, required ProductCollectionRef? collection}) = _ConfigurationBaseline;
}

@Freezed(toStringOverride: false)
final class ConfigurationChange with _$ConfigurationChange {
  ConfigurationChange({required this.header, required this.baseCollectionRevision, required this.collection, required List<ProductEntityRef> upserted, required List<int> removedEntries}) : upserted = List.unmodifiable(upserted), removedEntries = List.unmodifiable(removedEntries);
  final ConfigurationHeader header;
  final int? baseCollectionRevision;
  final ProductCollectionRef? collection;
  final List<ProductEntityRef> upserted;
  final List<int> removedEntries;
}

@Freezed(toStringOverride: false)
sealed class AgentProfilesFrame with _$AgentProfilesFrame {
  const factory AgentProfilesFrame.data({required int deliverySequence, required AgentProfilesEvent event}) = AgentProfilesData;
  const factory AgentProfilesFrame.resyncRequired({required ProductFeedIdentity identity, required ProductResyncReason reason}) = AgentProfilesResyncRequired;
  const factory AgentProfilesFrame.failure({required ProductFeedIdentity identity, required StudioFailure error}) = AgentProfilesFeedFailure;
  const factory AgentProfilesFrame.closed({required ProductFeedIdentity identity, required ProductFeedCloseReason reason}) = AgentProfilesClosed;
}

@Freezed(toStringOverride: false)
sealed class AgentProfilesEvent with _$AgentProfilesEvent {
  const factory AgentProfilesEvent.baseline({required ProductFeedIdentity identity, required ProductProjectionStamp stamp, required AgentProfilesBaseline value}) = AgentProfilesBaselineEvent;
  const factory AgentProfilesEvent.change({required ProductProjectionStamp stamp, required int baseRevision, required AgentProfilesChange value}) = AgentProfilesChangeEvent;
}

@Freezed(toStringOverride: false)
abstract class AgentProfilesBaseline with _$AgentProfilesBaseline {
  const factory AgentProfilesBaseline({required AgentProfilesHeader header, required ProductCollectionRef? collection}) = _AgentProfilesBaseline;
}

@Freezed(toStringOverride: false)
final class AgentProfilesChange with _$AgentProfilesChange {
  AgentProfilesChange({required this.header, required this.baseCollectionRevision, required this.collection, required List<ProductEntityRef> upserted, required List<int> removedEntries}) : upserted = List.unmodifiable(upserted), removedEntries = List.unmodifiable(removedEntries);
  final AgentProfilesHeader header;
  final int? baseCollectionRevision;
  final ProductCollectionRef? collection;
  final List<ProductEntityRef> upserted;
  final List<int> removedEntries;
}
