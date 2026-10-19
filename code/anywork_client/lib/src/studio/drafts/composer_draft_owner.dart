import 'dart:async';
import 'dart:typed_data';

import '../../../anywork_client.dart';
import '../../../models.dart';
import '../anywork_client.dart';
import 'attachment_drafts.dart';
import 'submission_observation.dart';

/// Logical Thread draft. Route/provider observers borrow it without owning it.
class ComposerDraftOwner extends ReadModel<ComposerThreadState> {
  ComposerDraftOwner(this._client, this.threadId)
    : _permit = _client.budget.acquire(
        ResourceKind.draft,
        owner: 'composer:$threadId',
      ),
      super(const ComposerThreadState.idle());

  final AnyworkClient _client;
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
      _client.attachments.admitThread(
        threadId: threadId,
        binding: binding,
        projectId: _projectId,
        sources: [
          for (final path in paths) AttachmentDraftSource.localFile(path),
        ],
      );

  Future<void> addRemoteAttachment(String url) =>
      _client.attachments.admitThread(
        threadId: threadId,
        binding: binding,
        projectId: _projectId,
        sources: [AttachmentDraftSource.remoteUrl(url.trim())],
      );

  Future<void> addClipboardImage(Uint8List pngBytes) =>
      _client.attachments.addThreadClipboard(
        threadId: threadId,
        binding: binding,
        projectId: _projectId,
        pngBytes: pngBytes,
      );

  Future<void> removeAttachment(String draftId) =>
      _client.attachments.removeThreadDraft(
        threadId: threadId,
        binding: binding,
        projectId: _projectId,
        draftId: draftId,
      );

  /// Capture every payload field and stable identity before the first await.
  FrozenComposerSubmission _freezeForSubmit() {
    if (_closed || _client.isClosed) throw StateError('The composer is closed');
    if (_pending != null) throw StateError('A submission is already pending');
    if (_unknownStamp == stamp)
      throw StateError('The previous submission outcome is unknown');
    if (state.draft.trim().isEmpty && state.attachments.isEmpty) {
      throw StateError('Cannot submit an empty draft');
    }
    final session = _client.session(threadId).state;
    if (!session.hasSnapshot || session.workspace?.thread.id != threadId) {
      throw StateError('Thread submission target is no longer available');
    }
    final blocked =
        _client.recovery.state.value?.values.any(
          (issue) =>
              issue.blocksAccess &&
              issue.scope == RecoveryIssueScope.thread &&
              issue.threadId == threadId,
        ) ??
        false;
    if (blocked || session.storage?.blocksContinuation == true) {
      throw StateError('Thread submission is blocked by recovery');
    }
    final route = session.runtime?.modelRoute;
    if (route == null || !route.available)
      throw StateError('Thread model route is unavailable');
    final frozenStamp = stamp;
    final operation = _client.mutations.begin(
      target: 'submit:$threadId',
      draft: frozenStamp,
    );
    final input = StudioPromptInput(
      inputId: operation.id.value,
      text: state.draft.trim(),
      attachmentDraftIds: List.unmodifiable(
        state.attachments.map((item) => item.id),
      ),
    );
    try {
      _client.attachments.retainFrozen(
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
    if (_pending != null ||
        (state.draft.trim().isEmpty && state.attachments.isEmpty)) {
      return Future<void>.value();
    }
    final FrozenComposerSubmission frozen;
    try {
      frozen = _freezeForSubmit();
    } catch (error) {
      reportFailure(error);
      return Future<void>.value();
    }
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
    final task = _submit(frozen, beforeSubmit);
    _pending = task;
    return task.whenComplete(() {
      if (identical(_pending, task)) _pending = null;
    });
  }

  Future<void> _submit(
    FrozenComposerSubmission frozen,
    Future<void> Function()? beforeSubmit,
  ) async {
    if (beforeSubmit != null) {
      try {
        await beforeSubmit();
      } catch (error) {
        // 展示准备失败：后端尚未收到提交，这是**已知未受理**，不是未知结果。
        frozen.operation.reject(error);
        await _client.attachments.completeFrozen(
          operationId: frozen.operation.id,
          accepted: false,
          clearCurrent: false,
          projectId: frozen.projectId,
          threadId: threadId,
        );
        if (!_closed && stamp == frozen.stamp) {
          apply(
            ComposerThreadState.failure(
              error: error.toString(),
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
    SubmitPromptReceipt? acceptedReceipt;
    try {
      final receipt = await _client.threadCommands.submitComposer(
        threadId,
        frozen.input,
        expectedModelRouteRevision: frozen.route.revision,
      );
      if (receipt.threadId != threadId ||
          receipt.inputId != frozen.input.inputId) {
        throw StateError('Thread submission receipt did not match');
      }
      acceptedReceipt = receipt;
      _observations.removeWhere((entry) => entry.isCancelled);
      _observations.add(
        observeSubmittedInput(
          client: _client,
          operation: frozen.operation,
          receipt: receipt,
        ),
      );
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
      await _client.attachments.completeFrozen(
        operationId: frozen.operation.id,
        accepted: true,
        clearCurrent: clear,
        projectId: frozen.projectId,
        threadId: threadId,
      );
    } catch (error) {
      if (acceptedReceipt != null) {
        frozen.operation.syncFailed(error);
        await _client.attachments.completeFrozen(
          operationId: frozen.operation.id,
          accepted: true,
          clearCurrent: false,
          projectId: frozen.projectId,
          threadId: threadId,
        );
      } else if (isKnownSubmissionRejection(error)) {
        frozen.operation.reject(error);
        await _client.attachments.completeFrozen(
          operationId: frozen.operation.id,
          accepted: false,
          clearCurrent: false,
          projectId: frozen.projectId,
          threadId: threadId,
        );
      } else {
        _unknownStamp = frozen.stamp;
        frozen.operation.unknownOutcome(error);
      }
      if (!_closed && stamp == frozen.stamp) {
        apply(
          ComposerThreadState.failure(
            error: error.toString(),
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
    await _client.attachments.discard(
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
      _client.session(threadId).state.workspace?.thread.projectId ??
      _client.findThread(threadId)?.projectId;
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
