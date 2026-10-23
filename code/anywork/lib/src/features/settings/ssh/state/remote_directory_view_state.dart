import 'package:anywork_client/remote.dart';
import 'package:anywork_client/resources.dart';
import 'package:anywork_client/workspace.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'remote_directory_view_state.freezed.dart';

enum RemotePathIssue { required, absolute }

@Freezed(toStringOverride: false)
abstract class RemoteDirectoryViewState with _$RemoteDirectoryViewState {
  const RemoteDirectoryViewState._();
  const factory RemoteDirectoryViewState({
    required String alias,
    @Default('') String pathRaw,
    @Default(false) bool showProjectNameField,
    @Default('') String nameRaw,
    @Default(false) bool nameEdited,
    @Default(false) bool nameRequired,
    RemoteDirectoryState? directory,
    @Default(0) int generation,
    @Default(false) bool browsing,
    @Default(false) bool opening,
    @Default(false) bool closing,
    @Default(false) bool verified,
    RemotePathIssue? pathIssue,
    StudioFailure? error,
    StudioFailure? observationError,
    @Default([]) List<CloseReport> cleanupReports,
    WorkspaceOpenResult? openResult,
    @Default(false) bool openUncertain,
    String? completedPath,
  }) = _RemoteDirectoryViewState;
  bool get busy => browsing || opening || closing;
  bool get canOpen => !busy && !openUncertain && completedPath == null && verified && directory != null &&
    directory!.error == null && !directory!.loading && pathRaw.trim() == directory!.path &&
    (!showProjectNameField || nameRaw.trim().isNotEmpty);
}
