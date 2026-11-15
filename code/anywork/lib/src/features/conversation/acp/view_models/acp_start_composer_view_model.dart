import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../../presentation/providers/attachment_drafts.dart';
import '../../../../presentation/providers/client_provider.dart';
import '../../../../presentation/providers/start_session_controller.dart';
import '../state/acp_view_state.dart';
import '../../composer/view_models/start_backend_view_model.dart';
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
    );
    final composer = ref.watch(attachmentDraftsProvider).newThread(workspaceId);
    final failure = composer.failure;
    final accountId = draft.project.acpAccountId;
    final service = ref
        .watch(startBackendViewModelProvider(workspaceId))
        .selectedService;
    return AcpStartComposerViewState(
      workspaceId: workspaceId,
      text: draft.project.text,
      accountId: accountId,
      serviceName: service?.name,
      brandKey: service?.brandKey,
      submitting: draft.submitting,
      serviceEnabled: service?.enabled == true,
      stagedAttachments: composer.attachments,
      failureMessage: failure == null ? null : formatAcpError(failure),
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

  Future<void> removeAttachment(String draftId) => ref
      .read(anyworkClientProvider)
      .drafts
      .attachments
      .removeNewThreadDraft(workspaceId, draftId);
}
