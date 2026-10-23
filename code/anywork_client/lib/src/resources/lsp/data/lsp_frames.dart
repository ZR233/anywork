import 'package:freezed_annotation/freezed_annotation.dart';

import 'package:anywork_client/resources.dart';

import '../domain/lsp_state.dart';

part 'lsp_frames.freezed.dart';

@freezed
abstract class LspBaseline with _$LspBaseline {
  const factory LspBaseline({required LspHeader header, required ProductCollectionRef? collection}) =
      _LspBaseline;
}

@Freezed(toStringOverride: false)
final class LspChange with _$LspChange {
  LspChange({required this.header, required this.baseCollectionRevision,
    required this.collection, required List<ProductEntityRef> upserted,
    required List<int> removedEntries})
      : upserted = List.unmodifiable(upserted), removedEntries = List.unmodifiable(removedEntries);
  final LspHeader header;
  final int? baseCollectionRevision;
  final ProductCollectionRef? collection;
  final List<ProductEntityRef> upserted;
  final List<int> removedEntries;
}

@freezed
sealed class LspEvent with _$LspEvent {
  const factory LspEvent.baseline({required ProductFeedIdentity identity,
    required ProductProjectionStamp stamp, required LspBaseline value}) = LspBaselineEvent;
  const factory LspEvent.change({required ProductProjectionStamp stamp,
    required int baseRevision, required LspChange value}) = LspChangeEvent;
}

@Freezed(toStringOverride: false)
sealed class LspFrame with _$LspFrame {
  const factory LspFrame.data({required int deliverySequence, required LspEvent event}) = LspData;
  const factory LspFrame.resyncRequired({required ProductFeedIdentity identity,
    required ProductResyncReason reason}) = LspResyncRequired;
  const factory LspFrame.failure({required ProductFeedIdentity identity,
    required StudioFailure error}) = LspFeedFailure;
  const factory LspFrame.closed({required ProductFeedIdentity identity,
    required ProductFeedCloseReason reason}) = LspClosed;
}
