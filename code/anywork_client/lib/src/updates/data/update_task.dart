import 'package:freezed_annotation/freezed_annotation.dart';

import 'package:anywork_client/resources.dart';

import '../domain/updates_state.dart';

part 'update_task.freezed.dart';

@freezed
abstract class UpdateTaskIdentity with _$UpdateTaskIdentity {
  const factory UpdateTaskIdentity({
    required String runtimeEpoch,
    required String taskId,
    required OperationId operationId,
  }) = _UpdateTaskIdentity;
}

@Freezed(toStringOverride: false)
abstract class UpdateTaskCloseReport with _$UpdateTaskCloseReport {
  const factory UpdateTaskCloseReport({
    required UpdateTaskIdentity identity,
    required FeedCloseOutcome outcome,
  }) = _UpdateTaskCloseReport;
}

/// No events/ACK: all canonical progress belongs exclusively to Updates feed.
abstract interface class UpdateTaskConnection {
  UpdateTaskIdentity get identity;
  Future<void> start();
  Future<UpdatesReadTarget> finish();
  void requestCancel();
  Future<UpdateTaskCloseReport> close();
  Future<UpdateTaskCloseReport> retryClose();
}
