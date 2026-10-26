part of 'drafts_repository.dart';

sealed class _DraftHandle {
  _DraftHandle(this.repo);
  final _DraftsRepository repo;
  AttachmentDraftRecord get record;
  bool disposed = false;
  bool get canDispose;
  void sealRecord();
  void disposeRecord();
  void removeRecord(String id);
  void discardRecord();
  bool discardCaptured(AttachmentDraftReferences references);
  void publishCleanup(List<AttachmentCleanupIssue> issues);
  OperationTicket<Unit> localFiles(List<String> paths) => repo.attach(this, [
    for (final path in List<String>.of(paths))
      AttachmentDraftSource.localFile(path),
  ]);
  OperationTicket<Unit> remote(String url) =>
      repo.attach(this, [AttachmentDraftSource.remoteUrl(url)]);
  OperationTicket<Unit> clipboard(Uint8List bytes) =>
      repo.attach(this, const [], image: bytes);
}

final class _Composer extends _DraftHandle implements ComposerDraft {
  _Composer(super.repo, this.record);
  @override
  final ComposerDraftRecord record;
  @override
  String get threadId => record.threadId;
  @override
  ReadonlyLatestValue<ComposerDraftState> get state => record.state;
  @override
  void setText(String text) {
    repo.ensureOpen();
    record.setText(text);
  }

  @override
  OperationTicket<Unit> addLocalFiles(List<String> paths) => localFiles(paths);
  @override
  OperationTicket<Unit> addRemoteUrl(String url) => remote(url);
  @override
  OperationTicket<Unit> addClipboardImage(Uint8List bytes) => clipboard(bytes);
  @override
  OperationTicket<Unit> removeAttachment(String id) =>
      repo.editAttachments(this, id);
  @override
  OperationTicket<Unit> discard() => repo.editAttachments(this, null);
  @override
  OperationTicket<SubmitPromptReceipt> submit({
    Future<void> Function()? preparePresentation,
  }) => repo.submitComposer(this, preparePresentation);
  @override
  bool get canDispose => !record.hasPending && !record.hasUnknown;
  @override
  void sealRecord() => record.seal();
  @override
  void disposeRecord() {
    record.dispose();
    disposed = true;
  }

  @override
  void removeRecord(String id) => record.removeAttachment(id);
  @override
  void discardRecord() => record.discard();
  @override
  bool discardCaptured(AttachmentDraftReferences references) =>
      record.discardCaptured(references.stamp, references.generation);
  @override
  void publishCleanup(List<AttachmentCleanupIssue> issues) =>
      record.cleanupIssues(issues);
}

final class _Start extends _DraftHandle implements StartDraft {
  _Start(super.repo, this.record);
  @override
  final StartDraftRecord record;
  int _routeToken = 0;
  Future<void>? _preparing;
  final Set<Future<void>> _routeWork = Set.identity();
  ({ConfigurationRoleReadTarget? sources, StartRouteQuery query, int revision})?
  _prepareKey;
  @override
  String get projectId => record.projectId;
  @override
  ReadonlyLatestValue<StartDraftState> get state => record.state;
  @override
  void setText(String text) {
    repo.ensureOpen();
    record.setText(text);
  }

  @override
  void setMode(ThreadModeId mode) {
    repo.ensureOpen();
    if (record.state.value.mode == mode) return;
    record.setMode(mode);
    invalidateRoute();
  }

  @override
  void setWorkspaceMode(ThreadWorkspaceMode mode) {
    repo.ensureOpen();
    record.setWorkspaceMode(mode);
  }

  @override
  void setDelegationMode(DelegationMode? mode) {
    repo.ensureOpen();
    record.setDelegationMode(mode);
  }

  @override
  void setDelegationPreference(DelegationPreference? preference) {
    repo.ensureOpen();
    record.setDelegationPreference(preference);
  }

  @override
  Future<void> prepareRoute() => _prepareStartRoute(this);
  void invalidateRoute() => _invalidateStartRoute(this);
  @override
  OperationTicket<Unit> addLocalFiles(List<String> paths) => localFiles(paths);
  @override
  OperationTicket<Unit> addRemoteUrl(String url) => remote(url);
  @override
  OperationTicket<Unit> addClipboardImage(Uint8List bytes) => clipboard(bytes);
  @override
  OperationTicket<Unit> removeAttachment(String id) =>
      repo.editAttachments(this, id);
  @override
  OperationTicket<Unit> discard() => repo.editAttachments(this, null);
  @override
  OperationTicket<StartNewThreadResult> submit() => repo.submitStart(this);
  @override
  bool get canDispose =>
      !record.hasPending && !record.hasUnknown && _routeWork.isEmpty;
  @override
  void sealRecord() {
    _routeToken++;
    record.seal();
  }

  @override
  void disposeRecord() {
    record.dispose();
    disposed = true;
  }

  @override
  void removeRecord(String id) => record.removeAttachment(id);
  @override
  void discardRecord() => record.discard();
  @override
  bool discardCaptured(AttachmentDraftReferences references) =>
      record.discardCaptured(references.stamp, references.generation);
  @override
  void publishCleanup(List<AttachmentCleanupIssue> issues) =>
      record.cleanupIssues(issues);
}
