import 'package:anywork_client/drafts.dart';
import 'package:anywork_client/drafts_ports.dart';
import 'package:anywork_client/models.dart';
import 'package:anywork_client/modes.dart';
import 'package:anywork_client/workspace.dart';

import '../../../rust/api/studio/types/attachment.dart' as attachment;
import '../../../rust/api/studio/types/delegation.dart' as delegation;
import '../../../rust/api/studio/types/thread_preparation.dart' as preparation;
import '../../../rust/api/studio/types/thread_stream.dart' as thread;
import '../conversation/scalar_converters.dart' show threadStatusFromBridge;
import '../shared/adapter_failure.dart';
import '../shared/exact_numbers.dart';

attachment.BridgeAttachmentAdmissionContext admissionContextToBridge(
  AttachmentAdmissionContext value,
) => switch (value) {
  ExistingThreadAttachmentAdmissionContext(:final threadId) =>
    attachment.BridgeAttachmentAdmissionContext.existingThread(
      threadId: threadId,
    ),
  NewThreadAttachmentAdmissionContext(:final route) =>
    attachment.BridgeAttachmentAdmissionContext.newThread(
      route: delegation.BridgeNewThreadModelRoute(
        accountId: route.model.accountId,
        modelId: route.model.modelId,
        effort: route.effort,
      ),
    ),
};

attachment.BridgeAttachmentDraftSource draftSourceToBridge(
  AttachmentDraftSource value,
) => switch (value) {
  LocalFileAttachmentDraftSource(:final path) =>
    attachment.BridgeAttachmentDraftSource.localFile(path: path),
  RemoteUrlAttachmentDraftSource(:final url, :final filename) =>
    attachment.BridgeAttachmentDraftSource.remoteUrl(
      url: url,
      filename: filename,
    ),
};

List<attachment.BridgeAttachmentDraftSource> admissionSourcesToBridge(
  List<AttachmentDraftSource> values,
) => List<attachment.BridgeAttachmentDraftSource>.unmodifiable(
  List<AttachmentDraftSource>.of(values).map(draftSourceToBridge),
);

AttachmentMetadata admittedAttachmentFromBridge(
  attachment.BridgeAttachmentDraft value,
) => AttachmentMetadata(
  id: value.draftId,
  modality: switch (value.modality) {
    attachment.BridgeAttachmentModality.image => AttachmentModality.image,
    attachment.BridgeAttachmentModality.video => AttachmentModality.video,
    attachment.BridgeAttachmentModality.file => AttachmentModality.file,
  },
  mediaType: value.mediaType,
  filename: value.filename,
  byteSize: exactU64(value.byteSize, 'admitted attachment byte size'),
  width: value.width,
  height: value.height,
);

preparation.BridgeStartNewThreadRequest creationRequestToBridge(
  NewThreadCreationRequest value,
) => preparation.BridgeStartNewThreadRequest(
  projectId: value.projectId,
  input: attachment.BridgeStudioPromptInput(
    inputId: value.input.inputId,
    text: value.input.text,
    attachmentDraftIds: List<String>.unmodifiable(
      value.input.attachmentDraftIds,
    ),
  ),
  mode: value.mode.id,
  accountId: value.route.model.accountId,
  modelId: value.route.model.modelId,
  effort: value.route.effort,
  workspaceMode: value.workspaceMode.name,
  delegationMode: switch (value.delegationMode) {
    DelegationMode.profile => delegation.BridgeDelegationMode.profile,
    DelegationMode.automatic => delegation.BridgeDelegationMode.automatic,
  },
  delegationPreference: switch (value.delegationPreference) {
    DelegationPreference.economy =>
      delegation.BridgeDelegationPreference.economy,
    DelegationPreference.balanced =>
      delegation.BridgeDelegationPreference.balanced,
    DelegationPreference.fast => delegation.BridgeDelegationPreference.fast,
  },
);

ThreadPreparationProgress preparationProgressFromBridge(
  preparation.BridgeThreadPreparationProgress value,
) => ThreadPreparationProgress(
  projectId: value.projectId,
  inputId: value.inputId,
  stage: switch (value.stage) {
    preparation.BridgeThreadPreparationStage.checkingProject =>
      ThreadPreparationStage.checkingProject,
    preparation.BridgeThreadPreparationStage.preparingWorkspace =>
      ThreadPreparationStage.preparingWorkspace,
    preparation.BridgeThreadPreparationStage.resolvingRepository =>
      ThreadPreparationStage.resolvingRepository,
    preparation.BridgeThreadPreparationStage.creatingWorktree =>
      ThreadPreparationStage.creatingWorktree,
    preparation.BridgeThreadPreparationStage.initializingSession =>
      ThreadPreparationStage.initializingSession,
    preparation.BridgeThreadPreparationStage.submittingPrompt =>
      ThreadPreparationStage.submittingPrompt,
  },
  workspacePath: value.workspacePath,
  branch: value.branch,
);

WorkspaceThreadRecord createdThreadFromBridge(thread.BridgeThread value) {
  final route = value.frozenModel;
  return WorkspaceThreadRecord(
    id: value.id,
    projectId: value.projectId,
    title: value.title,
    mode: ThreadModeId(value.mode),
    delegationMode: switch (value.delegationMode) {
      delegation.BridgeDelegationMode.profile => DelegationMode.profile,
      delegation.BridgeDelegationMode.automatic => DelegationMode.automatic,
    },
    delegationPreference: switch (value.delegationPreference) {
      delegation.BridgeDelegationPreference.economy =>
        DelegationPreference.economy,
      delegation.BridgeDelegationPreference.balanced =>
        DelegationPreference.balanced,
      delegation.BridgeDelegationPreference.fast => DelegationPreference.fast,
    },
    frozenModel: route == null
        ? null
        : ModelSelection(
            model: AccountModelKey(
              accountId: route.accountId,
              modelId: route.modelId,
            ),
            effort: route.effort,
          ),
    workspaceMode: switch (value.workspaceMode) {
      'local' => ThreadWorkspaceMode.local,
      'worktree' => ThreadWorkspaceMode.worktree,
      _ => throw adapterProtocol('created-thread-workspace-mode'),
    },
    workspacePath: value.workspacePath,
    rootThreadId: value.rootThreadId,
    parentThreadId: value.parentThreadId,
    role: value.role,
    agentPath: value.agentPath,
    status: threadStatusFromBridge(value.status),
    createdAt: exactI64(
      BigInt.from(value.createdAt),
      'created Thread Unix seconds',
    ),
    updatedAt: exactI64(
      BigInt.from(value.updatedAt),
      'updated Thread Unix seconds',
    ),
    lastUserMessageAt: value.lastUserMessageAt == null
        ? null
        : exactI64(
            BigInt.from(value.lastUserMessageAt!),
            'last accepted input Unix seconds',
          ),
    archived: value.archived,
  );
}
