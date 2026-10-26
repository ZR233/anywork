import 'package:anywork_client/remote.dart';
import 'package:anywork_client/resources.dart';
import 'package:anywork_client/workspace.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

import 'workspace_view_state.dart';

part 'add_project_state.freezed.dart';

enum AddProjectStep { location, connections, directory }

/// Identity of this Workspace dialog's own VM only. It is never passed as an
/// SSH editor/prompt/picker ID; U1's public helpers exclusively own those IDs.
final class AddProjectDialogKey {
  AddProjectDialogKey();
}

@Freezed(toStringOverride: false)
abstract class AddProjectState with _$AddProjectState {
  const AddProjectState._();

  const factory AddProjectState({
    required AddProjectStep step,
    required bool? remote,
    required String rawSearch,
    required String localPathRaw,
    required RemoteState connections,
    required SshServerRuntimeEntry? selectedServer,
    required bool picking,
    required bool pending,
    required bool sealed,
    required WorkspaceActionPresentation? action,
    required StudioFailure? failure,
    required StudioFailure? authenticationFailure,
    required bool passwordUnavailable,
    required SshConnectionSnapshot? connection,
    required WorkspaceOpenResult? opened,
  }) = _AddProjectState;

  String? get selectedAlias => selectedServer?.profile.alias;

  bool get canSubmitLocalPath =>
      picking && !this.sealed && localPathRaw.trim().isNotEmpty;

  List<SshServerRuntimeEntry>? get filteredServers {
    final query = rawSearch.trim().toLowerCase();
    return connections.servers
        ?.where((server) {
          final profile = server.profile;
          return '${profile.alias} ${profile.username}@${profile.hostName}:${profile.port}'
              .toLowerCase()
              .contains(query);
        })
        .toList(growable: false);
  }
}
