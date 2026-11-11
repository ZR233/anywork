import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../../presentation/providers/attachment_drafts.dart';
import '../../../../presentation/providers/client_provider.dart';
import '../../../../presentation/providers/project_store.dart';
import '../../../../presentation/providers/start_session_controller.dart';
import '../state/acp_view_state.dart';
import 'acp_session_view_model.dart';

part 'acp_start_composer_view_model.g.dart';

@riverpod
class AcpStartComposerViewModel extends _$AcpStartComposerViewModel {
  @override
  AcpStartComposerViewState build(String workspaceId) {
    final sessionDraft = ref.watch(startSessionControllerProvider);
    final draft = (
      project: sessionDraft.forProject(workspaceId),
      submitting: sessionDraft.submitting,
      failure: sessionDraft.preparations[workspaceId]?.failure,
    );
    final projectStore = ref.watch(projectStoreProvider);
    final isRemoteSsh =
        projectStore.projects?.values
            .where((project) => project.id == workspaceId)
            .firstOrNull
            ?.sshAlias !=
        null;
    final attachments = ref
        .watch(attachmentDraftsProvider)
        .newThread(workspaceId)
        .attachments;
    final accountId = draft.project.acpAccountId;
    return AcpStartComposerViewState(
      workspaceId: workspaceId,
      text: draft.project.text,
      accountId: accountId,
      submitting: draft.submitting,
      isRemoteSsh: isRemoteSsh,
      serviceEnabled: accountId != null,
      stagedAttachments: attachments,
      failureMessage: draft.failure == null
          ? null
          : formatAcpError(draft.failure!),
    );
  }

  void updateDraft(String text) {
    ref
        .read(anyworkClientProvider)
        .drafts
        .startDraft
        .updateDraft(workspaceId, text);
  }

  Future<bool> submit() {
    return ref
        .read(anyworkClientProvider)
        .drafts
        .startDraft
        .submit(workspaceId);
  }
}
