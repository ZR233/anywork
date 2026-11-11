import 'package:anywork_client/studio_client.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../presentation/providers/attachment_drafts.dart';
import '../../../../presentation/providers/client_provider.dart';
import '../../../../presentation/providers/project_store.dart';
import '../../../../presentation/providers/start_session_controller.dart';

typedef AcpStartState = ({
  String text,
  String? accountId,
  bool submitting,
  bool remote,
  ComposerThreadState attachments,
  Object? failure,
});

final acpStartViewModelProvider = Provider.autoDispose
    .family<AcpStartState, String>((ref, workspaceId) {
      final draft = ref.watch(
        startSessionControllerProvider.select(
          (state) => (
            project: state.forProject(workspaceId),
            submitting: state.submitting,
            failure: state.preparations[workspaceId]?.failure,
          ),
        ),
      );
      final remote = ref.watch(
        projectStoreProvider.select(
          (state) =>
              state.projects?.values
                  .where((project) => project.id == workspaceId)
                  .firstOrNull
                  ?.sshAlias !=
              null,
        ),
      );
      final attachments = ref.watch(
        attachmentDraftsProvider.select(
          (state) => state.newThread(workspaceId),
        ),
      );
      return (
        text: draft.project.text,
        accountId: draft.project.acpAccountId,
        submitting: draft.submitting,
        remote: remote,
        attachments: attachments,
        failure: draft.failure,
      );
    });

final acpStartActionsProvider = Provider.autoDispose
    .family<AcpStartActions, String>(
      (ref, workspaceId) =>
          AcpStartActions(ref.watch(anyworkClientProvider), workspaceId),
    );

final class AcpStartActions {
  AcpStartActions(this.client, this.workspaceId);

  final AnyworkClient client;
  final String workspaceId;

  void updateDraft(String text) =>
      client.drafts.startDraft.updateDraft(workspaceId, text);

  Future<bool> submit() => client.drafts.startDraft.submit(workspaceId);
}
