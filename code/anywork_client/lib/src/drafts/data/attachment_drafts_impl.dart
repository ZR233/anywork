import 'dart:async';
import 'dart:developer' show log;
import 'dart:typed_data';

import '../../contracts/stamps.dart';
import '../../lifecycle/resource_budget.dart';
import '../../observation/read_model.dart';
import '../../../models.dart';
import 'attachment_ledger.dart';
import '../../../studio_ports.dart';
import 'drafts_dependencies.dart';
import '../domain/draft_errors.dart';
import 'draft_attachment_operations.dart';
import '../../studio/commands/command_lane.dart';

/// 附件草稿的 admission / preview / removal。
///
/// 两阶段：先发布稳定 metadata，再按 draft id 异步补 preview。预览失败保留已准入
/// 附件并写入 typed composer failure。同一逻辑草稿的写入由 [CommandLane] 串行，
/// 页面观察者的销毁与重建不改变草稿或附件所有权。
/// 失败只记录诊断，不回滚 canonical。
final class AttachmentDraftsImpl extends ReadModel<AttachmentDraftBoard>
    implements DraftAttachmentOperations {
  AttachmentDraftsImpl(
    this._dependencies, {
    this.clipboardImageStager,
    this.clipboardImageCleanup,
  }) : _ownership = AttachmentDraftStore(budget: _dependencies.budget),
       super(const AttachmentDraftBoard());

  final DraftsDependencies _dependencies;
  final Future<String?> Function(Uint8List)? clipboardImageStager;
  final Future<void> Function(String)? clipboardImageCleanup;
  final AttachmentDraftStore _ownership;
  final Map<OperationId, _FrozenAttachments> _submissions = {};
  final Map<String, int> _newThreadGenerations = {};
  final Map<String, int> _newThreadRevisions = {};
  final Map<String, _CleanupFailure> _unresolvedCleanup = {};
  final Map<String, Object> _unresolvedAdmissions = {};
  final Map<String, _StagingCleanupFailure> _unresolvedStaging = {};
  final Set<Future<void>> _tasks = {};
  Future<void>? _closing;
  Future<void>? _cleanupRetry;
  int _admissionSequence = 0;
  bool _closed = false;
  bool _admissionsSealed = false;
  final Map<String, CommandLane> _lanes = {};

  /// Exit seals new native work immediately; accepted submissions retain their
  /// frozen ownership until they finish, and explicit cleanup remains legal.
  void sealAdmissions() {
    _admissionsSealed = true;
  }

  Future<T> runLocked<T>(String targetKey, Future<T> Function() action) {
    return _lane(targetKey).enqueue(action);
  }

  Future<void> admitThread({
    required String threadId,
    required ComposerDraftBinding binding,
    required List<AttachmentDraftSource> sources,
    required String? projectId,
  }) {
    if (_admissionsSealed) return Future<void>.value();
    return _track(
      () => _admit(
        targetKey: attachmentLaneKeyForThread(threadId),
        context: AttachmentAdmissionContext.existingThread(threadId),
        sources: sources,
        binding: binding,
        projectId: projectId,
        threadId: threadId,
        targetCurrent: () => _threadTargetCurrent(threadId),
      ),
    );
  }

  Future<void> removeThreadDraft({
    required String threadId,
    required String draftId,
    required ComposerDraftBinding binding,
    required String? projectId,
  }) {
    return _track(
      () => _remove(
        targetKey: attachmentLaneKeyForThread(threadId),
        draftId: draftId,
        binding: binding,
        projectId: projectId,
        threadId: threadId,
      ),
    );
  }

  Future<void> addThreadClipboard({
    required String threadId,
    required Uint8List pngBytes,
    required ComposerDraftBinding binding,
    required String? projectId,
  }) {
    if (_admissionsSealed) return Future<void>.value();
    return _track(
      () => _addClipboard(
        targetKey: attachmentLaneKeyForThread(threadId),
        pngBytes: pngBytes,
        context: AttachmentAdmissionContext.existingThread(threadId),
        binding: binding,
        projectId: projectId,
        threadId: threadId,
        targetCurrent: () => _threadTargetCurrent(threadId),
      ),
    );
  }

  void seedNewThreadIfEmpty(String projectId, ComposerThreadState incoming) {
    if (_closed || _admissionsSealed) return;
    final current = state.newThread(projectId);
    if (current.attachments.isNotEmpty ||
        current.cleanupFailureDraftIds.isNotEmpty ||
        current.error != null) {
      return;
    }
    if (incoming.isSubmissionPending ||
        (incoming.attachments.isEmpty && incoming.error == null)) {
      return;
    }
    var seeded = const ComposerThreadState.idle().updateAttachments(
      incoming.attachments,
    );
    if (incoming.cleanupFailureDraftIds.isNotEmpty) {
      seeded = seeded.reportAttachmentCleanupFailure(
        incoming.cleanupFailureDraftIds,
      );
    }
    if (incoming.error != null) {
      seeded = seeded.reportFailure(StateError(incoming.error!));
    }
    try {
      _ownership.adopt(
        'start:$projectId',
        seeded.attachments.map((item) => item.id),
      );
      _putNewThread(projectId, seeded);
    } catch (error) {
      reportNewThreadFailure(projectId, error);
    }
  }

  Future<void> admitNewThread({
    required String projectId,
    required ThreadModeId mode,
    required List<AttachmentDraftSource> sources,
  }) {
    if (_closed || _admissionsSealed) return Future<void>.value();
    final context = _newThreadContext(projectId, mode);
    if (context == null) return Future<void>.value();
    return _track(
      () => _admit(
        targetKey: attachmentLaneKeyForNewThread(projectId),
        context: context,
        sources: sources,
        binding: _newThreadBinding(projectId),
        projectId: projectId,
        threadId: null,
        targetCurrent: () => _newThreadCurrent(projectId),
      ),
    );
  }

  Future<void> removeNewThreadDraft(String projectId, String draftId) {
    return _track(
      () => _remove(
        targetKey: attachmentLaneKeyForNewThread(projectId),
        draftId: draftId,
        binding: _newThreadBinding(projectId),
        projectId: projectId,
        threadId: null,
      ),
    );
  }

  Future<void> addNewThreadRemote({
    required String projectId,
    required ThreadModeId mode,
    required String url,
  }) {
    return admitNewThread(
      projectId: projectId,
      mode: mode,
      sources: [AttachmentDraftSource.remoteUrl(url.trim())],
    );
  }

  Future<void> addNewThreadClipboard({
    required String projectId,
    required ThreadModeId mode,
    required Uint8List pngBytes,
  }) {
    if (_closed || _admissionsSealed) return Future<void>.value();
    final context = _newThreadContext(projectId, mode);
    if (context == null) return Future<void>.value();
    return _track(
      () => _addClipboard(
        targetKey: attachmentLaneKeyForNewThread(projectId),
        pngBytes: pngBytes,
        context: context,
        binding: _newThreadBinding(projectId),
        projectId: projectId,
        threadId: null,
        targetCurrent: () => _newThreadCurrent(projectId),
      ),
    );
  }

  AttachmentAdmissionContext? _newThreadContext(
    String projectId,
    ThreadModeId mode,
  ) {
    try {
      return AttachmentAdmissionContext.newThread(
        _dependencies.startDraft.resolveRoute(mode),
      );
    } catch (error) {
      reportNewThreadFailure(projectId, error);
      return null;
    }
  }

  void reportNewThreadFailure(String projectId, Object error) {
    final binding = _newThreadBinding(projectId);
    if (!binding.mounted()) return;
    final current = binding.read();
    binding.write(current.reportFailure(error));
  }

  Future<void> _admit({
    required String targetKey,
    required AttachmentAdmissionContext context,
    required List<AttachmentDraftSource> sources,
    required ComposerDraftBinding binding,
    required String? projectId,
    required String? threadId,
    required bool Function() targetCurrent,
  }) async {
    if (_closed || _admissionsSealed || sources.isEmpty) return;
    final admitted = await _lane(targetKey).enqueue(() async {
      if (_closed ||
          _admissionsSealed ||
          !binding.mounted() ||
          !targetCurrent())
        return null;
      final generation = binding.generation();
      final reservations = <ResourcePermit>[];
      final admission = ++_admissionSequence;
      var dispatched = false;
      final List<AttachmentDraftView> drafts;
      try {
        // Native admission creates exactly one draft per source. Reserve its
        // budget before dispatch, including time spent opening and retiring.
        for (var index = 0; index < sources.length; index += 1) {
          reservations.add(
            _dependencies.budget.acquire(
              ResourceKind.attachment,
              owner: 'admission:$admission:$index',
              phase: ResourcePhase.opening,
            ),
          );
        }
        dispatched = true;
        drafts = await _api.admitAttachmentDrafts(context, sources);
      } catch (error) {
        if (!dispatched || _knownAdmissionRejection(error)) {
          for (final permit in reservations) {
            permit.release();
          }
        } else {
          // No receipt means these native IDs are unknown. Keep the original
          // opening permits instead of claiming the backend allocated nothing.
          for (final permit in reservations) {
            permit.mark(ResourcePhase.unresolved);
          }
          _unresolvedAdmissions['admission:$admission'] = error;
        }
        if (_closed ||
            _admissionsSealed ||
            !binding.mounted() ||
            !targetCurrent())
          return null;
        final current = binding.read();
        if (binding.generation() != generation) {
          return null;
        }
        binding.write(current.reportFailure(error));
        return null;
      }
      // No await separates the reservation handoff and the actual draft IDs.
      for (final permit in reservations) {
        permit.release();
      }
      if (drafts.isEmpty) return null;
      if (_closed ||
          _admissionsSealed ||
          !binding.mounted() ||
          !targetCurrent()) {
        await _cleanupOrphans(
          drafts.map((draft) => draft.id),
          projectId: projectId,
          threadId: threadId,
        );
        return null;
      }
      final current = binding.read();
      if (binding.generation() != generation) {
        await _cleanupOrphans(
          drafts.map((draft) => draft.id),
          projectId: projectId,
          threadId: threadId,
        );
        return null;
      }
      try {
        _ownership.adopt(binding.draftId, drafts.map((draft) => draft.id));
      } catch (error) {
        await _cleanupOrphans(
          drafts.map((draft) => draft.id),
          projectId: projectId,
          threadId: threadId,
        );
        if (binding.mounted())
          binding.write(binding.read().reportFailure(error));
        return null;
      }
      final updated = current.updateAttachments([
        ...current.attachments,
        ...drafts,
      ]);
      binding.write(updated);
      return drafts;
    });
    if (admitted == null || admitted.isEmpty) return;
    await Future.wait([
      for (final draft in admitted)
        if (draft.modality == AttachmentModalityView.image)
          _readPreview(
            draft,
            binding: binding,
            projectId: projectId,
            threadId: threadId,
            targetKey: targetKey,
            targetCurrent: targetCurrent,
          ),
    ]);
  }

  /// 预览写入前重新读取最新草稿。只替换同一 draft id 的 preview bytes，因此不再用
  /// attachment generation 当写屏障；id 已不在时丢弃这次字节。
  Future<void> _readPreview(
    AttachmentDraftView draft, {
    required ComposerDraftBinding binding,
    required String? projectId,
    required String? threadId,
    required String targetKey,
    required bool Function() targetCurrent,
  }) async {
    if (_admissionsSealed) return;
    final Uint8List bytes;
    try {
      bytes = await _api.readAttachmentDraft(draft.id);
    } catch (error) {
      await _lane(targetKey).enqueue(() async {
        if (_closed || !binding.mounted() || !targetCurrent()) {
          return;
        }
        final current = binding.read();
        final present = current.attachments
            .where((attachment) => attachment.id == draft.id)
            .firstOrNull;
        if (present == null || present.previewBytes != null) return;
        _reportPreviewFailure(
          binding,
          error,
          draftId: draft.id,
          targetCurrent: targetCurrent,
        );
      });
      return;
    }
    await _lane(targetKey).enqueue(() async {
      if (_closed || !binding.mounted() || !targetCurrent()) {
        return;
      }
      final current = binding.read();
      final present = current.attachments
          .where((attachment) => attachment.id == draft.id)
          .firstOrNull;
      if (present == null || present.previewBytes != null) return;
      final updated = current.updateAttachmentPreview(draft.id, bytes);
      if (!identical(updated, current)) binding.write(updated);
    });
  }

  void _reportPreviewFailure(
    ComposerDraftBinding binding,
    Object error, {
    required String draftId,
    required bool Function() targetCurrent,
  }) {
    if (!binding.mounted() || !targetCurrent()) return;
    final current = binding.read();
    if (!current.attachments.any((attachment) => attachment.id == draftId)) {
      return;
    }
    binding.write(current.reportAttachmentFailure(error));
  }

  Future<void> _remove({
    required String targetKey,
    required String draftId,
    required ComposerDraftBinding binding,
    required String? projectId,
    required String? threadId,
  }) {
    return _lane(targetKey).enqueue(() async {
      if (!binding.mounted()) return;
      final current = binding.read();
      if (!current.attachments.any((item) => item.id == draftId)) return;
      final frozen = _submissions.values.any(
        (value) => value.ids.contains(draftId),
      );
      if (frozen) {
        _ownership.detach(binding.draftId, [draftId]);
        _unresolvedCleanup.remove(draftId);
        binding.write(current.removeAttachment(draftId));
        return;
      }
      try {
        if (!await _api.removeAttachmentDraft(draftId)) {
          throw StateError('Attachment draft is unavailable.');
        }
        _ownership.detach(binding.draftId, [draftId]);
        _unresolvedCleanup.remove(draftId);
        if (binding.mounted()) {
          binding.write(binding.read().removeAttachment(draftId));
        }
      } catch (error) {
        _unresolvedCleanup[draftId] = _CleanupFailure(
          projectId,
          threadId,
          error,
          binding: binding,
        );
        if (binding.mounted()) {
          binding.write(
            binding.read().reportAttachmentCleanupFailure([draftId]),
          );
        }
        _record(
          projectId: projectId,
          threadId: threadId,
          message: 'Attachment removal failed for draft ID: $draftId: $error',
          cleanupFailureDraftIds: [draftId],
        );
      }
    });
  }

  Future<void> _addClipboard({
    required String targetKey,
    required Uint8List pngBytes,
    required AttachmentAdmissionContext context,
    required ComposerDraftBinding binding,
    required String? projectId,
    required String? threadId,
    required bool Function() targetCurrent,
  }) async {
    if (_closed || _admissionsSealed || !binding.mounted() || !targetCurrent())
      return;
    if (pngBytes.isEmpty) {
      await _lane(targetKey).enqueue(() async {
        if (!binding.mounted() || !targetCurrent()) return;
        final current = binding.read();
        binding.write(
          current.reportFailure(StateError('Clipboard image is empty.')),
        );
      });
      return;
    }
    String? path;
    ResourcePermit? stagingPermit;
    var stagingDispatched = false;
    var stagingReturned = false;
    final stagingOwner = 'clipboard-staging:${++_admissionSequence}';
    try {
      final stage = clipboardImageStager;
      if (stage == null)
        throw StateError('Clipboard image staging is unavailable.');
      stagingPermit = _dependencies.budget.acquire(
        ResourceKind.attachment,
        owner: stagingOwner,
        phase: ResourcePhase.opening,
      );
      stagingDispatched = true;
      path = await stage(Uint8List.fromList(pngBytes));
      stagingReturned = true;
      if (path == null || path.isEmpty) {
        throw StateError('Clipboard image staging did not return a file.');
      }
      stagingPermit.mark(ResourcePhase.active);
      await _admit(
        targetKey: targetKey,
        context: context,
        sources: [AttachmentDraftSource.localFile(path)],
        binding: binding,
        projectId: projectId,
        threadId: threadId,
        targetCurrent: targetCurrent,
      );
    } catch (error) {
      if (stagingDispatched && !stagingReturned && stagingPermit != null) {
        // The callback did not return an identity, so a created staging file
        // cannot be disproved or silently accounted as already reclaimed.
        stagingPermit.mark(ResourcePhase.unresolved);
        _unresolvedAdmissions[stagingOwner] = error;
        stagingPermit = null;
      }
      await _lane(targetKey).enqueue(() async {
        if (!binding.mounted() || !targetCurrent()) return;
        binding.write(binding.read().reportAttachmentFailure(error));
      });
    } finally {
      if (path != null && path.isNotEmpty) {
        try {
          final cleanup = clipboardImageCleanup;
          if (cleanup == null)
            throw StateError('Clipboard staging cleanup is unavailable.');
          await cleanup(path);
          stagingPermit?.release();
        } catch (error, stack) {
          final permit = stagingPermit;
          if (permit != null) {
            permit.mark(ResourcePhase.unresolved);
            _unresolvedStaging[stagingOwner] = _StagingCleanupFailure(
              path,
              permit,
              error,
            );
          }
          log(
            'clipboard staging cleanup failed',
            error: error,
            stackTrace: stack,
          );
        }
      } else {
        stagingPermit?.release();
      }
    }
  }

  Future<void> _cleanupOrphans(
    Iterable<String> draftIds, {
    required String? projectId,
    required String? threadId,
  }) async {
    final candidates = draftIds.toSet();
    if (candidates.isEmpty) return;
    // Cleanup itself retains ownership and budget until native deletion really
    // succeeds. No Map clear can stand in for that acknowledgement.
    _ownership.adopt(_cleanupOwner, candidates);
    final failures = <String, Object>{};
    for (final draftId in candidates) {
      var removed = false;
      Object? lastError;
      for (var attempt = 0; attempt < 2 && !removed; attempt++) {
        try {
          removed = await _api.removeAttachmentDraft(draftId);
          if (!removed) {
            lastError = StateError(
              'Attachment draft removal returned false: $draftId',
            );
          }
        } catch (error) {
          lastError = error;
        }
      }
      if (!removed) {
        failures[draftId] =
            lastError ?? StateError('Attachment draft cleanup failed.');
        _unresolvedCleanup[draftId] = _CleanupFailure(
          projectId,
          threadId,
          failures[draftId]!,
        );
      } else {
        _unresolvedCleanup.remove(draftId);
        _ownership.detach(_cleanupOwner, [draftId]);
      }
    }
    if (failures.isEmpty) return;
    final ids = failures.keys.toList()..sort();
    _record(
      projectId: projectId,
      threadId: threadId,
      message: 'Attachment cleanup failed for draft IDs: ${ids.join(', ')}',
      cleanupFailureDraftIds: ids,
    );
    for (final entry in failures.entries) {
      log(
        'attachment cleanup failed projectId=$projectId threadId=$threadId draftId=${entry.key}',
        error: entry.value,
      );
    }
  }

  void _record({
    required String? projectId,
    required String? threadId,
    required String message,
    Iterable<String> cleanupFailureDraftIds = const [],
  }) {
    if (projectId == null) return;
    final key = attachmentTargetKey(projectId, threadId);
    final previous = state.diagnostics[key];
    final ids = {
      ...?previous?.cleanupFailureDraftIds,
      ...cleanupFailureDraftIds,
    }.toList()..sort();
    final diagnostic = ComposerTargetDiagnostic(
      projectId: projectId,
      threadId: threadId,
      message: message,
      cleanupFailureDraftIds: ids,
    );
    if (diagnostic == previous) return;
    state = state.copyWith(
      diagnostics: {...state.diagnostics, key: diagnostic},
    );
  }

  ComposerDraftBinding _newThreadBinding(String projectId) {
    return ComposerDraftBinding(
      read: () => state.newThread(projectId),
      write: (next) => _putNewThread(projectId, next),
      mounted: () => !_closed,
      draftId: 'start:$projectId',
      generation: () => _newThreadGenerations[projectId] ?? 0,
    );
  }

  void _putNewThread(String projectId, ComposerThreadState next) {
    if (_closed) return;
    if (state.newThread(projectId) == next &&
        state.newThreadDrafts.containsKey(projectId)) {
      return;
    }
    final previous = state.newThread(projectId);
    if (!_sameAttachmentIds(previous.attachments, next.attachments)) {
      _newThreadRevisions[projectId] =
          (_newThreadRevisions[projectId] ?? 0) + 1;
    }
    state = state.copyWith(
      newThreadDrafts: {...state.newThreadDrafts, projectId: next},
    );
  }

  void _clearNewThread(String projectId) {
    if (!state.newThreadDrafts.containsKey(projectId)) return;
    state = state.copyWith(
      newThreadDrafts: {...state.newThreadDrafts}..remove(projectId),
    );
  }

  bool _threadTargetCurrent(String threadId) {
    final thread = _lookupThread(threadId);
    if (thread == null) {
      final session = _dependencies.conversations.session(threadId).state;
      return session.hasSnapshot && session.workspace?.thread.isRoot == true;
    }
    if (!thread.isRoot) return false;
    // faulted 可能只是模型或工具输入驱动失败，后端续接会重新启用驱动并创建新的
    // 执行轮次；只有类型化存储事实明确阻塞准入时，才沿用存储恢复闸门。
    return switch (thread.status) {
      ThreadStatusView.closing || ThreadStatusView.closed => false,
      ThreadStatusView.faulted =>
        _dependencies.conversations
                .session(threadId)
                .state
                .storage
                ?.blocksContinuation !=
            true,
      _ => true,
    };
  }

  StudioThread? _lookupThread(String threadId) {
    for (final thread in _dependencies.threads()) {
      if (thread.id == threadId) return thread;
    }
    return _dependencies.conversations
        .session(threadId)
        .state
        .workspace
        ?.thread;
  }

  bool _newThreadCurrent(String projectId) {
    final projects = _dependencies.project.value.projects?.values ?? const [];
    return projects.any((project) => project.id == projectId);
  }

  ComposerDraftBinding newThreadBinding(String projectId) =>
      _newThreadBinding(projectId);

  DraftStamp newThreadStamp(String projectId) => DraftStamp(
    draftId: 'start:$projectId',
    revision: _newThreadRevisions[projectId] ?? 0,
  );

  void retainFrozen({
    required OperationId operationId,
    required ComposerDraftBinding binding,
    required Iterable<String> attachmentIds,
  }) {
    if (_submissions.containsKey(operationId)) {
      throw StateError('The submission already owns attachments');
    }
    final ids = List<String>.unmodifiable(attachmentIds);
    _ownership.adopt(binding.draftId, ids);
    _ownership.freeze(operationId, ids);
    _submissions[operationId] = _FrozenAttachments(binding.draftId, ids);
  }

  Future<void> completeFrozen({
    required OperationId operationId,
    required bool accepted,
    required bool clearCurrent,
    required String? projectId,
    required String? threadId,
  }) async {
    final frozen = _submissions.remove(operationId);
    if (frozen == null) return;
    if (clearCurrent) _ownership.detach(frozen.draftId, frozen.ids);
    final released = _ownership.completeSubmission(operationId);
    // Session resources were promoted before acceptance. Staging remains
    // immutable and reusable while any logical draft still owns the same ID.
    if (released.isNotEmpty) {
      await _cleanupOrphans(released, projectId: projectId, threadId: threadId);
    }
  }

  Future<void> discard({
    required ComposerDraftBinding binding,
    required String? projectId,
    required String? threadId,
  }) async {
    final released = _ownership.discardDraft(binding.draftId);
    binding.write(const ComposerThreadState.idle());
    await _cleanupOrphans(released, projectId: projectId, threadId: threadId);
  }

  Future<void> discardProject(String projectId) async {
    _newThreadGenerations[projectId] =
        (_newThreadGenerations[projectId] ?? 0) + 1;
    await discard(
      binding: _newThreadBinding(projectId),
      projectId: projectId,
      threadId: null,
    );
    _clearNewThread(projectId);
  }

  List<String> get unresolvedAttachmentIds =>
      List.unmodifiable(_unresolvedCleanup.keys);
  List<String> get unresolvedStagingPaths => List.unmodifiable(
    _unresolvedStaging.values.map((failure) => failure.path),
  );

  Future<void> retryCleanup() {
    final existing = _cleanupRetry;
    if (existing != null) return existing;
    late final Future<void> task;
    task = _track(_retryCleanup, cleanupOnly: true).whenComplete(() {
      if (identical(_cleanupRetry, task)) _cleanupRetry = null;
    });
    _cleanupRetry = task;
    return task;
  }

  Future<void> _retryCleanup() async {
    for (final entry in List.of(_unresolvedStaging.entries)) {
      try {
        final cleanup = clipboardImageCleanup;
        if (cleanup == null)
          throw StateError('Clipboard staging cleanup is unavailable.');
        await cleanup(entry.value.path);
        _unresolvedStaging.remove(entry.key);
        entry.value.permit.release();
      } catch (error) {
        _unresolvedStaging[entry.key] = _StagingCleanupFailure(
          entry.value.path,
          entry.value.permit,
          error,
        );
      }
    }
    for (final entry in List.of(_unresolvedCleanup.entries)) {
      final failure = entry.value;
      final binding = failure.binding;
      if (binding != null && !_closed) {
        await _remove(
          targetKey: failure.threadId == null
              ? attachmentLaneKeyForNewThread(failure.projectId!)
              : attachmentLaneKeyForThread(failure.threadId!),
          draftId: entry.key,
          binding: binding,
          projectId: failure.projectId,
          threadId: failure.threadId,
        );
      } else {
        if (binding != null) {
          final frozen = _submissions.values.any(
            (value) => value.ids.contains(entry.key),
          );
          if (frozen) {
            _ownership.detach(binding.draftId, [entry.key]);
            _unresolvedCleanup.remove(entry.key);
            continue;
          }
          // This explicit retry completes the user's earlier delete intent.
          // Keep cleanup ownership through the native ACK even though the UI
          // binding has retired; do not reopen it or accept new attachments.
          _ownership.adopt(_cleanupOwner, [entry.key]);
          _ownership.detach(binding.draftId, [entry.key]);
        }
        await _cleanupOrphans(
          [entry.key],
          projectId: failure.projectId,
          threadId: failure.threadId,
        );
      }
    }
    if (_unresolvedCleanup.isNotEmpty ||
        _unresolvedAdmissions.isNotEmpty ||
        _unresolvedStaging.isNotEmpty) {
      throw AttachmentCleanupUnresolved(
        unresolvedAttachmentIds,
        admissionOwners: _unresolvedAdmissions.keys,
        stagingPaths: unresolvedStagingPaths,
      );
    }
  }

  Future<void> _track(
    Future<void> Function() action, {
    bool cleanupOnly = false,
  }) {
    if (_closed && !cleanupOnly) return Future<void>.value();
    late final Future<void> task;
    task = Future<void>.sync(action).whenComplete(() {
      _tasks.remove(task);
    });
    _tasks.add(task);
    return task;
  }

  Future<void> close() => _closing ??= _close();

  Future<void> _close() async {
    sealAdmissions();
    _closed = true;
    // Includes clipboard staging and preview reads, not only lane tails.
    while (_tasks.isNotEmpty) {
      await Future.wait(List.of(_tasks));
    }
    if (_unresolvedCleanup.isNotEmpty ||
        _unresolvedAdmissions.isNotEmpty ||
        _unresolvedStaging.isNotEmpty) {
      throw AttachmentCleanupUnresolved(
        unresolvedAttachmentIds,
        admissionOwners: _unresolvedAdmissions.keys,
        stagingPaths: unresolvedStagingPaths,
      );
    }
  }

  CommandLane _lane(String targetKey) =>
      _lanes.putIfAbsent(targetKey, CommandLane.new);

  AttachmentTransport get _api => _dependencies.transport;
}

const _cleanupOwner = '<native-cleanup>';

final class _StagingCleanupFailure {
  const _StagingCleanupFailure(this.path, this.permit, this.error);
  final String path;
  final ResourcePermit permit;
  final Object error;
}

final class _CleanupFailure {
  const _CleanupFailure(
    this.projectId,
    this.threadId,
    this.error, {
    this.binding,
  });
  final String? projectId;
  final String? threadId;
  final Object error;
  final ComposerDraftBinding? binding;
}

bool _knownAdmissionRejection(Object error) =>
    error is StudioFailure &&
    switch (error.code) {
      StudioFailureCode.invalidArgument ||
      StudioFailureCode.notFound ||
      StudioFailureCode.busy ||
      StudioFailureCode.conflict ||
      StudioFailureCode.staleRevision ||
      StudioFailureCode.permissionDenied ||
      StudioFailureCode.overloaded => true,
      _ => false,
    };

final class _FrozenAttachments {
  const _FrozenAttachments(this.draftId, this.ids);
  final String draftId;
  final List<String> ids;
}

bool _sameAttachmentIds(
  List<AttachmentDraftView> left,
  List<AttachmentDraftView> right,
) {
  if (left.length != right.length) return false;
  for (var index = 0; index < left.length; index += 1) {
    if (left[index].id != right[index].id) return false;
  }
  return true;
}
