import '../../../modes.dart' show ThreadModeId;
import '../../../resources.dart';
import '../../../resources_ports.dart';
import '../../../workspace.dart' show ThreadWorkspaceMode;
import '../../conversation/data/conversation_mirror.dart';
import '../domain/draft_values.dart';

/// One project has one text/attachment stamp, not the old pair of draft boards.
final class StartDraftRecord {
  StartDraftRecord({required this.projectId, required ResourceBudget budget})
      : _permit = budget.acquire(ResourceKind.draft, owner: 'start:$projectId'),
        _mirror = ConversationMirror(
          StartDraftState(
            stamp: DraftStamp(draftId: 'start:$projectId', revision: 0),
            text: '', attachments: const [], attachmentGeneration: 0,
            submissionRevision: 0, submission: const DraftSubmissionState.idle(),
            cleanupIssues: const [], mode: ThreadModeId.simple,
            workspaceMode: ThreadWorkspaceMode.local, preparation: null,
          ),
          budget: budget, owner: 'start:$projectId',
        );

  final String projectId;
  final ResourcePermit _permit;
  final ConversationMirror<StartDraftState> _mirror;
  final Set<DraftStamp> _unknown = {};
  OperationId? _pending;
  String? _inputId;
  bool _sealed = false;

  ReadonlyLatestValue<StartDraftState> get state => _mirror.readonly;
  bool get hasPending => _pending != null;
  bool get hasUnknown => _unknown.isNotEmpty;

  void setText(String raw) {
    _ensureOpen();
    final previous = _mirror.value;
    if (previous.text != raw) _edit(previous.copyWith(text: raw));
  }

  void setMode(ThreadModeId mode) {
    _ensureOpen();
    final previous = _mirror.value;
    if (previous.mode != mode) _edit(previous.copyWith(mode: mode));
  }

  void setWorkspaceMode(ThreadWorkspaceMode mode) {
    _ensureOpen();
    final previous = _mirror.value;
    if (previous.workspaceMode != mode) _edit(previous.copyWith(workspaceMode: mode));
  }

  void _edit(StartDraftState next) => _mirror.publish(next.copyWith(
    stamp: _next(next.stamp),
    submission: _pending == null ? const DraftSubmissionState.idle() : next.submission,
  ));

  bool adoptAttachment(AttachmentMetadata metadata, {required int generation}) {
    final previous = _mirror.value;
    if (_sealed || previous.attachmentGeneration != generation) return false;
    if (previous.attachments.any((item) => item.id == metadata.id)) {
      throw _failure(StudioFailureCode.protocol, 'An attachment admission reused an existing draft identity.');
    }
    _edit(previous.copyWith(attachments: [...previous.attachments, metadata]));
    return true;
  }

  void removeAttachment(String id) {
    _ensureOpen();
    final previous = _mirror.value;
    final next = previous.attachments.where((item) => item.id != id).toList();
    if (next.length != previous.attachments.length) _edit(previous.copyWith(attachments: next));
  }

  void discard() {
    _ensureOpen();
    final previous = _mirror.value;
    _edit(previous.copyWith(text: '', attachments: const [],
        attachmentGeneration: previous.attachmentGeneration + 1));
    // An admitted/unknown create and its preparation are not cancelled here.
  }

  void checkSubmissionAdmission() {
    _ensureOpen();
    final value = _mirror.value;
    if (_pending != null) throw _failure(StudioFailureCode.busy, 'A project submission is already in flight.');
    if (_unknown.contains(value.stamp)) throw _failure(StudioFailureCode.conflict, 'This frozen project draft has an unresolved submission.');
    if (value.text.trim().isEmpty && value.attachments.isEmpty) {
      throw _failure(StudioFailureCode.invalidArgument, 'Cannot submit an empty draft.');
    }
  }

  /// Repository first obtains the global create admission and freezes selection,
  /// route and ledger ownership; none of those are owned by this display record.
  StartDraftState beginSubmission(OperationId id, String inputId) {
    checkSubmissionAdmission();
    final frozen = _mirror.value;
    _pending = id;
    _inputId = inputId;
    _mirror.publish(frozen.copyWith(
      submissionRevision: frozen.submissionRevision + 1,
      submission: DraftSubmissionState.submitting(operationId: id, inputId: inputId),
      preparation: NewThreadPreparation(projectId: projectId, inputId: inputId,
        workspaceMode: frozen.workspaceMode, progress: null,
        phase: NewThreadPreparationPhase.preparing, failure: null),
    ));
    return frozen;
  }

  void progress(OperationId id, ThreadPreparationProgress progress) {
    if (_pending != id) return;
    if (progress.projectId != projectId || progress.inputId != _inputId) {
      throw _failure(StudioFailureCode.protocol, 'Preparation progress belongs to a different creation.');
    }
    final previous = _mirror.value;
    final preparation = previous.preparation;
    if (preparation == null) throw _failure(StudioFailureCode.protocol, 'Preparation progress has no admitted owner.');
    _mirror.publish(previous.copyWith(preparation: preparation.copyWith(progress: progress)));
  }

  void acknowledged(OperationId id, DraftStamp stamp) {
    if (_pending != id) return;
    _pending = null;
    _inputId = null;
    final previous = _mirror.value;
    final clear = previous.stamp == stamp;
    _mirror.publish(previous.copyWith(
      stamp: clear ? _next(previous.stamp) : previous.stamp,
      text: clear ? '' : previous.text, attachments: clear ? const [] : previous.attachments,
      attachmentGeneration: clear ? previous.attachmentGeneration + 1 : previous.attachmentGeneration,
      submission: const DraftSubmissionState.idle(), preparation: null,
    ));
  }

  void failed(OperationId id, String inputId, DraftStamp stamp,
      StudioFailure error, {required bool unknown}) {
    if (unknown) _unknown.add(stamp);
    if (_pending != id) return;
    _pending = null;
    _inputId = null;
    final previous = _mirror.value;
    _mirror.publish(previous.copyWith(
      submission: previous.stamp != stamp ? const DraftSubmissionState.idle()
          : unknown ? DraftSubmissionState.unknownOutcome(operationId: id, inputId: inputId, error: error)
          : DraftSubmissionState.failed(operationId: id, inputId: inputId, error: error),
      preparation: previous.preparation?.copyWith(
        phase: unknown ? NewThreadPreparationPhase.unknownOutcome : NewThreadPreparationPhase.failed,
        failure: error,
      ),
    ));
  }

  void cleanupIssues(List<AttachmentCleanupIssue> issues) =>
      _mirror.publish(_mirror.value.copyWith(cleanupIssues: issues));
  void seal() => _sealed = true;

  void dispose() {
    if (_permit.isReleased) return;
    if (_pending != null || _unknown.isNotEmpty) {
      throw _failure(StudioFailureCode.busy, 'The project draft still owns an unresolved creation.');
    }
    seal();
    _mirror.close();
    _permit.release();
  }

  DraftStamp _next(DraftStamp stamp) => stamp.copyWith(revision: stamp.revision + 1);
  void _ensureOpen() {
    if (_sealed) throw _failure(StudioFailureCode.cancelled, 'The project draft is sealed.');
  }
  StudioFailure _failure(StudioFailureCode code, String message) => StudioFailure(
      code: code, message: message, retryable: false, correlationId: 'start-draft');
}
