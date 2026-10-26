import 'package:freezed_annotation/freezed_annotation.dart';

import 'package:anywork_client/resources.dart';

part 'updates_reads.freezed.dart';

@Freezed(toStringOverride: false)
abstract class UpdateSummaryRead with _$UpdateSummaryRead {
  const factory UpdateSummaryRead({
    required ReadText version,
    required int publishedAt,
    required ReadText notesUrl,
  }) = _UpdateSummaryRead;
}

@Freezed(toStringOverride: false)
abstract class UpdateAssetRead with _$UpdateAssetRead {
  const factory UpdateAssetRead({
    required ReadText url,
    required int size,
    required ReadText sha256,
    required ReadText signature,
  }) = _UpdateAssetRead;
}

@Freezed(toStringOverride: false)
abstract class UpdateDetailsRead with _$UpdateDetailsRead {
  const factory UpdateDetailsRead({
    required UpdateSummaryRead summary,
    required UpdateAssetRead installer,
  }) = _UpdateDetailsRead;
}

@Freezed(toStringOverride: false)
abstract class UpdateOperationReadHeader with _$UpdateOperationReadHeader {
  const factory UpdateOperationReadHeader({required ReadText operationId}) =
      _UpdateOperationReadHeader;
}

@Freezed(toStringOverride: false)
sealed class UpdatesReadHeader with _$UpdatesReadHeader {
  const factory UpdatesReadHeader.disabled({
    required int revision,
    required int updatedAt,
  }) = DisabledUpdatesReadHeader;
  const factory UpdatesReadHeader.idle({
    required int revision,
    required int updatedAt,
  }) = IdleUpdatesReadHeader;
  const factory UpdatesReadHeader.checking({
    required int revision,
    required ReadText operationId,
    required int startedAt,
  }) = CheckingUpdatesReadHeader;
  const factory UpdatesReadHeader.upToDate({
    required int revision,
    required int checkedAt,
  }) = UpToDateUpdatesReadHeader;
  const factory UpdatesReadHeader.available({
    required int revision,
    required int checkedAt,
    required UpdateDetailsRead update,
  }) = AvailableUpdatesReadHeader;
  const factory UpdatesReadHeader.downloading({
    required int revision,
    required int updatedAt,
    required UpdateDetailsRead update,
    required int downloaded,
    required int total,
  }) = DownloadingUpdatesReadHeader;
  const factory UpdatesReadHeader.verifying({
    required int revision,
    required int updatedAt,
    required UpdateDetailsRead update,
    required int downloaded,
    required int total,
  }) = VerifyingUpdatesReadHeader;
  const factory UpdatesReadHeader.ready({
    required int revision,
    required int readyAt,
    required UpdateDetailsRead update,
  }) = ReadyUpdatesReadHeader;
  const factory UpdatesReadHeader.installerLaunched({
    required int revision,
    required int launchedAt,
    required UpdateDetailsRead update,
  }) = InstallerLaunchedUpdatesReadHeader;
  const factory UpdatesReadHeader.checkFailed({
    required int revision,
    required int failedAt,
    required SourceStateErrorRead error,
  }) = CheckFailedUpdatesReadHeader;
  const factory UpdatesReadHeader.installFailed({
    required int revision,
    required int failedAt,
    required UpdateDetailsRead update,
    required SourceStateErrorRead error,
  }) = InstallFailedUpdatesReadHeader;
}
