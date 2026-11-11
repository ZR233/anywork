import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import '../../../acp_sessions.dart';
import '../../../directory_ports.dart';
import '../../commands/mutation_board.dart';
import '../../contracts/stamps.dart';
import '../../observation/latest_value.dart';
import '../../observation/read_model.dart';
import '../../../models.dart';
import 'drafts_dependencies.dart';
import '../domain/draft_owners.dart';
import '../domain/draft_errors.dart';
import 'draft_attachment_operations.dart';
import 'submission_observation.dart';

/// Logical Thread draft. Route/account observers borrow it without owning it.
final class ComposerDraftImpl extends ReadModel<ComposerThreadState>
    implements ComposerDraftOwner {
  ComposerDraftImpl(this._dependencies, this.threadId)
    : super(const ComposerThreadState.idle()) {
    _observeAcpMetadata();
  }

  final DraftsDependencies _dependencies;
  final String threadId;
  final LatestValue<List<ComposerSubmission>> _submissions =
      LatestValue<List<ComposerSubmission>>(const <ComposerSubmission>[]);
  final Map<String, ComposerSubmission> _submissionById = {};
  final List<Observation> _observations = [];
  int _revision = 0;
  int _generation = 0;
  bool _closed = false;
  final Map<DraftStamp, Future<void>> _pendingByStamp = {};
  final Map<String, FrozenComposerSubmission> _frozenByInput = {};
  final Map<String, Future<void>> _retryByInput = {};
  final Map<String, Future<void>> _removeTasks = {};
  final Map<String, Future<void>> _presentationTasks = {};
  final Set<String> _presentedInputIds = {};
  Future<void>? _closing;
  DraftStamp? _unknownStamp;
  DirectoryObservation<ThreadMetadataFrame>? _metadata;
  bool _acpUnknown = false;

  void _observeAcpMetadata() {
    if (_closed || _metadata != null) return;
    if (_dependencies.acpSessions?.conversationForThread(threadId) != null ||
        _dependencies.directory?.observedThread(threadId)?.backend
            is AcpAgentBackendView) {
      _metadata = _dependencies.directory?.observeThread(threadId);
    }
  }

  @override
  ValueObservation<List<ComposerSubmission>> get submissions => _submissions;

  void _publishSubmission(ComposerSubmission submission) {
    if (!_submissionById.containsKey(submission.inputId)) return;
    _submissionById[submission.inputId] = submission;
    _submissions.publish(List.unmodifiable(_submissionById.values));
  }

  void _removeSubmission(String inputId) {
    if (_submissionById.remove(inputId) == null) return;
    _submissions.publish(List.unmodifiable(_submissionById.values));
  }

  void _updateSubmissionPhase(
    String inputId,
    ComposerSubmissionPhase phase, {
    Object? error,
  }) {
    final existing = _submissionById[inputId];
    if (existing != null) {
      _publishSubmission(existing.withPhase(phase, error: error));
    }
  }

  @override
  void markInputsPresented(Iterable<String> inputIds) {
    var changed = false;
    for (final inputId in inputIds) {
      if (!_presentedInputIds.add(inputId)) continue;
      final submission = _submissionById[inputId];
      changed = _submissionById.remove(inputId) != null || changed;
      for (final observation in _observations.where(
        (entry) =>
            entry is InputSubmissionObservation && entry.inputId == inputId,
      )) {
        if (submission?.phase == ComposerSubmissionPhase.unknownOutcome) {
          observation.cancel();
        }
      }
      final frozen = _frozenByInput.remove(inputId);
      if (frozen != null) {
        _releasePresentedInput(inputId, frozen);
      }
    }
    if (changed)
      _submissions.publish(List.unmodifiable(_submissionById.values));
  }

  void _releasePresentedInput(String inputId, FrozenComposerSubmission frozen) {
    final completion = Completer<void>();
    final task = completion.future;
    _presentationTasks[inputId] = task;
    unawaited(task.then<void>((_) {}, onError: (Object _, StackTrace __) {}));
    unawaited(
      _releaseFrozen(frozen)
          .then(completion.complete, onError: completion.completeError),
    );
  }

  Future<void> _releaseFrozen(FrozenComposerSubmission frozen) async {
    await _dependencies.attachments.completeFrozen(
      operationId: frozen.operation.id,
      accepted: false,
      clearCurrent: false,
      workspaceId: frozen.workspaceId,
      threadId: threadId,
    );
    final unresolved = _dependencies.attachments.unresolvedAttachmentIds
        .toSet();
    final failedIds = frozen.input.attachmentDraftIds
        .where(unresolved.contains)
        .toList();
    if (failedIds.isNotEmpty) throw AttachmentCleanupUnresolved(failedIds);
  }

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
        workspaceId: _workspaceId,
        sources: [
          for (final path in paths) AttachmentDraftSource.localFile(path),
        ],
      );

  Future<void> addRemoteAttachment(String url) =>
      _dependencies.attachments.admitThread(
        threadId: threadId,
        binding: binding,
        workspaceId: _workspaceId,
        sources: [AttachmentDraftSource.remoteUrl(url.trim())],
      );

  Future<void> addClipboardImage(Uint8List pngBytes) =>
      _dependencies.attachments.addThreadClipboard(
        threadId: threadId,
        binding: binding,
        workspaceId: _workspaceId,
        pngBytes: pngBytes,
      );

  Future<void> removeAttachment(String draftId) =>
      _dependencies.attachments.removeThreadDraft(
        threadId: threadId,
        binding: binding,
        workspaceId: _workspaceId,
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
    if (session.directoryRow?.isChildRow ?? false) {
      throw const StudioFailure(
        code: StudioFailureCode.permissionDenied,
        message:
            'A child agent is continued and instructed by the main session',
        retryable: false,
        correlationId: 'client-child-requires-parent-scheduling',
        reason: StudioFailureReason.childThreadRequiresParentScheduling,
      );
    }
    if (session.directoryRow?.backend is! NativeAgentBackendView ||
        session.workspace!.thread.mode == null) {
      throw StateError(
        'Native root submission requires a Native backend and mode',
      );
    }
    final recoveryIssue = recoveryIssueBlockingExecution(
      _dependencies.recovery.value.value?.values ?? const [],
      workspaceId: session.workspace!.thread.workspaceId,
      threadId: threadId,
    );
    if (recoveryIssue != null) throw recoveryIssue.blockedFailure();
    final storage = session.storage;
    if (storage?.blocksContinuation == true) {
      throw threadStorageContinuationFailure(storage!);
    }
    final route = session.modelRoute;
    if (route == null || !route.available)
      throw StateError('Thread model route is unavailable');
    final frozenStamp = stamp;
    final frozenText = state.draft;
    final frozenAttachments = List<String>.unmodifiable(
      state.attachments.map((item) => item.id),
    );
    final frozenAttachmentViews = ComposerSubmission.freezeAttachments(
      state.attachments,
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
      attachments: frozenAttachmentViews,
      workspaceId: session.workspace!.thread.workspaceId,
      mode: session.workspace!.thread.mode!,
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
    if (_closed || (state.draft.trim().isEmpty && state.attachments.isEmpty))
      return Future<void>.value();
    final submissionStamp = stamp;
    final active = _pendingByStamp[submissionStamp];
    if (active != null) return active;
    final completion = Completer<void>();
    late final Future<void> pending;
    pending = completion.future.whenComplete(() {
      if (identical(_pendingByStamp[submissionStamp], pending)) {
        final removed = _pendingByStamp.remove(submissionStamp);
        if (removed == null) return;
      }
    });
    // Register before begin() publishes its synchronous mutation notification.
    _pendingByStamp[submissionStamp] = pending;
    _observeAcpMetadata();
    final metadata = _metadata?.state.value;
    if (_metadata != null &&
        (metadata!.frame == null ||
            metadata.closed ||
            metadata.error != null)) {
      reportFailure(StateError('Thread directory metadata is unavailable'));
      completion.complete();
      return pending;
    }
    final row =
        metadata?.frame?.row ??
        _dependencies.directory?.observedThread(threadId);
    if (row?.backend is AcpAgentBackendView) {
      unawaited(
        _submitAcp(
          row!,
          beforeSubmit,
        ).then(completion.complete, onError: completion.completeError),
      );
      return pending;
    }
    if (_dependencies.directory != null && row == null) {
      reportFailure(
        StateError('Thread submission target is no longer available'),
      );
      completion.complete();
      return pending;
    }
    late final FrozenComposerSubmission frozen;
    try {
      frozen = _freezeForSubmit();
    } catch (error) {
      reportFailure(error);
      completion.complete();
      return pending;
    }
    unawaited(
      _prepareAndSubmit(
        frozen,
        beforeSubmit,
      ).then(completion.complete, onError: completion.completeError),
    );
    return pending;
  }

  void _requireAcpSend(
    SessionDirectoryRow row,
    AcpConversationSession owner,
    AcpSessionTargetView target,
  ) {
    final current = _metadata?.state.value;
    final currentRow = current?.frame?.row;
    final value = owner.state;
    if (_closed ||
        _dependencies.isClosed ||
        _acpUnknown ||
        current?.closed == true ||
        current?.error != null ||
        currentRow == null ||
        currentRow.backend != row.backend ||
        currentRow.workspaceId != row.workspaceId ||
        currentRow.sessionId != target.sessionId ||
        currentRow.agentId != target.agentId ||
        currentRow.isChildRow ||
        !identical(
          _dependencies.acpSessions?.conversationForThread(threadId),
          owner,
        ) ||
        value.target != target ||
        !value.ready ||
        value.openPending ||
        value.disconnected ||
        value.observationEnded) {
      throw StateError('The ACP prompt target is unavailable or unresolved');
    }
    if (value.configPending ||
        value.configError != null ||
        value.sendPending ||
        value.activeRun != null) {
      throw StateError('Resolve ACP configuration or the current prompt first');
    }
    final workspace = _dependencies.project.value.projects?.values
        .where((item) => item.id == row.workspaceId)
        .firstOrNull;
    if (workspace == null || workspace.sshAlias != null) {
      throw StateError('ACP requires an available local workspace');
    }
    final recoveryIssue = recoveryIssueBlockingExecution(
      _dependencies.recovery.value.value?.values ?? const [],
      workspaceId: row.workspaceId,
      threadId: threadId,
    );
    if (recoveryIssue != null) throw recoveryIssue.blockedFailure();
  }

  Future<void> _submitAcp(
    SessionDirectoryRow row,
    Future<void> Function()? beforeSubmit,
  ) async {
    OperationId? operationId;
    var accepted = false;
    var clear = false;
    var dispatched = false;
    final frozenStamp = stamp;
    final generation = _generation;
    final text = state.draft;
    final attachments = List<AttachmentDraftView>.unmodifiable(
      state.attachments,
    );
    try {
      final owner = _dependencies.acpSessions?.conversationForThread(threadId);
      final target = owner?.state.target;
      if (owner == null || target == null) {
        throw StateError('The ACP conversation has not been opened');
      }
      _requireAcpSend(row, owner, target);
      operationId = OperationId(newPromptInputId());
      _dependencies.attachments.retainFrozen(
        operationId: operationId,
        binding: binding,
        attachmentIds: attachments.map((item) => item.id),
      );
      apply(
        SubmittingComposerThreadState(
          draft: state.draft,
          attachments: state.attachments,
          submissionRevision: state.submissionRevision + 1,
          attachmentGeneration: state.attachmentGeneration,
          cleanupFailureDraftIds: state.cleanupFailureDraftIds,
          inputId: operationId.value,
        ),
      );
      _requireAcpSend(row, owner, target);
      if (_generation != generation) {
        throw StateError('The ACP draft was discarded before dispatch');
      }
      final content = await _acpContent(
        text,
        attachments,
        owner.state.capabilities,
      );
      if (beforeSubmit != null) await beforeSubmit();
      _requireAcpSend(row, owner, target);
      if (_generation != generation) {
        throw StateError('The ACP draft was discarded before dispatch');
      }
      dispatched = true;
      await owner.send(content);
      accepted = true;
      clear = !_closed && stamp == frozenStamp && _generation == generation;
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
    } catch (error) {
      if (dispatched && error is! AcpBusinessFailureView) _acpUnknown = true;
      if (!_closed && _generation == generation) {
        apply(
          ComposerThreadState.failure(
            error: error,
            draft: state.draft,
            attachments: state.attachments,
            submissionRevision: state.submissionRevision,
            attachmentGeneration: state.attachmentGeneration,
            cleanupFailureDraftIds: state.cleanupFailureDraftIds,
            inputId: operationId?.value,
          ),
        );
      }
    } finally {
      if (operationId != null) {
        await _dependencies.attachments.completeFrozen(
          operationId: operationId,
          accepted: accepted,
          clearCurrent: clear,
          workspaceId: row.workspaceId,
          threadId: threadId,
        );
      }
    }
  }

  Future<List<AcpContentBlockView>> _acpContent(
    String text,
    List<AttachmentDraftView> attachments,
    AcpAgentCapabilitiesView? capabilities,
  ) async {
    final content = <AcpContentBlockView>[
      if (text.isNotEmpty) AcpTextContentView(text: text),
    ];
    for (final attachment in attachments) {
      final supported = switch (attachment.modality) {
        AttachmentModalityView.image => capabilities?.image == true,
        AttachmentModalityView.file => capabilities?.embeddedContext == true,
        AttachmentModalityView.video => false,
      };
      if (!supported) {
        throw StateError('The ACP agent does not support this attachment');
      }
      final bytes = await _dependencies.transport.readAttachmentDraft(
        attachment.id,
      );
      final data = base64Encode(bytes);
      content.add(switch (attachment.modality) {
        AttachmentModalityView.image => AcpImageContentView(
          data: data,
          mimeType: attachment.mediaType,
        ),
        AttachmentModalityView.file => AcpEmbeddedResourceView(
          resource: AcpBlobResourceContentsView(
            uri: Uri(
              scheme: 'attachment',
              pathSegments: [attachment.id, attachment.filename],
            ).toString(),
            mimeType: attachment.mediaType,
            blob: data,
          ),
        ),
        AttachmentModalityView.video => throw StateError(
          'ACP video is unsupported',
        ),
      });
    }
    return List.unmodifiable(content);
  }

  Future<void> _prepareAndSubmit(
    FrozenComposerSubmission frozen,
    Future<void> Function()? beforeSubmit,
  ) async {
    InputSubmissionObservation? evidence;
    Future<SubmitPromptReceipt>? dispatch;
    Completer<void>? beforeDispatchReady;
    Object? setupFailure;
    try {
      evidence = registerSubmittedInput(
        dependencies: _dependencies,
        operation: frozen.operation,
        inputId: frozen.input.inputId,
        expectedThreadId: threadId,
      );
      _observations.removeWhere((entry) => entry.isCancelled);
      _observations.add(evidence);
      _frozenByInput[frozen.input.inputId] = frozen;
      final dispatchReady = Completer<void>();
      beforeDispatchReady = dispatchReady;
      dispatch = _dependencies.threadCommands.submitComposer(
        threadId,
        frozen.input,
        expectedModelRouteRevision: frozen.route.revision,
        beforeDispatch: () async {
          await dispatchReady.future;
          if (setupFailure != null) throw setupFailure;
          if (_closed || _dependencies.isClosed) {
            throw StateError('Submission cancelled before backend dispatch');
          }
          if (beforeSubmit != null) await beforeSubmit();
          if (_closed || _dependencies.isClosed) {
            throw StateError('Submission cancelled before backend dispatch');
          }
        },
      );
      if (!_presentedInputIds.contains(frozen.input.inputId)) {
        _submissionById[frozen.input.inputId] = ComposerSubmission(
          inputId: frozen.input.inputId,
          text: frozen.input.text,
          attachments: frozen.attachments,
          phase: ComposerSubmissionPhase.sending,
        );
      } else {
        _frozenByInput.remove(frozen.input.inputId);
        _releasePresentedInput(frozen.input.inputId, frozen);
      }
      final attachmentGeneration = state.attachmentGeneration + 1;
      _dependencies.attachments.detachFrozenDraft(frozen.operation.id);
      apply(
        ComposerThreadState.idle(
          draft: '',
          attachments: const [],
          submissionRevision: state.submissionRevision + 1,
          attachmentGeneration: attachmentGeneration,
          cleanupFailureDraftIds: state.cleanupFailureDraftIds,
        ),
      );
      _submissions.publish(List.unmodifiable(_submissionById.values));
      beforeDispatchReady.complete();
      await _submit(frozen, evidence, dispatch);
    } catch (error) {
      if (evidence != null && !evidence.isCancelled) evidence.cancel();
      if (dispatch != null) {
        setupFailure = error;
        if (beforeDispatchReady != null && !beforeDispatchReady.isCompleted) {
          beforeDispatchReady.complete();
        }
        try {
          await dispatch;
        } catch (_) {
          // The lane wraps a beforeDispatch failure as SubmissionNotSent.
        }
      }
      if (_frozenByInput.containsKey(frozen.input.inputId)) {
        final known = error is SubmissionNotSent ? error.error : error;
        frozen.operation.reject(known);
        await _dependencies.attachments.completeFrozen(
          operationId: frozen.operation.id,
          accepted: false,
          clearCurrent: false,
          workspaceId: frozen.workspaceId,
          threadId: threadId,
          retainForRetry: true,
        );
        _updateSubmissionPhase(
          frozen.input.inputId,
          ComposerSubmissionPhase.failed,
          error: known,
        );
        return;
      }
      evidence?.cancel();
      frozen.operation.reject(error);
      await _dependencies.attachments.completeFrozen(
        operationId: frozen.operation.id,
        accepted: false,
        clearCurrent: false,
        workspaceId: frozen.workspaceId,
        threadId: threadId,
      );
      if (!_closed) reportFailure(error);
      return;
    }
  }

  Future<void> _submit(
    FrozenComposerSubmission frozen,
    InputSubmissionObservation evidence,
    Future<SubmitPromptReceipt> dispatch,
  ) async {
    SubmitPromptReceipt? acceptedReceipt;
    try {
      final receipt = await dispatch;
      if (receipt.inputId != frozen.input.inputId ||
          receipt.threadId != threadId) {
        throw StateError('Input receipt did not match the submitted request');
      }
      acceptedReceipt = receipt;
      _updateSubmissionPhase(
        frozen.input.inputId,
        ComposerSubmissionPhase.accepted,
      );
      evidence.accept(receipt);
      await _dependencies.attachments.completeFrozen(
        operationId: frozen.operation.id,
        accepted: true,
        clearCurrent: false,
        workspaceId: frozen.workspaceId,
        threadId: threadId,
      );
      _frozenByInput.remove(frozen.input.inputId);
    } catch (error) {
      final failure = error is SubmissionNotSent ? error.error : error;
      if (acceptedReceipt != null) {
        evidence.cancel();
        frozen.operation.syncFailed(failure);
        await _dependencies.attachments.completeFrozen(
          operationId: frozen.operation.id,
          accepted: true,
          clearCurrent: false,
          workspaceId: frozen.workspaceId,
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
          workspaceId: frozen.workspaceId,
          threadId: threadId,
          retainForRetry: true,
        );
        _updateSubmissionPhase(
          frozen.input.inputId,
          ComposerSubmissionPhase.failed,
          error: failure,
        );
      } else {
        if (!_presentedInputIds.contains(frozen.input.inputId)) {
          _unknownStamp = frozen.stamp;
        } else {
          evidence.cancel();
        }
        frozen.operation.unknownOutcome(failure);
        _updateSubmissionPhase(
          frozen.input.inputId,
          ComposerSubmissionPhase.unknownOutcome,
          error: failure,
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
      workspaceId: _workspaceId,
      threadId: threadId,
    );
  }

  @override
  Future<void> retrySubmission(String inputId) {
    final running = _retryByInput[inputId];
    if (running != null) return running;
    final existing = _submissionById[inputId];
    final frozen = _frozenByInput[inputId];
    if (existing == null ||
        existing.phase != ComposerSubmissionPhase.failed ||
        frozen == null) {
      return Future<void>.error(
        StateError('Submission is missing or is not retryable'),
      );
    }
    if (_closed || _dependencies.isClosed) {
      return Future<void>.error(StateError('The composer is closed'));
    }
    final completion = Completer<void>();
    late final Future<void> retry;
    retry = completion.future.whenComplete(() {
      if (identical(_retryByInput[inputId], retry)) {
        final removed = _retryByInput.remove(inputId);
        if (removed == null) return;
      }
    });
    _retryByInput[inputId] = retry;
    unawaited(
      _retryFrozen(
        inputId,
        frozen,
      ).then(completion.complete, onError: completion.completeError),
    );
    return retry;
  }

  Future<void> _retryFrozen(
    String previousInputId,
    FrozenComposerSubmission previous,
  ) async {
    final operation = _dependencies.mutations.begin(
      target: 'submit:$threadId',
      draft: previous.stamp,
    );
    final input = StudioPromptInput(
      inputId: operation.id.value,
      text: previous.input.text,
      attachmentDraftIds: previous.input.attachmentDraftIds,
    );
    _dependencies.attachments.retainRetryFrozen(
      operationId: operation.id,
      draftId: previous.stamp.draftId,
      attachmentIds: input.attachmentDraftIds,
    );
    InputSubmissionObservation? evidence;
    try {
      evidence = registerSubmittedInput(
        dependencies: _dependencies,
        operation: operation,
        inputId: input.inputId,
        expectedThreadId: threadId,
      );
      _observations.removeWhere((entry) => entry.isCancelled);
      _observations.add(evidence);
    } catch (error) {
      operation.reject(error);
      await _dependencies.attachments.completeFrozen(
        operationId: operation.id,
        accepted: false,
        clearCurrent: false,
        workspaceId: previous.workspaceId,
        threadId: threadId,
      );
      rethrow;
    }
    final replacement = FrozenComposerSubmission(
      stamp: previous.stamp,
      operation: operation,
      input: input,
      attachments: previous.attachments,
      workspaceId: previous.workspaceId,
      mode: previous.mode,
      route: previous.route,
    );
    Future<void>? previousHandoff;
    Future<void> releasePreviousOwner() =>
        previousHandoff ??= _releaseFrozen(previous);
    final dispatch = _dependencies.threadCommands.submitComposer(
      threadId,
      input,
      expectedModelRouteRevision: previous.route.revision,
      beforeDispatch: () async {
        // The retry already owns the frozen attachment IDs. Release the failed
        // operation's owner even when close sealed further dispatch.
        await releasePreviousOwner();
        if (_closed || _dependencies.isClosed) {
          throw StateError('Submission cancelled before backend dispatch');
        }
      },
    );
    _submissionById.remove(previousInputId);
    _submissionById[input.inputId] = ComposerSubmission(
      inputId: input.inputId,
      text: input.text,
      attachments: previous.attachments,
      phase: ComposerSubmissionPhase.sending,
    );
    _frozenByInput.remove(previousInputId);
    _frozenByInput[input.inputId] = replacement;
    _submissions.publish(List.unmodifiable(_submissionById.values));
    await _submit(replacement, evidence, dispatch);
    // A sealed/rejected lane may fail before invoking beforeDispatch. Still
    // complete the old-owner handoff before this retry task can satisfy close.
    await releasePreviousOwner();
  }

  @override
  Future<void> removeSubmission(String inputId) {
    final existing = _submissionById[inputId];
    if (existing == null) return Future<void>.value();
    final active = _removeTasks[inputId];
    if (active != null) return active;
    if (_closed)
      return Future<void>.error(StateError('The composer is closed'));
    if (existing.phase != ComposerSubmissionPhase.failed) {
      return Future<void>.error(
        StateError('Only failed submissions can be removed'),
      );
    }
    final completion = Completer<void>();
    final task = completion.future;
    _removeTasks[inputId] = task;
    final frozen = _frozenByInput.remove(inputId);
    _removeSubmission(inputId);
    unawaited(
      (frozen == null ? Future<void>.value() : _releaseFrozen(frozen)).then(
        completion.complete,
        onError: completion.completeError,
      ),
    );
    return task;
  }

  Future<void> close() => _closing ??= _close();

  Future<void> _close() async {
    _closed = true;
    Object? failure;
    StackTrace? failureStack;
    Future<void> waitFor(Iterable<Future<void>> tasks) async {
      try {
        await Future.wait(tasks);
      } catch (error, stackTrace) {
        failure ??= error;
        failureStack ??= stackTrace;
      }
    }

    await waitFor(_pendingByStamp.values);
    await waitFor(_retryByInput.values);
    await waitFor(_removeTasks.values);
    await waitFor(_presentationTasks.values);
    for (final frozen in _frozenByInput.values.toList()) {
      try {
        await _releaseFrozen(frozen);
      } catch (error, stackTrace) {
        failure ??= error;
        failureStack ??= stackTrace;
      }
    }
    _frozenByInput.clear();
    for (final observation in _observations) {
      observation.cancel();
    }
    _observations.clear();
    try {
      await _metadata?.release();
    } catch (error, stackTrace) {
      failure ??= error;
      failureStack ??= stackTrace;
    }
    if (failure != null) Error.throwWithStackTrace(failure!, failureStack!);
  }

  String? get _workspaceId => _dependencies.directory != null
      ? _dependencies.directory!.observedThread(threadId)?.workspaceId
      : _dependencies.conversations
            .session(threadId)
            .state
            .workspace
            ?.thread
            .workspaceId;
}

final class FrozenComposerSubmission {
  const FrozenComposerSubmission({
    required this.stamp,
    required this.operation,
    required this.input,
    required this.attachments,
    required this.workspaceId,
    required this.mode,
    required this.route,
  });
  final DraftStamp stamp;
  final OperationHandle operation;
  final StudioPromptInput input;
  final List<AttachmentDraftView> attachments;
  final String workspaceId;
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
