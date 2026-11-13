import 'dart:typed_data';

import 'package:anywork_client/models.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

import '../../timeline/state/patch_presentation.dart';
import '../../timeline/state/tool_presentation.dart';

part 'acp_view_state.freezed.dart';

/// Stable semantic key values shared by pure ACP views, connectors, and tests.
///
/// Keys use canonical protocol or thread identities rather than mutable text,
/// random values, or timestamps.
abstract final class AcpViewKeyValues {
  static (String, String) startInput(String workspaceId) =>
      ('acp-start-input', workspaceId);
  static (String, String) startSubmit(String workspaceId) =>
      ('acp-start-submit', workspaceId);
  static (String, int) timelineItem(String threadId, int index) =>
      (threadId, index);
  static (String, String) composerInput(String threadId) =>
      ('acp-input', threadId);
  static (String, String) composerPrimaryAction(String threadId) =>
      ('acp-composer-action', threadId);
  static (String, String) configControl(String configId) =>
      ('acp-config', configId);
  static (String, String, String) configChoice(
    String configId,
    String valueId,
  ) => ('acp-config-choice', configId, valueId);
  static const String configLegacyMode = 'acp-config-legacy-mode';
  static const String configOverflow = 'acp-config-overflow';
  static (String, String) permissionDock(String permissionId) =>
      ('acp-permission', permissionId);
  static (String, String, String) permissionOption(
    String permissionId,
    String optionId,
  ) => ('acp-permission-option', permissionId, optionId);
  static (String, String) permissionCancel(String permissionId) =>
      ('acp-permission-cancel', permissionId);
  static (String, String) planCard(String threadId) => ('acp-plan', threadId);
  static (String, String) toolCard(String toolCallId) =>
      ('acp-tool', toolCallId);
  static (String, String) externalHistoryButton(String threadId) =>
      ('acp-external-history-button', threadId);
  static (String, String) externalHistoryLoad(String sessionId) =>
      ('acp-external-load', sessionId);
  static (String, String) externalHistoryResume(String sessionId) =>
      ('acp-external-resume', sessionId);
}

@freezed
abstract class AcpStartComposerViewState with _$AcpStartComposerViewState {
  const AcpStartComposerViewState._();

  const factory AcpStartComposerViewState({
    required String workspaceId,
    required String text,
    String? accountId,
    String? serviceName,
    String? brandKey,
    @Default(false) bool submitting,
    @Default(false) bool serviceEnabled,
    @Default(<AttachmentDraftView>[])
    List<AttachmentDraftView> stagedAttachments,
    String? failureMessage,
  }) = _AcpStartComposerViewState;

  bool get canEditDraft => !submitting;

  bool get canCreate =>
      accountId != null && serviceEnabled && !submitting;
}

enum AcpCapabilityKind {
  image,
  audio,
  embeddedContext,
  loadSession,
  resumeSession,
  listSessions,
}

enum AcpGapKind { windowExceeded, disconnected, encoding }

enum AcpHistoryOriginKind {
  newSession,
  loadReplay,
  resumedWithoutHistory,
  residentWithoutObservation,
  incomplete,
}

@freezed
abstract class AcpTimelineHeaderViewState with _$AcpTimelineHeaderViewState {
  const factory AcpTimelineHeaderViewState({
    @Default(true) bool loading,
    @Default(false) bool ready,
    @Default(false) bool disconnected,
    @Default(false) bool observationEnded,
    @Default(0) int itemCount,
    @Default(false) bool hasConversationalContent,
    @Default(false) bool hasPlan,
    @Default(<AcpCapabilityKind>[]) List<AcpCapabilityKind> capabilities,
    String? errorMessage,
    AcpGapKind? gapKind,
    AcpHistoryOriginKind? historyKind,
  }) = _AcpTimelineHeaderViewState;
}

enum AcpToolStatusKind { pending, inProgress, completed, failed, unknown }

@freezed
sealed class AcpContentBlockPresentation with _$AcpContentBlockPresentation {
  const factory AcpContentBlockPresentation.text({required String text}) =
      AcpTextBlockPresentation;

  const factory AcpContentBlockPresentation.image({
    required String cacheKey,
    required String dataBase64,
    required String mimeType,
    String? uri,
  }) = AcpImageBlockPresentation;

  const factory AcpContentBlockPresentation.audio({required String mimeType}) =
      AcpAudioBlockPresentation;

  const factory AcpContentBlockPresentation.resourceLink({
    required String label,
    required String uri,
    String? description,
    String? mimeType,
    @Default(false) bool canOpenExternal,
  }) = AcpResourceLinkBlockPresentation;

  const factory AcpContentBlockPresentation.textResource({
    required String uri,
    required String text,
    String? mimeType,
  }) = AcpTextResourceBlockPresentation;

  const factory AcpContentBlockPresentation.blobResource({
    required String uri,
    String? mimeType,
    required int byteCount,
  }) = AcpBlobResourceBlockPresentation;
}

@freezed
abstract class AcpImagePayload with _$AcpImagePayload {
  const factory AcpImagePayload({
    required String cacheKey,
    required String dataBase64,
    required String mimeType,
    String? uri,
  }) = _AcpImagePayload;
}

@freezed
abstract class AcpDecodedImagePresentation with _$AcpDecodedImagePresentation {
  const factory AcpDecodedImagePresentation({
    required Uint8List bytes,
    required ThreadAttachmentView attachment,
  }) = _AcpDecodedImagePresentation;
}

@freezed
sealed class AcpUpdatePresentation with _$AcpUpdatePresentation {
  const factory AcpUpdatePresentation.notice({
    required String title,
    String? description,
  }) = AcpNoticeUpdatePresentation;

  const factory AcpUpdatePresentation.usage({
    required String usedFormatted,
    required String sizeFormatted,
    String? costLabel,
  }) = AcpUsageUpdatePresentation;

  const factory AcpUpdatePresentation.compaction({
    required String statusLabel,
    String? errorMessage,
  }) = AcpCompactionUpdatePresentation;

  const factory AcpUpdatePresentation.availableCommands({
    required List<({String name, String description})> commands,
  }) = AcpCommandsUpdatePresentation;

  const factory AcpUpdatePresentation.sessionInfo() =
      AcpSessionInfoUpdatePresentation;

  const factory AcpUpdatePresentation.superseded() =
      AcpSupersededUpdatePresentation;

  const factory AcpUpdatePresentation.generic() = AcpGenericUpdatePresentation;
}

@freezed
sealed class AcpTimelineItemPresentation with _$AcpTimelineItemPresentation {
  const factory AcpTimelineItemPresentation.userMessage({
    required String id,
    required List<AcpContentBlockPresentation> blocks,
  }) = AcpTimelineUserMessage;

  const factory AcpTimelineItemPresentation.assistantMessage({
    required String id,
    required List<AcpContentBlockPresentation> blocks,
  }) = AcpTimelineAssistantMessage;

  const factory AcpTimelineItemPresentation.thought({
    required String id,
    required String summary,
    required List<AcpContentBlockPresentation> blocks,
    @Default(false) bool active,
  }) = AcpTimelineThoughtItem;

  const factory AcpTimelineItemPresentation.toolCall({
    required String id,
    required String toolCallId,
    required TimelineToolPresentation tool,
    required AcpToolStatusKind status,
    String? kindLabel,
    @Default(<String>[]) List<String> locations,
    @Default(<String>[]) List<String> terminals,
    @Default(<TimelinePatchDocument>[]) List<TimelinePatchDocument> diffs,
    @Default(<AcpContentBlockPresentation>[])
    List<AcpContentBlockPresentation> contentBlocks,
  }) = AcpTimelineToolCallItem;

  const factory AcpTimelineItemPresentation.sessionUpdate({
    required String id,
    required AcpUpdatePresentation update,
  }) = AcpTimelineSessionUpdateItem;
}

enum AcpPlanPriorityKind { high, medium, low }

enum AcpPlanStatusKind { pending, inProgress, completed }

@freezed
abstract class AcpPlanEntryPresentation with _$AcpPlanEntryPresentation {
  const factory AcpPlanEntryPresentation({
    required String content,
    required AcpPlanPriorityKind priority,
    required AcpPlanStatusKind status,
  }) = _AcpPlanEntryPresentation;
}

@freezed
abstract class AcpPlanCardViewState with _$AcpPlanCardViewState {
  const factory AcpPlanCardViewState({
    required List<AcpPlanEntryPresentation> entries,
    required int completedCount,
  }) = _AcpPlanCardViewState;
}

enum AcpPermissionOptionTone {
  allowAlways,
  allowOnce,
  rejectOnce,
  rejectAlways,
  other,
}

@freezed
abstract class AcpPermissionOptionPresentation
    with _$AcpPermissionOptionPresentation {
  const factory AcpPermissionOptionPresentation({
    required String optionId,
    required String name,
    required AcpPermissionOptionTone tone,
  }) = _AcpPermissionOptionPresentation;
}

@freezed
abstract class AcpPermissionRequestPresentation
    with _$AcpPermissionRequestPresentation {
  const factory AcpPermissionRequestPresentation({
    required String id,
    required String title,
    String? kindLabel,
    @Default(<String>[]) List<String> locations,
    String? argumentsPreview,
    @Default(<TimelinePatchDocument>[]) List<TimelinePatchDocument> diffs,
    required List<AcpPermissionOptionPresentation> options,
    @Default(false) bool submitting,
  }) = _AcpPermissionRequestPresentation;
}

@freezed
abstract class AcpPermissionDockViewState with _$AcpPermissionDockViewState {
  const factory AcpPermissionDockViewState({
    @Default(0) int pendingCount,
    AcpPermissionRequestPresentation? activeRequest,
    String? errorMessage,
  }) = _AcpPermissionDockViewState;
}

enum AcpConfigCategoryKind {
  mode,
  model,
  modelConfig,
  thoughtLevel,
  other,
  unspecified,
}

@freezed
abstract class AcpSelectChoicePresentation with _$AcpSelectChoicePresentation {
  const factory AcpSelectChoicePresentation({
    required String value,
    required String name,
    String? description,
  }) = _AcpSelectChoicePresentation;
}

@freezed
abstract class AcpSelectGroupPresentation with _$AcpSelectGroupPresentation {
  const factory AcpSelectGroupPresentation({
    required String id,
    required String name,
    required List<AcpSelectChoicePresentation> options,
  }) = _AcpSelectGroupPresentation;
}

@freezed
sealed class AcpConfigControlPresentation with _$AcpConfigControlPresentation {
  const factory AcpConfigControlPresentation.select({
    required String id,
    required String name,
    String? description,
    required AcpConfigCategoryKind category,
    required String currentValue,
    required String currentLabel,
    @Default(<AcpSelectChoicePresentation>[])
    List<AcpSelectChoicePresentation> flatOptions,
    @Default(<AcpSelectGroupPresentation>[])
    List<AcpSelectGroupPresentation> groups,
  }) = AcpSelectConfigControl;

  const factory AcpConfigControlPresentation.boolean({
    required String id,
    required String name,
    String? description,
    required AcpConfigCategoryKind category,
    required bool currentValue,
  }) = AcpBooleanConfigControl;

  const factory AcpConfigControlPresentation.legacyMode({
    required String id,
    String? description,
    required String currentModeId,
    required String currentModeLabel,
    required List<AcpSelectChoicePresentation> modes,
  }) = AcpLegacyModeConfigControl;
}

@freezed
abstract class AcpConfigurationViewState with _$AcpConfigurationViewState {
  const AcpConfigurationViewState._();

  const factory AcpConfigurationViewState({
    @Default(<AcpConfigControlPresentation>[])
    List<AcpConfigControlPresentation> controls,
    @Default(false) bool pending,
    @Default(false) bool enabled,
    String? errorMessage,
  }) = _AcpConfigurationViewState;

  bool get isVisible => controls.isNotEmpty || pending || errorMessage != null;
}

enum AcpComposerBlockerKind {
  opening,
  disconnected,
  observationEnded,
  initializing,
  notReady,
  configPending,
  configError,
  sending,
  running,
}

@freezed
abstract class AcpComposerBlocker with _$AcpComposerBlocker {
  const factory AcpComposerBlocker({
    required AcpComposerBlockerKind kind,
    String? detail,
  }) = _AcpComposerBlocker;
}

@freezed
abstract class AcpComposerViewState with _$AcpComposerViewState {
  const AcpComposerViewState._();

  const factory AcpComposerViewState({
    required String threadId,
    @Default('') String draftText,
    @Default(<AttachmentDraftView>[]) List<AttachmentDraftView> attachments,
    @Default(<ModelInputCapabilityView>[])
    List<ModelInputCapabilityView> localCapabilities,
    @Default(<ModelInputCapabilityView>[])
    List<ModelInputCapabilityView> remoteCapabilities,
    @Default(false) bool supportsImagePaste,
    @Default(false) bool canSend,
    @Default(false) bool isRunning,
    @Default(false) bool canInterrupt,
    @Default(false) bool canAttach,
    @Default(false) bool submitting,
    AcpComposerBlocker? blocker,
    String? draftError,
  }) = _AcpComposerViewState;

  bool get hasSendableInput =>
      draftText.trim().isNotEmpty || attachments.isNotEmpty;
}

enum AcpSessionStatusPhase {
  connecting,
  ready,
  running,
  stopping,
  completed,
  disconnected,
  ended,
}

enum AcpStopReasonKind {
  endTurn,
  maxTokens,
  maxTurnRequests,
  refusal,
  cancelled,
  other,
}

@freezed
abstract class AcpUsagePresentation with _$AcpUsagePresentation {
  const factory AcpUsagePresentation({
    required String usedFormatted,
    required String sizeFormatted,
    required double ratio,
    String? costLabel,
  }) = _AcpUsagePresentation;
}

@freezed
abstract class AcpStatusBarViewState with _$AcpStatusBarViewState {
  const factory AcpStatusBarViewState({
    required AcpSessionStatusPhase phase,
    AcpStopReasonKind? stopReason,
    String? stopReasonRaw,
    AcpHistoryOriginKind? provenance,
    AcpUsagePresentation? usage,
  }) = _AcpStatusBarViewState;
}

enum AcpExternalHistoryAvailability {
  loading,
  noOwner,
  unknownCapability,
  unsupported,
  notReady,
  available,
}

enum AcpExternalOpenOutcome { opening, opened, unknown }

@freezed
abstract class AcpExternalHistoryButtonState
    with _$AcpExternalHistoryButtonState {
  const factory AcpExternalHistoryButtonState({
    required AcpExternalHistoryAvailability status,
    @Default(false) bool canLoad,
    @Default(false) bool canResume,
  }) = _AcpExternalHistoryButtonState;
}

@freezed
abstract class AcpExternalSessionRowPresentation
    with _$AcpExternalSessionRowPresentation {
  const factory AcpExternalSessionRowPresentation({
    required String sessionId,
    String? title,
    required String cwd,
    String? updatedAt,
    AcpExternalOpenOutcome? outcome,
    String? errorMessage,
  }) = _AcpExternalSessionRowPresentation;
}

@freezed
abstract class AcpExternalHistoryDialogState
    with _$AcpExternalHistoryDialogState {
  const factory AcpExternalHistoryDialogState({
    required AcpExternalHistoryAvailability availability,
    @Default(false) bool canLoad,
    @Default(false) bool canResume,
    @Default(<AcpExternalSessionRowPresentation>[])
    List<AcpExternalSessionRowPresentation> sessions,
    String? nextCursor,
    @Default(false) bool loading,
    @Default(false) bool loadingMore,
    @Default(false) bool anyOpening,
    String? listError,
  }) = _AcpExternalHistoryDialogState;
}
