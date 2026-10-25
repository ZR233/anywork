import 'package:freezed_annotation/freezed_annotation.dart';

import 'package:anywork_client/resources.dart';

part 'update_values.freezed.dart';

@freezed
abstract class UpdateControls with _$UpdateControls {
  const factory UpdateControls({required bool enabled}) = _UpdateControls;
}

@freezed
abstract class UpdatePreparationResult with _$UpdatePreparationResult {
  const factory UpdatePreparationResult({required String? readyVersion}) =
      _UpdatePreparationResult;
}

@Freezed(toStringOverride: false)
abstract class UpdateSummary with _$UpdateSummary {
  const factory UpdateSummary({
    required String version,
    required int publishedAt,
    required String notesUrl,
  }) = _UpdateSummary;
}

@Freezed(toStringOverride: false)
abstract class UpdateAsset with _$UpdateAsset {
  const factory UpdateAsset({
    required String url,
    required int size,
    required String sha256,
    required String signature,
  }) = _UpdateAsset;
}

@Freezed(toStringOverride: false)
abstract class UpdateDetails with _$UpdateDetails {
  const factory UpdateDetails({
    required UpdateSummary summary,
    required UpdateAsset installer,
  }) = _UpdateDetails;
}

@Freezed(toStringOverride: false)
sealed class UpdatesValue with _$UpdatesValue {
  const factory UpdatesValue.disabled({
    required int revision,
    required int updatedAt,
  }) = DisabledUpdatesValue;
  const factory UpdatesValue.idle({
    required int revision,
    required int updatedAt,
  }) = IdleUpdatesValue;
  const factory UpdatesValue.checking({
    required int revision,
    required String operationId,
    required int startedAt,
  }) = CheckingUpdatesValue;
  const factory UpdatesValue.upToDate({
    required int revision,
    required int checkedAt,
  }) = UpToDateUpdatesValue;
  const factory UpdatesValue.available({
    required int revision,
    required int checkedAt,
    required UpdateSummary update,
  }) = AvailableUpdatesValue;
  const factory UpdatesValue.downloading({
    required int revision,
    required int updatedAt,
    required UpdateSummary update,
    required int downloaded,
    required int total,
  }) = DownloadingUpdatesValue;
  const factory UpdatesValue.verifying({
    required int revision,
    required int updatedAt,
    required UpdateSummary update,
    required int downloaded,
    required int total,
  }) = VerifyingUpdatesValue;
  const factory UpdatesValue.ready({
    required int revision,
    required int readyAt,
    required UpdateSummary update,
  }) = ReadyUpdatesValue;
  const factory UpdatesValue.installerLaunched({
    required int revision,
    required int launchedAt,
    required UpdateSummary update,
  }) = InstallerLaunchedUpdatesValue;
  const factory UpdatesValue.checkFailed({
    required int revision,
    required int failedAt,
    required SourceStateError error,
  }) = CheckFailedUpdatesValue;
  const factory UpdatesValue.installFailed({
    required int revision,
    required int failedAt,
    required UpdateSummary update,
    required SourceStateError error,
  }) = InstallFailedUpdatesValue;
}
