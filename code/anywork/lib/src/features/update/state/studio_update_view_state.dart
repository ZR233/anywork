/// Immutable presentation projection for Studio update entry points.
final class StudioUpdateViewState {
  const StudioUpdateViewState({
    required this.hasUpdate,
    required this.updateBusy,
    required this.currentVersion,
    this.availableVersion,
    required this.statusKind,
    required this.requestKind,
    required this.showProgress,
    this.progress,
    required this.progressPercent,
    required this.actionLayout,
    required this.primaryAction,
    required this.primaryEnabled,
    required this.showReleaseNotes,
    required this.showCancel,
    required this.cancelEnabled,
    required this.errorKind,
    required this.errorMessage,
    this.requestErrorMessage,
  });

  final bool hasUpdate;
  final bool updateBusy;
  final String currentVersion;
  final String? availableVersion;
  final StudioUpdateStatusKind statusKind;
  final StudioUpdateRequestKind requestKind;
  final bool showProgress;
  final double? progress;
  final int progressPercent;
  final StudioUpdateSettingsActionLayout actionLayout;
  final StudioUpdatePrimaryAction primaryAction;
  final bool primaryEnabled;
  final bool showReleaseNotes;
  final bool showCancel;
  final bool cancelEnabled;
  final StudioUpdateErrorKind errorKind;
  final String errorMessage;
  final String? requestErrorMessage;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is StudioUpdateViewState &&
          hasUpdate == other.hasUpdate &&
          updateBusy == other.updateBusy &&
          currentVersion == other.currentVersion &&
          availableVersion == other.availableVersion &&
          statusKind == other.statusKind &&
          requestKind == other.requestKind &&
          showProgress == other.showProgress &&
          progress == other.progress &&
          progressPercent == other.progressPercent &&
          actionLayout == other.actionLayout &&
          primaryAction == other.primaryAction &&
          primaryEnabled == other.primaryEnabled &&
          showReleaseNotes == other.showReleaseNotes &&
          showCancel == other.showCancel &&
          cancelEnabled == other.cancelEnabled &&
          errorKind == other.errorKind &&
          errorMessage == other.errorMessage &&
          requestErrorMessage == other.requestErrorMessage;

  @override
  int get hashCode => Object.hash(
    hasUpdate,
    updateBusy,
    currentVersion,
    availableVersion,
    statusKind,
    requestKind,
    showProgress,
    progress,
    progressPercent,
    actionLayout,
    primaryAction,
    primaryEnabled,
    showReleaseNotes,
    showCancel,
    cancelEnabled,
    errorKind,
    errorMessage,
    requestErrorMessage,
  );
}

enum StudioUpdateStatusKind {
  disabled,
  idle,
  checking,
  upToDate,
  available,
  downloading,
  verifying,
  ready,
  installerLaunched,
  installFailed,
  checkFailed,
}

enum StudioUpdatePrimaryAction {
  none,
  check,
  downloadAndRestart,
  installAndRestart,
}

enum StudioUpdateSettingsActionLayout {
  none,
  checking,
  progress,
  updateAvailable,
  check,
}

enum StudioUpdateRequestKind {
  idle,
  checking,
  preparing,
  cancelling,
  cancelled,
  ready,
  failed,
}

enum StudioUpdateErrorKind { none, cancelled, failed }
