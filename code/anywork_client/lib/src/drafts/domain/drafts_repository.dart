import 'dart:typed_data';

import '../../../modes.dart';
import '../../../operations.dart';
import '../../../resources.dart';
import '../../../workspace.dart' show ThreadWorkspaceMode;
import 'draft_values.dart';
import 'submission_values.dart';

abstract interface class DraftsRepository {
  ComposerDraft composer(String threadId);
  StartDraft start(String projectId);
  ReadonlyLatestValue<StartRoutePreferences> get startRoutes;
  void setStartModel(ThreadModeId mode, String accountId, String modelId);
  void setStartEffort(ThreadModeId mode, String effort);

  /// Each returned buffer is owned exclusively by the caller, never in state.
  Future<Uint8List> readDraftAttachment(String draftId);
  Future<Uint8List> readThreadAttachment(String threadId, String attachmentId);

  void seal();
  Future<CloseReport> close({DateTime? deadline});
  Future<CloseReport> retryCleanup({DateTime? deadline});
}

/// Borrowed capability; disposing an observer cannot close or discard this owner.
abstract interface class ComposerDraft {
  String get threadId;
  ReadonlyLatestValue<ComposerDraftState> get state;
  void setText(String text);
  OperationTicket<Unit> addLocalFiles(List<String> paths);
  OperationTicket<Unit> addRemoteUrl(String url);
  OperationTicket<Unit> addClipboardImage(Uint8List pngBytes);
  OperationTicket<Unit> removeAttachment(String attachmentDraftId);
  OperationTicket<Unit> discard();
  OperationTicket<SubmitPromptReceipt> submit({
    Future<void> Function()? preparePresentation,
  });
}

abstract interface class StartDraft {
  String get projectId;
  ReadonlyLatestValue<StartDraftState> get state;
  void setText(String text);
  void setMode(ThreadModeId mode);
  void setWorkspaceMode(ThreadWorkspaceMode mode);
  void setDelegationMode(DelegationMode? mode);
  void setDelegationPreference(DelegationPreference? preference);
  Future<void> prepareRoute();
  OperationTicket<Unit> addLocalFiles(List<String> paths);
  OperationTicket<Unit> addRemoteUrl(String url);
  OperationTicket<Unit> addClipboardImage(Uint8List pngBytes);
  OperationTicket<Unit> removeAttachment(String attachmentDraftId);
  OperationTicket<Unit> discard();
  OperationTicket<StartNewThreadResult> submit();
}
