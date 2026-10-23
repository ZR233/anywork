import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:anywork_client/resources.dart';

import '../domain/directory_state.dart';

part 'agent_directory_frames.freezed.dart';

@freezed
abstract class AgentDirectoryBaseline with _$AgentDirectoryBaseline {
  const factory AgentDirectoryBaseline({required AgentDirectoryHeader header,
    required ProductCollectionRef? collection}) = _AgentDirectoryBaseline;
}

@Freezed(toStringOverride: false)
final class AgentDirectoryChange with _$AgentDirectoryChange {
  AgentDirectoryChange({required this.header, required this.baseCollectionRevision,
    required this.collection, required List<ProductEntityRef> upserted, required List<int> removedEntries})
      : upserted = List.unmodifiable(upserted), removedEntries = List.unmodifiable(removedEntries);
  final AgentDirectoryHeader header;
  final int? baseCollectionRevision;
  final ProductCollectionRef? collection;
  final List<ProductEntityRef> upserted;
  final List<int> removedEntries;
}

@freezed
sealed class AgentDirectoryEvent with _$AgentDirectoryEvent {
  const factory AgentDirectoryEvent.baseline({required ProductFeedIdentity identity,
    required ProductProjectionStamp stamp, required AgentDirectoryBaseline value}) = AgentDirectoryBaselineEvent;
  const factory AgentDirectoryEvent.change({required ProductProjectionStamp stamp,
    required int baseRevision, required AgentDirectoryChange value}) = AgentDirectoryChangeEvent;
}

@Freezed(toStringOverride: false)
sealed class AgentDirectoryFrame with _$AgentDirectoryFrame {
  const factory AgentDirectoryFrame.data({required int deliverySequence,
    required AgentDirectoryEvent event}) = AgentDirectoryData;
  const factory AgentDirectoryFrame.resyncRequired({required ProductFeedIdentity identity,
    required ProductResyncReason reason}) = AgentDirectoryResyncRequired;
  const factory AgentDirectoryFrame.failure({required ProductFeedIdentity identity,
    required StudioFailure error}) = AgentDirectoryFeedFailure;
  const factory AgentDirectoryFrame.closed({required ProductFeedIdentity identity,
    required ProductFeedCloseReason reason}) = AgentDirectoryClosed;
}
