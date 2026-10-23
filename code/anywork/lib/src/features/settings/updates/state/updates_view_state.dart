import 'package:anywork_client/resources.dart';
import 'package:anywork_client/updates.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

import '../../state/settings_action.dart';

part 'updates_view_state.freezed.dart';

enum UpdateSettingsAction { check, prepare, cancel }
enum UpdatesReadField { value, summary }

@freezed
abstract class UpdateRestartRequest with _$UpdateRestartRequest {
  const factory UpdateRestartRequest({required int intent, required String version}) = _UpdateRestartRequest;
}

@Freezed(toStringOverride: false)
abstract class UpdatesViewState with _$UpdatesViewState {
  const UpdatesViewState._();
  const factory UpdatesViewState({
    required UpdatesState source,
    required UpdateControls controls,
    required String currentVersion,
    UpdateSummary? summary,
    ProductReadOrigin? summaryOrigin,
    UpdateSummaryReadRef? summaryReference,
    @Default(false) bool readingSummary,
    @Default(false) bool readingValue,
    @Default(0) int latestIntent,
    int? consumedRestartIntent,
    @Default({}) Map<UpdateSettingsAction, SettingsAction> actions,
    @Default({}) Map<UpdatesReadField, StudioFailure> readIssues,
  }) = _UpdatesViewState;

  StudioFailure? get readError => readIssues.values.firstOrNull;

  UpdatesValue? get currentValue {
    final read = source.value;
    return read is ReadyReadValue<UpdatesValue, UpdatesReadRef> &&
      read.current.origin == source.projection.stamp?.origin &&
      read.current.reference == source.projection.header?.reference ? read.current.value : null;
  }
  UpdateSummary? get currentSummary {
    if (summaryOrigin == source.projection.stamp?.origin && summaryReference != null &&
        summaryReference == source.projection.header?.summary) return summary;
    return switch (currentValue) {
      AvailableUpdatesValue(:final update) || DownloadingUpdatesValue(:final update) ||
      VerifyingUpdatesValue(:final update) || ReadyUpdatesValue(:final update) ||
      InstallerLaunchedUpdatesValue(:final update) || InstallFailedUpdatesValue(:final update) => update,
      _ => null,
    };
  }
}
