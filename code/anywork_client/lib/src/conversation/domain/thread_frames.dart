import 'package:freezed_annotation/freezed_annotation.dart';

import '../../../resources.dart';
import 'authoring_values.dart';
import 'configuration_values.dart';
import 'context_values.dart';
import 'execution_values.dart';
import 'metrics_values.dart';
import 'thread_identity.dart';

part 'thread_frames.freezed.dart';

@Freezed(toStringOverride: false)
sealed class ThreadExecutionFrame with _$ThreadExecutionFrame {
  const factory ThreadExecutionFrame.data({required int deliverySequence, required ThreadExecutionEvent event}) = ThreadExecutionData;
  const factory ThreadExecutionFrame.resyncRequired({required ThreadFeedIdentity identity, required ThreadResyncReason reason}) = ThreadExecutionResyncRequired;
  const factory ThreadExecutionFrame.failure({required ThreadFeedIdentity identity, required StudioFailure error}) = ThreadExecutionFailure;
  const factory ThreadExecutionFrame.closed({required ThreadFeedIdentity identity, required ThreadFeedClosedReason reason}) = ThreadExecutionClosed;
}

@Freezed(toStringOverride: false)
sealed class ThreadExecutionEvent with _$ThreadExecutionEvent {
  const factory ThreadExecutionEvent.baseline({required ThreadFeedIdentity identity, required ThreadFacetStamp stamp, required ThreadExecutionBaseline value}) = ThreadExecutionBaselineEvent;
  const factory ThreadExecutionEvent.change({required ThreadFacetStamp stamp, required int baseRevision, required ThreadExecutionChange value}) = ThreadExecutionChangeEvent;
}

@Freezed(toStringOverride: false)
sealed class ThreadMetricsFrame with _$ThreadMetricsFrame {
  const factory ThreadMetricsFrame.data({required int deliverySequence, required ThreadMetricsEvent event}) = ThreadMetricsData;
  const factory ThreadMetricsFrame.resyncRequired({required ThreadFeedIdentity identity, required ThreadResyncReason reason}) = ThreadMetricsResyncRequired;
  const factory ThreadMetricsFrame.failure({required ThreadFeedIdentity identity, required StudioFailure error}) = ThreadMetricsFailure;
  const factory ThreadMetricsFrame.closed({required ThreadFeedIdentity identity, required ThreadFeedClosedReason reason}) = ThreadMetricsClosed;
}

@Freezed(toStringOverride: false)
sealed class ThreadMetricsEvent with _$ThreadMetricsEvent {
  const factory ThreadMetricsEvent.baseline({required ThreadFeedIdentity identity, required ThreadFacetStamp stamp, required ThreadMetricsValue value}) = ThreadMetricsBaselineEvent;
  const factory ThreadMetricsEvent.replace({required ThreadFacetStamp stamp, required ThreadMetricsValue value}) = ThreadMetricsReplaceEvent;
}

@Freezed(toStringOverride: false)
sealed class ThreadContextFrame with _$ThreadContextFrame {
  const factory ThreadContextFrame.data({required int deliverySequence, required ThreadContextEvent event}) = ThreadContextData;
  const factory ThreadContextFrame.resyncRequired({required ThreadFeedIdentity identity, required ThreadResyncReason reason}) = ThreadContextResyncRequired;
  const factory ThreadContextFrame.failure({required ThreadFeedIdentity identity, required StudioFailure error}) = ThreadContextFailure;
  const factory ThreadContextFrame.closed({required ThreadFeedIdentity identity, required ThreadFeedClosedReason reason}) = ThreadContextClosed;
}

@Freezed(toStringOverride: false)
sealed class ThreadContextEvent with _$ThreadContextEvent {
  const factory ThreadContextEvent.baseline({required ThreadFeedIdentity identity, required ThreadFacetStamp stamp, required ThreadContextValue value}) = ThreadContextBaselineEvent;
  const factory ThreadContextEvent.replace({required ThreadFacetStamp stamp, required ThreadContextValue value}) = ThreadContextReplaceEvent;
}

@Freezed(toStringOverride: false)
sealed class ThreadConfigurationFrame with _$ThreadConfigurationFrame {
  const factory ThreadConfigurationFrame.data({required int deliverySequence, required ThreadConfigurationEvent event}) = ThreadConfigurationData;
  const factory ThreadConfigurationFrame.resyncRequired({required ThreadFeedIdentity identity, required ThreadResyncReason reason}) = ThreadConfigurationResyncRequired;
  const factory ThreadConfigurationFrame.failure({required ThreadFeedIdentity identity, required StudioFailure error}) = ThreadConfigurationFailure;
  const factory ThreadConfigurationFrame.closed({required ThreadFeedIdentity identity, required ThreadFeedClosedReason reason}) = ThreadConfigurationClosed;
}

@Freezed(toStringOverride: false)
sealed class ThreadConfigurationEvent with _$ThreadConfigurationEvent {
  const factory ThreadConfigurationEvent.baseline({required ThreadFeedIdentity identity, required ThreadFacetStamp stamp, required ThreadConfigurationValue value}) = ThreadConfigurationBaselineEvent;
  const factory ThreadConfigurationEvent.replace({required ThreadFacetStamp stamp, required ThreadConfigurationValue value}) = ThreadConfigurationReplaceEvent;
}

@Freezed(toStringOverride: false)
sealed class ThreadAuthoringFrame with _$ThreadAuthoringFrame {
  const factory ThreadAuthoringFrame.data({required int deliverySequence, required ThreadAuthoringEvent event}) = ThreadAuthoringData;
  const factory ThreadAuthoringFrame.resyncRequired({required ThreadFeedIdentity identity, required ThreadResyncReason reason}) = ThreadAuthoringResyncRequired;
  const factory ThreadAuthoringFrame.failure({required ThreadFeedIdentity identity, required StudioFailure error}) = ThreadAuthoringFailure;
  const factory ThreadAuthoringFrame.closed({required ThreadFeedIdentity identity, required ThreadFeedClosedReason reason}) = ThreadAuthoringClosed;
}

@Freezed(toStringOverride: false)
sealed class ThreadAuthoringEvent with _$ThreadAuthoringEvent {
  const factory ThreadAuthoringEvent.baseline({required ThreadFeedIdentity identity, required ThreadFacetStamp stamp, required ThreadAuthoringBaseline value}) = ThreadAuthoringBaselineEvent;
  const factory ThreadAuthoringEvent.change({required ThreadFacetStamp stamp, required int baseRevision, required ThreadAuthoringChange value}) = ThreadAuthoringChangeEvent;
}
