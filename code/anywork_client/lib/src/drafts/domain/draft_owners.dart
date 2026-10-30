import 'dart:typed_data';

import '../../../models.dart';
import '../../contracts/stamps.dart';
import '../../observation/latest_value.dart';

abstract interface class ComposerDraftOwner {
  ComposerThreadState get state;
  ValueObservation<ComposerThreadState> get source;
  String get threadId;
  DraftStamp get stamp;
  void updateDraft(String value);
  void reportFailure(Object error);
  Future<void> addLocalAttachments(List<String> paths);
  Future<void> addRemoteAttachment(String url);
  Future<void> addClipboardImage(Uint8List pngBytes);
  Future<void> removeAttachment(String draftId);
  Future<void> submit({Future<void> Function()? beforeSubmit});
  Future<void> discard();
  Future<void> close();
}

abstract interface class StartSessionDraftOwner {
  StartSessionDraft get state;
  ValueObservation<StartSessionDraft> get source;
  void updateDraft(String workspaceId, String text);
  void setMode(String workspaceId, ThreadModeId mode);
  void setWorkspaceMode(String workspaceId, ThreadWorkspaceMode mode);
  void setDelegationModeOverride(String workspaceId, DelegationMode? mode);
  void setDelegationPreferenceOverride(
    String workspaceId,
    DelegationPreference? preference,
  );
  void setModelIntent(ThreadModeId mode, String accountId, String modelId);
  void setEffortIntent(ThreadModeId mode, String effort);
  Future<bool> submit(String workspaceId);
  ModeModelRouteView resolveRoute(ThreadModeId mode);
  Future<void> discardProject(String workspaceId);
  Future<void> close();
}

abstract interface class AttachmentDraftsOwner {
  AttachmentDraftBoard get state;
  ValueObservation<AttachmentDraftBoard> get source;
  void seedNewThreadIfEmpty(String workspaceId, ComposerThreadState incoming);
  Future<void> admitNewThread({
    required String workspaceId,
    required ThreadModeId mode,
    required List<AttachmentDraftSource> sources,
  });
  Future<void> removeNewThreadDraft(String workspaceId, String draftId);
  Future<void> addNewThreadRemote({
    required String workspaceId,
    required ThreadModeId mode,
    required String url,
  });
  Future<void> addNewThreadClipboard({
    required String workspaceId,
    required ThreadModeId mode,
    required Uint8List pngBytes,
  });
  void reportNewThreadFailure(String workspaceId, Object error);
  Future<void> discardProject(String workspaceId);
  List<String> get unresolvedAttachmentIds;
  List<String> get unresolvedStagingPaths;
  Future<void> retryCleanup();
  Future<void> close();
}
