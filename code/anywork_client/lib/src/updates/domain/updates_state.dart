import 'package:freezed_annotation/freezed_annotation.dart';

import 'package:anywork_client/resources.dart';

import 'update_values.dart';

part 'updates_state.freezed.dart';

@freezed
abstract class UpdatesReadRef with _$UpdatesReadRef {
  const factory UpdatesReadRef({required int entry, required int revision}) =
      _UpdatesReadRef;
}

@freezed
abstract class UpdatesReadTarget with _$UpdatesReadTarget {
  const factory UpdatesReadTarget({
    required ProductReadOrigin origin,
    required UpdatesReadRef reference,
  }) = _UpdatesReadTarget;
}

@freezed
abstract class UpdateSummaryReadRef with _$UpdateSummaryReadRef {
  const factory UpdateSummaryReadRef({
    required int entry,
    required int revision,
  }) = _UpdateSummaryReadRef;
}

@freezed
abstract class UpdateOperationReadRef with _$UpdateOperationReadRef {
  const factory UpdateOperationReadRef({
    required int entry,
    required int revision,
  }) = _UpdateOperationReadRef;
}

@freezed
abstract class UpdateErrorReadRef with _$UpdateErrorReadRef {
  const factory UpdateErrorReadRef({
    required int entry,
    required int revision,
  }) = _UpdateErrorReadRef;
}

@freezed
abstract class UpdateDetailsReadRef with _$UpdateDetailsReadRef {
  const factory UpdateDetailsReadRef({
    required int entry,
    required int revision,
  }) = _UpdateDetailsReadRef;
}

@freezed
sealed class UpdatesBrief with _$UpdatesBrief {
  const factory UpdatesBrief.disabled({
    required int revision,
    required int updatedAt,
  }) = DisabledUpdatesBrief;
  const factory UpdatesBrief.idle({
    required int revision,
    required int updatedAt,
  }) = IdleUpdatesBrief;
  const factory UpdatesBrief.checking({
    required int revision,
    required int startedAt,
  }) = CheckingUpdatesBrief;
  const factory UpdatesBrief.upToDate({
    required int revision,
    required int checkedAt,
  }) = UpToDateUpdatesBrief;
  const factory UpdatesBrief.available({
    required int revision,
    required int checkedAt,
  }) = AvailableUpdatesBrief;
  const factory UpdatesBrief.downloading({
    required int revision,
    required int updatedAt,
    required int downloaded,
    required int total,
  }) = DownloadingUpdatesBrief;
  const factory UpdatesBrief.verifying({
    required int revision,
    required int updatedAt,
    required int downloaded,
    required int total,
  }) = VerifyingUpdatesBrief;
  const factory UpdatesBrief.ready({
    required int revision,
    required int readyAt,
  }) = ReadyUpdatesBrief;
  const factory UpdatesBrief.installerLaunched({
    required int revision,
    required int launchedAt,
  }) = InstallerLaunchedUpdatesBrief;
  const factory UpdatesBrief.checkFailed({
    required int revision,
    required int failedAt,
    required bool retryable,
  }) = CheckFailedUpdatesBrief;
  const factory UpdatesBrief.installFailed({
    required int revision,
    required int failedAt,
    required bool retryable,
  }) = InstallFailedUpdatesBrief;
}

@freezed
abstract class UpdatesHeader with _$UpdatesHeader {
  const factory UpdatesHeader({
    required UpdatesReadRef reference,
    required UpdatesBrief brief,
    required UpdateSummaryReadRef? summary,
    required UpdateOperationReadRef? operation,
    required UpdateErrorReadRef? error,
    required UpdateDetailsReadRef? details,
  }) = _UpdatesHeader;
}

@Freezed(toStringOverride: false)
abstract class UpdatesState with _$UpdatesState {
  const factory UpdatesState({
    required ProductProjection<UpdatesHeader> projection,
    required ReadValue<UpdatesValue, UpdatesReadRef>? value,
  }) = _UpdatesState;
}
