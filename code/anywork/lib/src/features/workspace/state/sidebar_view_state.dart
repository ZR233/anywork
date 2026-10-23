import 'package:anywork_client/configuration.dart';
import 'package:anywork_client/operations.dart';
import 'package:anywork_client/resources.dart';
import 'package:anywork_client/updates.dart';
import 'package:anywork_client/workspace.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'sidebar_view_state.freezed.dart';

@Freezed(toStringOverride: false)
abstract class SidebarProjectPage with _$SidebarProjectPage {
  const factory SidebarProjectPage({
    required int generation,
    required DirectoryQuery query,
    required ThreadDirectoryState? directory,
    required StudioFailure? demandError,
  }) = _SidebarProjectPage;
}

@Freezed(toStringOverride: false)
abstract class SidebarPreferenceWrite with _$SidebarPreferenceWrite {
  const factory SidebarPreferenceWrite({
    required int intent,
    required bool pending,
    required OperationState? operation,
    required StudioFailure? admissionError,
    StudioFailure? observationError,
  }) = _SidebarPreferenceWrite;
}

@Freezed(toStringOverride: false)
abstract class SidebarViewState with _$SidebarViewState {
  const SidebarViewState._();

  const factory SidebarViewState({
    required WorkspaceState workspace,
    required ProjectDirectoryState projects,
    required ConfigurationState configuration,
    required UpdatesBrief? updatesBrief,
    required String rawQuery,
    required String normalizedQuery,
    required DirectoryFilter filter,
    required bool archived,
    required Set<String> expandedProjectIds,
    required int queryGeneration,
    required Map<String, SidebarProjectPage> pages,
    required double? widthDraft,
    required int widthIntent,
    required Map<String, SidebarPreferenceWrite> writes,
    required StudioFailure? preferencesReadError,
    required StudioFailure? projectsReadError,
    required StudioFailure? projectSourceReadError,
    required bool sealed,
  }) = _SidebarViewState;

  bool get hasUpdate => switch (updatesBrief) {
    AvailableUpdatesBrief() || DownloadingUpdatesBrief() || VerifyingUpdatesBrief() ||
    ReadyUpdatesBrief() || InstallFailedUpdatesBrief() => true,
    _ => false,
  };
}
