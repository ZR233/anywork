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
  void updateDraft(String projectId, String text);
  void setMode(String projectId, ThreadModeId mode);
  void setWorkspaceMode(String projectId, ThreadWorkspaceMode mode);
  void setDelegationModeOverride(String projectId, DelegationMode? mode);
  void setDelegationPreferenceOverride(
    String projectId,
    DelegationPreference? preference,
  );
  void setModelIntent(ThreadModeId mode, String accountId, String modelId);
  void setEffortIntent(ThreadModeId mode, String effort);
  Future<bool> submit(String projectId);
  ModeModelRouteView resolveRoute(ThreadModeId mode);
  Future<void> discardProject(String projectId);
  Future<void> close();
}

abstract interface class AttachmentDraftsOwner {
  AttachmentDraftBoard get state;
  ValueObservation<AttachmentDraftBoard> get source;
  void seedNewThreadIfEmpty(String projectId, ComposerThreadState incoming);
  Future<void> admitNewThread({
    required String projectId,
    required ThreadModeId mode,
    required List<AttachmentDraftSource> sources,
  });
  Future<void> removeNewThreadDraft(String projectId, String draftId);
  Future<void> addNewThreadRemote({
    required String projectId,
    required ThreadModeId mode,
    required String url,
  });
  Future<void> addNewThreadClipboard({
    required String projectId,
    required ThreadModeId mode,
    required Uint8List pngBytes,
  });
  void reportNewThreadFailure(String projectId, Object error);
  Future<void> discardProject(String projectId);
  List<String> get unresolvedAttachmentIds;
  List<String> get unresolvedStagingPaths;
  Future<void> retryCleanup();
  Future<void> close();
}
