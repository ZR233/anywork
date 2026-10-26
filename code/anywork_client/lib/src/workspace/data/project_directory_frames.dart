import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:anywork_client/resources.dart';

import '../domain/directory_state.dart';

part 'project_directory_frames.freezed.dart';

@freezed
abstract class ProjectDirectoryBaseline with _$ProjectDirectoryBaseline {
  const factory ProjectDirectoryBaseline({
    required ProjectDirectoryHeader header,
    required ProductCollectionRef? collection,
  }) = _ProjectDirectoryBaseline;
}

@Freezed(toStringOverride: false)
final class ProjectDirectoryChange with _$ProjectDirectoryChange {
  ProjectDirectoryChange({
    required this.header,
    required this.baseCollectionRevision,
    required this.collection,
    required List<ProductEntityRef> upserted,
    required List<int> removedEntries,
  }) : upserted = List.unmodifiable(upserted),
       removedEntries = List.unmodifiable(removedEntries);
  final ProjectDirectoryHeader header;
  final int? baseCollectionRevision;
  final ProductCollectionRef? collection;
  final List<ProductEntityRef> upserted;
  final List<int> removedEntries;
}

@freezed
sealed class ProjectDirectoryEvent with _$ProjectDirectoryEvent {
  const factory ProjectDirectoryEvent.baseline({
    required ProductFeedIdentity identity,
    required ProductProjectionStamp stamp,
    required ProjectDirectoryBaseline value,
  }) = ProjectDirectoryBaselineEvent;
  const factory ProjectDirectoryEvent.change({
    required ProductProjectionStamp stamp,
    required int baseRevision,
    required ProjectDirectoryChange value,
  }) = ProjectDirectoryChangeEvent;
}

@Freezed(toStringOverride: false)
sealed class ProjectDirectoryFrame with _$ProjectDirectoryFrame {
  const factory ProjectDirectoryFrame.data({
    required int deliverySequence,
    required ProjectDirectoryEvent event,
  }) = ProjectDirectoryData;
  const factory ProjectDirectoryFrame.resyncRequired({
    required ProductFeedIdentity identity,
    required ProductResyncReason reason,
  }) = ProjectDirectoryResyncRequired;
  const factory ProjectDirectoryFrame.failure({
    required ProductFeedIdentity identity,
    required StudioFailure error,
  }) = ProjectDirectoryFeedFailure;
  const factory ProjectDirectoryFrame.closed({
    required ProductFeedIdentity identity,
    required ProductFeedCloseReason reason,
  }) = ProjectDirectoryClosed;
}
