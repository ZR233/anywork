import 'dart:async';
import 'dart:typed_data';

import '../../commands/mutation_board.dart';
import '../../contracts/stamps.dart';
import '../../lifecycle/resource_budget.dart';
import '../../observation/latest_value.dart';
import '../../observation/read_model.dart';
import '../../../models.dart';
import 'drafts_dependencies.dart';
import '../domain/draft_owners.dart';
import 'draft_attachment_operations.dart';
import 'submission_observation.dart';

/// Logical Thread draft. Route/account observers borrow it without owning it.
final class ComposerDraftImpl extends ReadModel<ComposerThreadState>
    implements ComposerDraftOwner {
  ComposerDraftImpl(this._dependencies, this.threadId)
    : _permit = _dependencies.budget.acquire(
        ResourceKind.draft,
        owner: 'composer:$threadId',
      ),
      super(const ComposerThreadState.idle());

  final DraftsDependencies _dependencies;
  final String threadId;
  final ResourcePermit _permit;
  final List<Observation> _observations = [];
  int _revision = 0;
  int _generation = 0;
  bool _closed = false;
  Future<void>? _pending;
  Future<void>? _closing;
  DraftStamp? _unknownStamp;

  DraftStamp get stamp =>
      DraftStamp(draftId: 'composer:$threadId', revision: _revision);

  ComposerDraftBinding get binding => ComposerDraftBinding(
    read: () => state,
    write: apply,
    mounted: () => !_closed,
    draftId: stamp.draftId,
    generation: () => _generation,
  );

  void apply(ComposerThreadState next) {
    if (_closed || next == state) return;
    if (next.draft != state.draft ||
        !_sameIds(next.attachments, state.attachments)) {
      _revision += 1;
    }
    state = next;
  }

  void updateDraft(String value) => apply(state.updateDraft(value));
  void reportFailure(Object error) => apply(state.reportFailure(error));

  Future<void> addLocalAttachments(List<String> paths) =>
      _dependencies.attachments.admitThread(
        threadId: threadId,
        binding: binding,
        projectId: _projectId,
        sources: [
          for (final path in paths) AttachmentDraftSource.localFile(path),
        ],
      );

  Future<void> addRemoteAttachment(String url) =>
      _dependencies.attachments.admitThread(
        threadId: threadId,
        binding: binding,
        projectId: _projectId,
        sources: [AttachmentDraftSource.remoteUrl(url.trim())],
      );

  Future<void> addClipboardImage(Uint8List pngBytes) =>
      _dependencies.attachments.addThreadClipboard(
        threadId: threadId,
        binding: binding,
        projectId: _projectId,
        pngBytes: pngBytes,
      );

  Future<void> removeAttachment(String draftId) =>
      _dependencies.attachments.removeThreadDraft(
        threadId: threadId,
        binding: binding,
        projectId: _projectId,
        draftId: draftId,
      );

  /// Capture every payload field and stable identity before the first await.
  FrozenComposerSubmission _freezeForSubmit() {
    if (_closed || _dependencies.isClosed)
      throw StateError('The composer is closed');
    if (_unknownStamp == stamp)
      throw StateError('The previous submission outcome is unknown');
    if (state.draft.trim().isEmpty && state.attachments.isEmpty) {
      throw StateError('Cannot submit an empty draft');
    }
    final session = _dependencies.conversations.session(threadId).state;
    if (!session.hasSnapshot || session.workspace?.thread.id != threadId) {
      throw StateError('Thread submission target is no longer available');
    }
    if (!session.workspace!.thread.isRoot) {
      throw const StudioFailure(
        code: StudioFailureCode.permissionDenied,
        message:
            'A child agent is continued and instructed by the main session',
        retryable: false,
        correlationId: 'client-child-requires-parent-scheduling',
        reason: StudioFailureReason.childThreadRequiresParentScheduling,
      );
    }
    final recoveryIssue = recoveryIssueBlockingExecution(
      _dependencies.recovery.value.value?.values ?? const [],
      projectId: session.workspace!.thread.projectId,
      threadId: threadId,
    );
    if (recoveryIssue != null) throw recoveryIssue.blockedFailure();
    final storage = session.storage;
    if (storage?.blocksContinuation == true) {
      throw threadStorageContinuationFailure(storage!);
    }
    final route = session.runtime?.modelRoute;
    if (route == null || !route.available)
      throw StateError('Thread model route is unavailable');
    final frozenStamp = stamp;
    final frozenText = state.draft;
    final frozenAttachments = List<String>.unmodifiable(
      state.attachments.map((item) => item.id),
    );
    final operation = _dependencies.mutations.begin(
      target: 'submit:$threadId',
      draft: frozenStamp,
    );
    final input = StudioPromptInput(
      inputId: operation.id.value,
      text: frozenText,
      attachmentDraftIds: frozenAttachments,
    );
    try {
      _dependencies.attachments.retainFrozen(
        operationId: operation.id,
        binding: binding,
        attachmentIds: input.attachmentDraftIds,
      );
    } catch (error) {
      operation.reject(error);
      rethrow;
    }
    return FrozenComposerSubmission(
      stamp: frozenStamp,
      operation: operation,
      input: input,
      projectId: session.workspace!.thread.projectId,
      mode: session.workspace!.thread.mode,
      route: route,
    );
  }

  /// 提交一次已冻结的输入。
  ///
  /// [beforeSubmit] 是 SDK-only 的可等待展示准备钩子：它在本草稿冻结目标、payload、route、
  /// OperationId 与冻结附件引用之后，在调用后端 `submitComposer` **之前**执行。app 用它把
  /// “当前仍在显示该 Thread 时先回到实时新代次首帧”插在发送前；钩子失败保留草稿、附件与
  /// 原 History，后端从未收到该提交。钩子不写 canonical 事实，也不替代提交回执、保存观察或
  /// 附件所有权（design/26 §26.8）。
  Future<void> submit({Future<void> Function()? beforeSubmit}) {
    final current = _pending;
    if (current != null) return current;
    if (_closed || (state.draft.trim().isEmpty && state.attachments.isEmpty))
      return Future<void>.value();
    final completion = Completer<void>();
    late final Future<void> pending;
    pending = completion.future.whenComplete(() {
      if (identical(_pending, pending)) _pending = null;
    });
    // Includes synchronous freeze/budget/mutation notifications, not only RPC.
    _pending = pending;
    unawaited(
      _prepareAndSubmit(beforeSubmit)
          .then(completion.complete, onError: completion.completeError),
    );
    return pending;
  }

  Future<void> _prepareAndSubmit(Future<void> Function()? beforeSubmit) async {
    FrozenComposerSubmission? frozen;
    InputSubmissionObservation? evidence;
    try {
      frozen = _freezeForSubmit();
      evidence = registerSubmittedInput(
        dependencies: _dependencies,
        operation: frozen.operation,
        inputId: frozen.input.inputId,
        expectedThreadId: threadId,
      );
      _observations.removeWhere((entry) => entry.isCancelled);
      _observations.add(evidence);
    } catch (error) {
      evidence?.cancel();
      if (frozen != null) {
        frozen.operation.reject(error);
        await _dependencies.attachments.completeFrozen(
          operationId: frozen.operation.id,
          accepted: false,
          clearCurrent: false,
          projectId: frozen.projectId,
          threadId: threadId,
        );
      }
      if (!_closed) reportFailure(error);
      return;
    }
    if (!_closed)
      apply(
        SubmittingComposerThreadState(
          draft: state.draft,
          attachments: state.attachments,
          submissionRevision: state.submissionRevision + 1,
          attachmentGeneration: state.attachmentGeneration,
          cleanupFailureDraftIds: state.cleanupFailureDraftIds,
          inputId: frozen.input.inputId,
        ),
      );
    await _submit(frozen, beforeSubmit, evidence);
  }

  Future<void> _submit(
    FrozenComposerSubmission frozen,
    Future<void> Function()? beforeSubmit,
    InputSubmissionObservation evidence,
  ) async {
    if (!_closed && !_dependencies.isClosed && beforeSubmit != null) {
      try {
        await beforeSubmit();
      } catch (error) {
        // 展示准备失败：后端尚未收到提交，这是**已知未受理**，不是未知结果。
        evidence.cancel();
        frozen.operation.reject(error);
        await _dependencies.attachments.completeFrozen(
          operationId: frozen.operation.id,
          accepted: false,
          clearCurrent: false,
          projectId: frozen.projectId,
          threadId: threadId,
        );
        if (!_closed && stamp == frozen.stamp) {
          apply(
            ComposerThreadState.failure(
              error: error,
              draft: state.draft,
              attachments: state.attachments,
              submissionRevision: state.submissionRevision,
              attachmentGeneration: state.attachmentGeneration,
              cleanupFailureDraftIds: state.cleanupFailureDraftIds,
              inputId: frozen.input.inputId,
            ),
          );
        }
        return;
      }
    }
    if (_closed || _dependencies.isClosed) {
      final error = StateError('Submission cancelled before backend dispatch');
      evidence.cancel();
      frozen.operation.reject(error);
      await _dependencies.attachments.completeFrozen(
        operationId: frozen.operation.id,
        accepted: false,
        clearCurrent: false,
        projectId: frozen.projectId,
        threadId: threadId,
      );
      return;
    }
    SubmitPromptReceipt? acceptedReceipt;
    try {
      final receipt = await _dependencies.threadCommands.submitComposer(
        threadId,
        frozen.input,
        expectedModelRouteRevision: frozen.route.revision,
      );
      acceptedReceipt = receipt;
      evidence.accept(receipt);
      final clear = !_closed && stamp == frozen.stamp;
      if (!_closed) {
        apply(
          ComposerThreadState.idle(
            draft: clear ? '' : state.draft,
            attachments: clear ? const [] : state.attachments,
            submissionRevision: state.submissionRevision,
            attachmentGeneration: state.attachmentGeneration,
            cleanupFailureDraftIds: state.cleanupFailureDraftIds,
          ),
        );
      }
      await _dependencies.attachments.completeFrozen(
        operationId: frozen.operation.id,
        accepted: true,
        clearCurrent: clear,
        projectId: frozen.projectId,
        threadId: threadId,
      );
    } catch (error) {
      final failure = error is SubmissionNotSent ? error.error : error;
      if (acceptedReceipt != null) {
        evidence.cancel();
        frozen.operation.syncFailed(failure);
        await _dependencies.attachments.completeFrozen(
          operationId: frozen.operation.id,
          accepted: true,
          clearCurrent: false,
          projectId: frozen.projectId,
          threadId: threadId,
        );
      } else if (error is SubmissionNotSent ||
          isKnownSubmissionRejection(failure)) {
        evidence.cancel();
        frozen.operation.reject(failure);
        await _dependencies.attachments.completeFrozen(
          operationId: frozen.operation.id,
          accepted: false,
          clearCurrent: false,
          projectId: frozen.projectId,
          threadId: threadId,
        );
      } else {
        _unknownStamp = frozen.stamp;
        frozen.operation.unknownOutcome(failure);
      }
      if (!_closed && stamp == frozen.stamp) {
        apply(
          ComposerThreadState.failure(
            error: failure,
            draft: state.draft,
            attachments: state.attachments,
            submissionRevision: state.submissionRevision,
            attachmentGeneration: state.attachmentGeneration,
            cleanupFailureDraftIds: state.cleanupFailureDraftIds,
            inputId: frozen.input.inputId,
          ),
        );
      } else if (!_closed) {
        apply(
          ComposerThreadState.idle(
            draft: state.draft,
            attachments: state.attachments,
            submissionRevision: state.submissionRevision,
            attachmentGeneration: state.attachmentGeneration,
            cleanupFailureDraftIds: state.cleanupFailureDraftIds,
          ),
        );
      }
    }
  }

  Future<void> discard() async {
    if (_closed) return;
    _generation += 1;
    _revision += 1;
    await _dependencies.attachments.discard(
      binding: binding,
      projectId: _projectId,
      threadId: threadId,
    );
  }

  Future<void> close() => _closing ??= _close();

  Future<void> _close() async {
    _closed = true;
    await _pending;
    for (final observation in _observations) {
      observation.cancel();
    }
    _observations.clear();
    _permit.release();
  }

  String? get _projectId =>
      _dependencies.conversations
          .session(threadId)
          .state
          .workspace
          ?.thread
          .projectId ??
      _dependencies.findThread(threadId)?.projectId;
}

final class FrozenComposerSubmission {
  const FrozenComposerSubmission({
    required this.stamp,
    required this.operation,
    required this.input,
    required this.projectId,
    required this.mode,
    required this.route,
  });
  final DraftStamp stamp;
  final OperationHandle operation;
  final StudioPromptInput input;
  final String projectId;
  final ThreadModeId mode;
  final ThreadModelRouteView route;
}

bool _sameIds(List<AttachmentDraftView> left, List<AttachmentDraftView> right) {
  if (left.length != right.length) return false;
  for (var index = 0; index < left.length; index += 1) {
    if (left[index].id != right[index].id) return false;
  }
  return true;
}
