import 'package:freezed_annotation/freezed_annotation.dart';

import 'package:anywork_client/resources.dart';

import '../domain/mcp_state.dart';

part 'mcp_frames.freezed.dart';

@freezed
abstract class McpBaseline with _$McpBaseline {
  const factory McpBaseline({
    required McpHeader header,
    required ProductCollectionRef? collection,
  }) = _McpBaseline;
}

@Freezed(toStringOverride: false)
final class McpChange with _$McpChange {
  McpChange({
    required this.header,
    required this.baseCollectionRevision,
    required this.collection,
    required List<ProductEntityRef> upserted,
    required List<int> removedEntries,
  }) : upserted = List.unmodifiable(upserted),
       removedEntries = List.unmodifiable(removedEntries);
  final McpHeader header;
  final int? baseCollectionRevision;
  final ProductCollectionRef? collection;
  final List<ProductEntityRef> upserted;
  final List<int> removedEntries;
}

@freezed
sealed class McpEvent with _$McpEvent {
  const factory McpEvent.baseline({
    required ProductFeedIdentity identity,
    required ProductProjectionStamp stamp,
    required McpBaseline value,
  }) = McpBaselineEvent;
  const factory McpEvent.change({
    required ProductProjectionStamp stamp,
    required int baseRevision,
    required McpChange value,
  }) = McpChangeEvent;
}

@Freezed(toStringOverride: false)
sealed class McpFrame with _$McpFrame {
  const factory McpFrame.data({
    required int deliverySequence,
    required McpEvent event,
  }) = McpData;
  const factory McpFrame.resyncRequired({
    required ProductFeedIdentity identity,
    required ProductResyncReason reason,
  }) = McpResyncRequired;
  const factory McpFrame.failure({
    required ProductFeedIdentity identity,
    required StudioFailure error,
  }) = McpFeedFailure;
  const factory McpFrame.closed({
    required ProductFeedIdentity identity,
    required ProductFeedCloseReason reason,
  }) = McpClosed;
}
