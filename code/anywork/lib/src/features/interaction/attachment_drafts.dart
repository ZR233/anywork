import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../data/commands/command_lane.dart';
import '../../data/commands/settings_commands.dart';
import '../../data/commands/thread_commands.dart';
import '../../data/frb/studio_api.dart';
import '../../data/repositories/studio_api_provider.dart';
import '../../data/stores/domain_sync.dart';
import '../../data/stores/project_store.dart';
import '../../data/stores/recovery_store.dart';
import '../../data/stores/selection_store.dart';
import '../../data/stores/settings_store.dart';
import '../../data/stores/thread_directory_store.dart';
import '../../data/stores/thread_session_store.dart';
import '../../domain/models/studio_models.dart';
import '../../platform/clipboard_image_reader.dart';

part 'attachment_drafts.g.dart';

/// 附件 admission 的读写绑定。调用方持有草稿，本控制器不复制第二份正文。
class ComposerDraftBinding {
  const ComposerDraftBinding({
    required this.read,
    required this.write,
    required this.mounted,
  });

  final ComposerThreadState Function() read;
  final void Function(ComposerThreadState next) write;
  final bool Function() mounted;
}

String attachmentLaneKeyForThread(String threadId) => 'thread:$threadId';

String attachmentLaneKeyForNewThread(String projectId) => 'new:$projectId';

/// 附件草稿的 admission / preview / removal。
///
/// 两阶段：先发布稳定 metadata，再按 draft id 异步补 preview。预览失败保留已准入
/// 附件并写入 typed composer failure。不再使用 lifecycle token 或 barrier；同一目标
/// 的写入由 [CommandLane] 串行，提交前由调用方按 threadSessionStore 校验目标仍在。
/// 失败只记录诊断，不回滚 canonical。
@Riverpod(keepAlive: true)
class AttachmentDrafts extends _$AttachmentDrafts {
  final Map<String, CommandLane> _lanes = {};
  final Set<String> _newThreadSubmitInFlight = {};

  @override
  AttachmentDraftBoard build() => const AttachmentDraftBoard();

  Future<T> runLocked<T>(String targetKey, Future<T> Function() action) {
    return _lane(targetKey).enqueue(action);
  }

  Future<void> admitThread({
    required String threadId,
    required ComposerDraftBinding binding,
    required List<AttachmentDraftSource> sources,
    required String? projectId,
  }) {
    return _admit(
      targetKey: attachmentLaneKeyForThread(threadId),
      context: AttachmentAdmissionContext.existingThread(threadId),
      sources: sources,
      binding: binding,
      projectId: projectId,
      threadId: threadId,
      targetCurrent: () => _threadTargetCurrent(threadId),
    );
  }

  Future<void> removeThreadDraft({
    required String threadId,
    required String draftId,
    required ComposerDraftBinding binding,
    required String? projectId,
  }) {
    return _remove(
      targetKey: attachmentLaneKeyForThread(threadId),
      draftId: draftId,
      binding: binding,
      projectId: projectId,
      threadId: threadId,
    );
  }

  Future<void> addThreadClipboard({
    required String threadId,
    required Uint8List pngBytes,
    required ComposerDraftBinding binding,
    required String? projectId,
  }) {
    return _addClipboard(
      targetKey: attachmentLaneKeyForThread(threadId),
      pngBytes: pngBytes,
      context: AttachmentAdmissionContext.existingThread(threadId),
      binding: binding,
      projectId: projectId,
      threadId: threadId,
      targetCurrent: () => _threadTargetCurrent(threadId),
    );
  }

  Future<void> releaseOrphans({
    required String? projectId,
    required String? threadId,
    required List<String> draftIds,
  }) async {
    if (draftIds.isEmpty) return;
    final key = threadId == null
        ? attachmentLaneKeyForNewThread(projectId ?? '')
        : attachmentLaneKeyForThread(threadId);
    await _lane(key).enqueue(() async {
      await _cleanupOrphans(draftIds, projectId: projectId, threadId: threadId);
    });
  }

  /// 起始页 route 作用域控制器销毁后释放未提交的新会话附件。
  ///
  /// 由 StartSessionController 的 onDispose 延迟到 microtask 调用
  /// （Riverpod 3 生命周期回调内不能跨 provider 读写）；提交在途的
  /// 草稿不在释放范围。释放后整个起始页板条目移除（个别释放失败者一并
  /// 移除并留诊断），避免用户返回起始页时看到已被后端删除的幽灵附件。
  Future<void> releaseNewThreadOrphans() async {
    // 整个容器销毁（测试收尾/进程退出）时本板可能先于 microtask 执行被销毁。
    if (!ref.mounted) return;
    final projectIds = state.newThreadDrafts.keys.toList(growable: false);
    for (final projectId in projectIds) {
      final composer = state.newThread(projectId);
      if (composer.isSubmissionPending || composer.attachments.isEmpty) {
        continue;
      }
      await releaseOrphans(
        projectId: projectId,
        threadId: null,
        draftIds: [
          for (final attachment in composer.attachments) attachment.id,
        ],
      );
      if (!ref.mounted) return;
      _clearNewThread(projectId);
    }
  }

  void seedNewThreadIfEmpty(String projectId, ComposerThreadState incoming) {
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
    _putNewThread(projectId, seeded);
  }

  Future<void> admitNewThread({
    required String projectId,
    required ThreadModeId mode,
    required List<AttachmentDraftSource> sources,
  }) {
    return _admit(
      targetKey: attachmentLaneKeyForNewThread(projectId),
      context: AttachmentAdmissionContext.newThread(mode),
      sources: sources,
      binding: _newThreadBinding(projectId),
      projectId: projectId,
      threadId: null,
      targetCurrent: () => _newThreadCurrent(projectId),
    );
  }

  Future<void> removeNewThreadDraft(String projectId, String draftId) {
    return _remove(
      targetKey: attachmentLaneKeyForNewThread(projectId),
      draftId: draftId,
      binding: _newThreadBinding(projectId),
      projectId: projectId,
      threadId: null,
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
    return _addClipboard(
      targetKey: attachmentLaneKeyForNewThread(projectId),
      pngBytes: pngBytes,
      context: AttachmentAdmissionContext.newThread(mode),
      binding: _newThreadBinding(projectId),
      projectId: projectId,
      threadId: null,
      targetCurrent: () => _newThreadCurrent(projectId),
    );
  }

  void reportNewThreadFailure(String projectId, Object error) {
    final binding = _newThreadBinding(projectId);
    if (!binding.mounted()) return;
    final current = binding.read();
    if (current.isSubmissionPending) return;
    binding.write(current.reportFailure(error));
  }

  /// 起始页提交。正文由调用方持有；成功返回 true 且清空附件草稿。
  ///
  /// 设置 lane 先排空，避免创建会话读到尚未落地的 mode route。不再使用有超时的
  /// flush。命令返回 null（恢复阻断或空输入）时保留草稿且不报错。
  /// 排空开始前先占住 in-flight 哨兵，避免该窗口内 `isSubmissionPending` 仍为
  /// false 时第二次调用再创建一会话。诊断仍走 [_record]。
  Future<bool> submitNewThread({
    required String projectId,
    required String text,
    required ThreadModeId mode,
    required ThreadWorkspaceMode workspaceMode,
  }) async {
    if (!_newThreadSubmitInFlight.add(projectId)) return false;
    try {
      return await _submitNewThreadAfterGuard(
        projectId: projectId,
        text: text,
        mode: mode,
        workspaceMode: workspaceMode,
      );
    } finally {
      _newThreadSubmitInFlight.remove(projectId);
    }
  }

  Future<bool> _submitNewThreadAfterGuard({
    required String projectId,
    required String text,
    required ThreadModeId mode,
    required ThreadWorkspaceMode workspaceMode,
  }) async {
    final trimmed = text.trim();
    final initial = state.newThread(projectId);
    if ((trimmed.isEmpty && initial.attachments.isEmpty) ||
        initial.isSubmissionPending ||
        !_newThreadCurrent(projectId) ||
        _blocksProject(projectId)) {
      return false;
    }
    await ref
        .read(settingsCommandsProvider.notifier)
        .enqueueSettingsWrite(() async {});
    if (!ref.mounted) return false;
    final routeFailure = _newThreadRouteFailure(mode);
    if (routeFailure != null) {
      reportNewThreadFailure(projectId, StateError(routeFailure));
      return false;
    }
    return _lane(attachmentLaneKeyForNewThread(projectId)).enqueue(() async {
      if (!ref.mounted || !_newThreadCurrent(projectId)) {
        _record(
          projectId: projectId,
          threadId: null,
          message: 'New Thread submission target is no longer available.',
        );
        return false;
      }
      final current = state.newThread(projectId);
      if (current.isSubmissionPending ||
          (trimmed.isEmpty && current.attachments.isEmpty) ||
          _blocksProject(projectId)) {
        return false;
      }
      final submitting = current.beginCommandSubmission();
      final inputId = submitting.inputId;
      if (inputId == null) return false;
      _putNewThread(projectId, submitting);
      final input = StudioPromptInput(
        inputId: inputId,
        text: trimmed,
        attachmentDraftIds: [
          for (final attachment in submitting.attachments) attachment.id,
        ],
      );
      try {
        final result = await ref
            .read(threadCommandsProvider.notifier)
            .submitNewThread(
              projectId: projectId,
              input: input,
              mode: mode,
              workspaceMode: workspaceMode.id,
            );
        if (!ref.mounted) return false;
        if (result == null) {
          _revertNewThreadSubmission(projectId, submitting);
          return false;
        }
        if (result.thread.projectId != projectId ||
            result.receipt.threadId != result.thread.id ||
            result.receipt.inputId != inputId) {
          _failNewThread(
            projectId,
            submitting,
            StateError('New Thread submission receipt did not match.'),
          );
          return false;
        }
        _clearNewThread(projectId);
        return true;
      } catch (error) {
        if (ref.mounted) _failNewThread(projectId, submitting, error);
        return false;
      }
    });
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
    if (sources.isEmpty) return;
    final admitted = await _lane(targetKey).enqueue(() async {
      if (!binding.mounted() || !targetCurrent()) return null;
      final initial = binding.read();
      if (initial.isSubmissionPending) return null;
      final submissionRevision = initial.submissionRevision;
      final generation = initial.attachmentGeneration;
      final List<AttachmentDraftView> drafts;
      try {
        drafts = await _api.admitAttachmentDrafts(context, sources);
      } catch (error) {
        if (!ref.mounted || !binding.mounted() || !targetCurrent()) return null;
        final current = binding.read();
        if (current.isSubmissionPending ||
            current.submissionRevision != submissionRevision ||
            current.attachmentGeneration != generation) {
          return null;
        }
        binding.write(current.reportFailure(error));
        return null;
      }
      if (drafts.isEmpty) return null;
      if (!ref.mounted || !binding.mounted() || !targetCurrent()) {
        await _cleanupOrphans(
          drafts.map((draft) => draft.id),
          projectId: projectId,
          threadId: threadId,
        );
        return null;
      }
      final current = binding.read();
      if (current.isSubmissionPending ||
          current.submissionRevision != submissionRevision ||
          current.attachmentGeneration != generation) {
        await _cleanupOrphans(
          drafts.map((draft) => draft.id),
          projectId: projectId,
          threadId: threadId,
        );
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
  /// attachment generation 当写屏障；id 已不在或正在提交则丢弃这次字节。
  Future<void> _readPreview(
    AttachmentDraftView draft, {
    required ComposerDraftBinding binding,
    required String? projectId,
    required String? threadId,
    required String targetKey,
    required bool Function() targetCurrent,
  }) async {
    final Uint8List bytes;
    try {
      bytes = await _api.readAttachmentDraft(draft.id);
    } catch (error) {
      await _lane(targetKey).enqueue(() async {
        if (!ref.mounted || !binding.mounted() || !targetCurrent()) {
          await _cleanupOrphans(
            [draft.id],
            projectId: projectId,
            threadId: threadId,
          );
          return;
        }
        final current = binding.read();
        if (current.isSubmissionPending) return;
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
      if (!ref.mounted || !binding.mounted() || !targetCurrent()) {
        await _cleanupOrphans(
          [draft.id],
          projectId: projectId,
          threadId: threadId,
        );
        return;
      }
      final current = binding.read();
      if (current.isSubmissionPending) return;
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
    if (current.isSubmissionPending) return;
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
      try {
        if (!await _api.removeAttachmentDraft(draftId)) {
          throw StateError('Attachment draft is unavailable.');
        }
      } catch (error) {
        if (binding.mounted()) {
          final current = binding.read();
          if (current.attachments.any(
            (attachment) => attachment.id == draftId,
          )) {
            binding.write(current.reportAttachmentCleanupFailure([draftId]));
          }
        }
        _record(
          projectId: projectId,
          threadId: threadId,
          message: 'Attachment removal failed for draft ID: $draftId: $error',
          cleanupFailureDraftIds: [draftId],
        );
        return;
      }
      if (!binding.mounted()) return;
      final current = binding.read();
      final updated = current.removeAttachment(draftId);
      if (!identical(updated, current)) binding.write(updated);
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
    if (pngBytes.isEmpty) {
      await _lane(targetKey).enqueue(() async {
        if (!binding.mounted() || !targetCurrent()) return;
        final current = binding.read();
        if (current.isSubmissionPending) return;
        binding.write(
          current.reportFailure(StateError('Clipboard image is empty.')),
        );
      });
      return;
    }
    StagedClipboardImage? staged;
    try {
      staged = await ref.read(clipboardImageStagerProvider).stage(pngBytes);
      await _admit(
        targetKey: targetKey,
        context: context,
        sources: [AttachmentDraftSource.localFile(staged.path)],
        binding: binding,
        projectId: projectId,
        threadId: threadId,
        targetCurrent: targetCurrent,
      );
    } catch (error) {
      await _lane(targetKey).enqueue(() async {
        if (!binding.mounted() || !targetCurrent()) return;
        final current = binding.read();
        if (current.isSubmissionPending) return;
        binding.write(current.reportFailure(error));
      });
    } finally {
      await staged?.dispose();
    }
  }

  Future<void> _cleanupOrphans(
    Iterable<String> draftIds, {
    required String? projectId,
    required String? threadId,
  }) async {
    final failures = <String, Object>{};
    for (final draftId in draftIds) {
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
      debugPrint(
        'attachment_cleanup_failed projectId=$projectId threadId=$threadId '
        'draftId=${entry.key} error=${entry.value}',
      );
    }
  }

  void _record({
    required String? projectId,
    required String? threadId,
    required String message,
    Iterable<String> cleanupFailureDraftIds = const [],
  }) {
    if (!ref.mounted || projectId == null) return;
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
      mounted: () => ref.mounted,
    );
  }

  void _putNewThread(String projectId, ComposerThreadState next) {
    if (!ref.mounted) return;
    if (state.newThread(projectId) == next &&
        state.newThreadDrafts.containsKey(projectId)) {
      return;
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

  void _revertNewThreadSubmission(
    String projectId,
    ComposerThreadState submitting,
  ) {
    _putNewThread(
      projectId,
      ComposerThreadState.idle(
        attachments: submitting.attachments,
        submissionRevision: submitting.submissionRevision,
        attachmentGeneration: submitting.attachmentGeneration,
        cleanupFailureDraftIds: submitting.cleanupFailureDraftIds,
      ),
    );
  }

  void _failNewThread(
    String projectId,
    ComposerThreadState submitting,
    Object error,
  ) {
    final current = state.newThread(projectId);
    _putNewThread(
      projectId,
      current.fail(error, submissionRevision: submitting.submissionRevision),
    );
  }

  bool _threadTargetCurrent(String threadId) {
    final thread = _lookupThread(threadId);
    if (thread == null) {
      return ref.read(threadSessionStoreProvider(threadId)).hasSnapshot;
    }
    // faulted 可能只是模型或工具输入驱动失败，后端续接会重新启用驱动并创建新的
    // 执行轮次；只有类型化存储事实明确阻塞准入时，才沿用存储恢复闸门。
    return switch (thread.status) {
      ThreadStatusView.closing || ThreadStatusView.closed => false,
      ThreadStatusView.faulted =>
        ref
                .read(threadSessionStoreProvider(threadId))
                .storage
                ?.blocksContinuation !=
            true,
      _ => true,
    };
  }

  StudioThread? _lookupThread(String threadId) {
    for (final thread
        in ref.read(threadDirectoryStoreProvider).window.threads) {
      if (thread.id == threadId) return thread;
    }
    return ref.read(threadSessionStoreProvider(threadId)).workspace?.thread;
  }

  bool _newThreadCurrent(String projectId) {
    final selection = ref.read(selectionStoreProvider);
    if (selection.selectedProjectId != projectId ||
        selection.selectedThreadId != null) {
      return false;
    }
    final projects =
        ref.read(projectStoreProvider).projects?.values ?? const [];
    return projects.any((project) => project.id == projectId);
  }

  bool _blocksProject(String projectId) {
    final issues = ref.read(recoveryStoreProvider).value?.values ?? const [];
    return issues.any(
      (issue) =>
          issue.blocksAccess &&
          issue.scope == RecoveryIssueScope.project &&
          issue.projectId == projectId,
    );
  }

  String? _newThreadRouteFailure(ThreadModeId mode) {
    final commands = ref.read(settingsStoreProvider).commands;
    for (final key in [
      'new-thread-route:model:${mode.id}',
      'new-thread-route:effort:${mode.id}',
    ]) {
      final status = commands[key];
      if (status?.phase == CommandPhase.failed) {
        return status?.error?.message ?? 'Settings mutation failed.';
      }
    }
    return null;
  }

  CommandLane _lane(String targetKey) =>
      _lanes.putIfAbsent(targetKey, CommandLane.new);

  StudioBridgeDataSource get _api => ref.read(studioBridgeDataSourceProvider);
}

class AttachmentDraftBoard {
  const AttachmentDraftBoard({
    this.diagnostics = const {},
    this.newThreadDrafts = const {},
  });

  final Map<String, ComposerTargetDiagnostic> diagnostics;
  final Map<String, ComposerThreadState> newThreadDrafts;

  ComposerThreadState newThread(String projectId) =>
      newThreadDrafts[projectId] ?? const ComposerThreadState.idle();

  List<ComposerTargetDiagnostic> forProject(String? projectId) {
    if (projectId == null) return const [];
    return [
      for (final diagnostic in diagnostics.values)
        if (diagnostic.projectId == projectId) diagnostic,
    ];
  }

  AttachmentDraftBoard copyWith({
    Map<String, ComposerTargetDiagnostic>? diagnostics,
    Map<String, ComposerThreadState>? newThreadDrafts,
  }) {
    return AttachmentDraftBoard(
      diagnostics: diagnostics ?? this.diagnostics,
      newThreadDrafts: newThreadDrafts ?? this.newThreadDrafts,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AttachmentDraftBoard &&
          _diagnosticsEqual(diagnostics, other.diagnostics) &&
          _draftsEqual(newThreadDrafts, other.newThreadDrafts);

  @override
  int get hashCode => Object.hash(
    Object.hashAll(
      diagnostics.entries.map((entry) => Object.hash(entry.key, entry.value)),
    ),
    Object.hashAll(
      newThreadDrafts.entries.map(
        (entry) => Object.hash(entry.key, entry.value),
      ),
    ),
  );
}

bool _diagnosticsEqual(
  Map<String, ComposerTargetDiagnostic> left,
  Map<String, ComposerTargetDiagnostic> right,
) {
  if (identical(left, right)) return true;
  if (left.length != right.length) return false;
  for (final entry in left.entries) {
    if (right[entry.key] != entry.value) return false;
  }
  return true;
}

bool _draftsEqual(
  Map<String, ComposerThreadState> left,
  Map<String, ComposerThreadState> right,
) {
  if (identical(left, right)) return true;
  if (left.length != right.length) return false;
  for (final entry in left.entries) {
    if (right[entry.key] != entry.value) return false;
  }
  return true;
}
