import 'package:anywork_client/studio_client.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../presentation/providers/studio_update_controller.dart';
import '../state/studio_update_view_state.dart';
import '../studio_update_actions.dart';

part 'studio_update_view_model.g.dart';

/// Projects Client update snapshots into sidebar and settings vocabulary.
@riverpod
class StudioUpdateViewModel extends _$StudioUpdateViewModel {
  @override
  StudioUpdateViewState build() {
    return projectStudioUpdateViewState(
      snapshot: ref.watch(studioUpdateControllerProvider),
      request: ref.watch(studioUpdateRequestProvider),
      currentVersion: ref.watch(studioVersionProvider),
    );
  }

  Future<void> check() => ref.read(studioUpdateActionsProvider).check();

  Future<void> install() => ref.read(studioUpdateActionsProvider).install();

  Future<void> cancelInstall() =>
      ref.read(studioUpdateActionsProvider).cancelInstall();

  Future<void> openReleaseNotes() =>
      ref.read(studioUpdateActionsProvider).openReleaseNotes();
}

StudioUpdateViewState projectStudioUpdateViewState({
  required UpdaterStateSnapshot snapshot,
  required StudioUpdateRequest request,
  required String currentVersion,
}) {
  final requestKind = switch (request.phase) {
    StudioUpdateRequestPhase.idle => StudioUpdateRequestKind.idle,
    StudioUpdateRequestPhase.checking => StudioUpdateRequestKind.checking,
    StudioUpdateRequestPhase.preparing => StudioUpdateRequestKind.preparing,
    StudioUpdateRequestPhase.cancelling => StudioUpdateRequestKind.cancelling,
    StudioUpdateRequestPhase.cancelled => StudioUpdateRequestKind.cancelled,
    StudioUpdateRequestPhase.ready => StudioUpdateRequestKind.ready,
    StudioUpdateRequestPhase.failed => StudioUpdateRequestKind.failed,
  };
  final activity = snapshot.activity;
  final hasReady = snapshot.hasUpdate && snapshot.readyUpdate != null;
  final statusKind =
      hasReady &&
          (activity is IdleUpdaterActivity ||
              activity is UpToDateUpdaterActivity ||
              activity is CheckFailedUpdaterActivity ||
              activity is InstallFailedUpdaterActivity ||
              activity is ReadyUpdaterActivity)
      ? StudioUpdateStatusKind.ready
      : switch (activity) {
          DisabledUpdaterActivity() => StudioUpdateStatusKind.disabled,
          IdleUpdaterActivity() => StudioUpdateStatusKind.idle,
          CheckingUpdaterActivity() => StudioUpdateStatusKind.checking,
          UpToDateUpdaterActivity() => StudioUpdateStatusKind.upToDate,
          AvailableUpdaterActivity() => StudioUpdateStatusKind.available,
          DownloadingUpdaterActivity() => StudioUpdateStatusKind.downloading,
          VerifyingUpdaterActivity() => StudioUpdateStatusKind.verifying,
          ReadyUpdaterActivity() => StudioUpdateStatusKind.ready,
          InstallerLaunchedUpdaterActivity() =>
            StudioUpdateStatusKind.installerLaunched,
          InstallFailedUpdaterActivity() =>
            StudioUpdateStatusKind.installFailed,
          CheckFailedUpdaterActivity() => StudioUpdateStatusKind.checkFailed,
        };
  final downloading = activity is DownloadingUpdaterActivity ? activity : null;
  final progress = downloading == null || downloading.total <= 0
      ? null
      : (downloading.downloaded / downloading.total).clamp(0.0, 1.0);
  final error = switch (activity) {
    CheckFailedUpdaterActivity(:final error) ||
    InstallFailedUpdaterActivity(:final error) => error,
    DisabledUpdaterActivity() ||
    IdleUpdaterActivity() ||
    CheckingUpdaterActivity() ||
    UpToDateUpdaterActivity() ||
    AvailableUpdaterActivity() ||
    DownloadingUpdaterActivity() ||
    VerifyingUpdaterActivity() ||
    ReadyUpdaterActivity() ||
    InstallerLaunchedUpdaterActivity() => null,
  };

  late final StudioUpdateSettingsActionLayout actionLayout;
  late final StudioUpdatePrimaryAction primaryAction;
  var showReleaseNotes = false;
  var showCancel = false;
  var cancelEnabled = true;
  if (hasReady) {
    actionLayout = StudioUpdateSettingsActionLayout.updateAvailable;
    primaryAction = StudioUpdatePrimaryAction.installAndRestart;
    showReleaseNotes = true;
    showCancel =
        activity is DownloadingUpdaterActivity ||
        activity is VerifyingUpdaterActivity;
  } else if (activity is CheckingUpdaterActivity ||
      request.phase == StudioUpdateRequestPhase.checking) {
    actionLayout = StudioUpdateSettingsActionLayout.checking;
    primaryAction = StudioUpdatePrimaryAction.none;
  } else if (request.phase == StudioUpdateRequestPhase.preparing ||
      request.phase == StudioUpdateRequestPhase.cancelling ||
      activity is DownloadingUpdaterActivity ||
      activity is VerifyingUpdaterActivity) {
    actionLayout = StudioUpdateSettingsActionLayout.progress;
    primaryAction = StudioUpdatePrimaryAction.downloadAndRestart;
    showCancel = true;
    cancelEnabled = request.phase != StudioUpdateRequestPhase.cancelling;
  } else if (activity is InstallerLaunchedUpdaterActivity ||
      activity is DisabledUpdaterActivity) {
    actionLayout = StudioUpdateSettingsActionLayout.none;
    primaryAction = StudioUpdatePrimaryAction.none;
  } else if (snapshot.hasUpdate) {
    actionLayout = StudioUpdateSettingsActionLayout.updateAvailable;
    primaryAction = activity is ReadyUpdaterActivity
        ? StudioUpdatePrimaryAction.installAndRestart
        : StudioUpdatePrimaryAction.downloadAndRestart;
    showReleaseNotes = true;
  } else {
    actionLayout = StudioUpdateSettingsActionLayout.check;
    primaryAction = StudioUpdatePrimaryAction.check;
  }

  return StudioUpdateViewState(
    hasUpdate: snapshot.hasUpdate,
    updateBusy: request.pending,
    currentVersion: currentVersion,
    availableVersion:
        activity.update?.version ?? snapshot.readyUpdate?.update.version,
    readyVersion: snapshot.readyUpdate?.update.version,
    statusKind: statusKind,
    requestKind: requestKind,
    showProgress: downloading != null,
    progress: progress,
    progressPercent: ((progress ?? 0) * 100).round(),
    actionLayout: actionLayout,
    primaryAction: primaryAction,
    primaryEnabled: !request.pending,
    showReleaseNotes: showReleaseNotes,
    showCancel: showCancel,
    cancelEnabled: cancelEnabled,
    errorKind: error == null
        ? StudioUpdateErrorKind.none
        : error.code == 'cancelled'
        ? StudioUpdateErrorKind.cancelled
        : StudioUpdateErrorKind.failed,
    errorMessage: error?.message ?? '',
    requestErrorMessage: request.error?.toString() == error?.message
        ? null
        : request.error?.toString(),
  );
}
