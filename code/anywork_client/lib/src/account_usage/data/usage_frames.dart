import 'package:freezed_annotation/freezed_annotation.dart';

import '../../../resources.dart';
import '../domain/usage_state.dart';

part 'usage_frames.freezed.dart';

@Freezed(toStringOverride: false)
sealed class AccountUsageFrame with _$AccountUsageFrame {
  const factory AccountUsageFrame.data({required int deliverySequence, required AccountUsageEvent event}) = AccountUsageDataFrame;
  const factory AccountUsageFrame.resyncRequired({required ProductFeedIdentity identity, required ProductResyncReason reason}) = AccountUsageResyncRequired;
  const factory AccountUsageFrame.failure({required ProductFeedIdentity identity, required StudioFailure error}) = AccountUsageFeedFailure;
  const factory AccountUsageFrame.closed({required ProductFeedIdentity identity, required ProductFeedCloseReason reason}) = AccountUsageClosed;
}

@Freezed(toStringOverride: false)
sealed class AccountUsageEvent with _$AccountUsageEvent {
  const factory AccountUsageEvent.baseline({required ProductFeedIdentity identity, required ProductProjectionStamp stamp, required AccountUsageBaseline value}) = AccountUsageBaselineEvent;
  const factory AccountUsageEvent.change({required ProductProjectionStamp stamp, required int baseRevision, required AccountUsageChange value}) = AccountUsageChangeEvent;
}

@Freezed(toStringOverride: false)
abstract class AccountUsageBaseline with _$AccountUsageBaseline {
  const factory AccountUsageBaseline({required AccountUsageHeader header, required ProductCollectionRef? collection}) = _AccountUsageBaseline;
}

@Freezed(toStringOverride: false)
abstract class AccountUsageChange with _$AccountUsageChange {
  const factory AccountUsageChange({required AccountUsageHeader header, required int? baseCollectionRevision, required ProductCollectionRef? collection, required List<ProductEntityRef> upserted, required List<int> removedEntries}) = _AccountUsageChange;
}
