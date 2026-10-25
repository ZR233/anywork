import '../../../resources_ports.dart';
import '../../conversation/data/conversation_mirror.dart';
import '../domain/draft_values.dart';
import 'attachment_draft_record.dart';

/// Long-lived local composer state. Only DraftsRepository holds this writer.
/// Native dispatch/attachment ownership remain with that same repository.
final class ComposerDraftRecord implements AttachmentDraftRecord {
  ComposerDraftRecord({required this.threadId, required ResourceBudget budget})
    : _permit = budget.acquire(ResourceKind.draft, owner: 'composer:$threadId'),
      _mirror = ConversationMirror(
        ComposerDraftState(
          stamp: DraftStamp(draftId: 'composer:$threadId', revision: 0),
          text: '',
          attachments: const [],
          attachmentGeneration: 0,
          submissionRevision: 0,
          submission: const DraftSubmissionState.idle(),
          cleanupIssues: const [],
        ),
        budget: budget,
        owner: 'composer:$threadId',
      );

  final String threadId;
  final ResourcePermit _permit;
  final ConversationMirror<ComposerDraftState> _mirror;
  final Set<DraftStamp> _unknown = {};
  OperationId? _pending;
  bool _sealed = false;

  ReadonlyLatestValue<ComposerDraftState> get state => _mirror.readonly;
  @override
  DraftStamp get attachmentStamp => _mirror.value.stamp;
  @override
  int get attachmentGeneration => _mirror.value.attachmentGeneration;
  @override
  List<AttachmentMetadata> get attachmentMetadata => _mirror.value.attachments;
  bool get hasPending => _pending != null;
  bool get hasUnknown => _unknown.isNotEmpty;

  void setText(String raw) {
    _ensureOpen();
    final previous = _mirror.value;
    if (previous.text == raw) return;
    _mirror.publish(
      previous.copyWith(
        stamp: _next(previous.stamp),
        text: raw,
        submission: _editableSubmission(previous.submission),
      ),
    );
  }

  /// A late admission is adopted only after its ledger owner was registered.
  @override
  bool adoptAttachments(
    List<AttachmentMetadata> metadata, {
    required int generation,
  }) {
    final incoming = List<AttachmentMetadata>.unmodifiable(metadata);
    final previous = _mirror.value;
    if (_sealed || previous.attachmentGeneration != generation) return false;
    final ids = previous.attachments.map((item) => item.id).toSet();
    for (final item in incoming) {
      if (ids.add(item.id)) continue;
      throw _failure(
        StudioFailureCode.protocol,
        'An attachment admission reused an existing draft identity.',
      );
    }
    if (incoming.isEmpty) return true;
    _mirror.publish(
      previous.copyWith(
        stamp: _next(previous.stamp),
        attachments: [...previous.attachments, ...incoming],
        submission: _editableSubmission(previous.submission),
      ),
    );
    return true;
  }

  void removeAttachment(String draftId) {
    _ensureOpen();
    final previous = _mirror.value;
    final next = previous.attachments
        .where((item) => item.id != draftId)
        .toList();
    if (next.length == previous.attachments.length) return;
    _mirror.publish(
      previous.copyWith(
        stamp: _next(previous.stamp),
        attachments: next,
        submission: _editableSubmission(previous.submission),
      ),
    );
  }

  void discard() {
    _ensureOpen();
    _discard();
  }

  bool discardCaptured(DraftStamp stamp, int generation) {
    if (_mirror.value.stamp != stamp ||
        _mirror.value.attachmentGeneration != generation)
      return false;
    _discard();
    return true;
  }

  void _discard() {
    final previous = _mirror.value;
    _mirror.publish(
      previous.copyWith(
        stamp: _next(previous.stamp),
        text: '',
        attachments: const [],
        attachmentGeneration: previous.attachmentGeneration + 1,
        submission: _editableSubmission(previous.submission),
      ),
    );
    // This only releases the draft's ownership. The repository retains every
    // frozen operation reference, including UnknownOutcome, in its ledger.
  }

  void checkSubmissionAdmission() {
    _ensureOpen();
    final value = _mirror.value;
    if (_pending != null)
      throw _failure(
        StudioFailureCode.busy,
        'A submission is already in flight.',
      );
    if (_unknown.contains(value.stamp))
      throw _failure(
        StudioFailureCode.conflict,
        'This frozen draft has an unresolved submission.',
      );
    if (value.text.trim().isEmpty && value.attachments.isEmpty) {
      throw _failure(
        StudioFailureCode.invalidArgument,
        'Cannot submit an empty draft.',
      );
    }
  }

  /// The caller freezes Session/route and retains attachments in the same
  /// synchronous admission before it starts presentation preparation or dispatch.
  ComposerDraftState beginSubmission(OperationId id, String inputId) {
    checkSubmissionAdmission();
    final frozen = _mirror.value;
    _pending = id;
    _mirror.publish(
      frozen.copyWith(
        submissionRevision: frozen.submissionRevision + 1,
        submission: DraftSubmissionState.submitting(
          operationId: id,
          inputId: inputId,
        ),
      ),
    );
    return frozen;
  }

  bool acknowledged(OperationId id, DraftStamp frozenStamp) {
    final recovered = _unknown.remove(frozenStamp);
    final previous = _mirror.value;
    if (_pending != id &&
        !(recovered && _pending == null && previous.stamp == frozenStamp))
      return false;
    if (_pending == id) _pending = null;
    final clear = previous.stamp == frozenStamp;
    _mirror.publish(
      previous.copyWith(
        stamp: clear ? _next(previous.stamp) : previous.stamp,
        text: clear ? '' : previous.text,
        attachments: clear ? const [] : previous.attachments,
        attachmentGeneration: clear
            ? previous.attachmentGeneration + 1
            : previous.attachmentGeneration,
        submission: const DraftSubmissionState.idle(),
      ),
    );
    return clear;
  }

  void failed(
    OperationId id,
    String inputId,
    DraftStamp frozenStamp,
    StudioFailure error, {
    required bool unknown,
  }) {
    final recovered = !unknown && _unknown.remove(frozenStamp);
    if (unknown) _unknown.add(frozenStamp);
    if (_pending != id &&
        !(recovered && _pending == null && _mirror.value.stamp == frozenStamp))
      return;
    _pending = null;
    final previous = _mirror.value;
    _mirror.publish(
      previous.copyWith(
        submission: previous.stamp != frozenStamp
            ? const DraftSubmissionState.idle()
            : unknown
            ? DraftSubmissionState.unknownOutcome(
                operationId: id,
                inputId: inputId,
                error: error,
              )
            : DraftSubmissionState.failed(
                operationId: id,
                inputId: inputId,
                error: error,
              ),
      ),
    );
  }

  void cleanupIssues(List<AttachmentCleanupIssue> issues) {
    _mirror.publish(_mirror.value.copyWith(cleanupIssues: issues));
  }

  void seal() => _sealed = true;

  /// The repository calls this only after native work and frozen references end.
  /// Unknown payloads are not abandoned just because the application unmounted.
  void dispose() {
    if (_permit.isReleased) return;
    if (_pending != null || _unknown.isNotEmpty) {
      throw _failure(
        StudioFailureCode.busy,
        'The draft still owns an unresolved submission.',
      );
    }
    seal();
    _mirror.close();
    _permit.release();
  }

  DraftSubmissionState _editableSubmission(DraftSubmissionState previous) =>
      _pending == null ? const DraftSubmissionState.idle() : previous;
  DraftStamp _next(DraftStamp stamp) =>
      stamp.copyWith(revision: stamp.revision + 1);
  void _ensureOpen() {
    if (_sealed)
      throw _failure(
        StudioFailureCode.cancelled,
        'The composer draft is sealed.',
      );
  }

  StudioFailure _failure(StudioFailureCode code, String message) =>
      StudioFailure(
        code: code,
        message: message,
        retryable: false,
        correlationId: 'composer-draft',
      );
}
