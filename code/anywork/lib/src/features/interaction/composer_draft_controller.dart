import 'dart:async';
import 'dart:typed_data';

import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../data/commands/thread_commands.dart';
import '../../data/stores/recovery_store.dart';
import '../../data/stores/selection_store.dart';
import '../../data/stores/thread_directory_store.dart';
import '../../data/stores/thread_session_store.dart';
import '../../domain/models/studio_models.dart';
import 'attachment_drafts.dart';

part 'composer_draft_controller.g.dart';

/// 会话输入草稿。不进入全局 store；autoDispose，最后一个观察者离开即释放附件。
///
/// 正文、附件引用和编辑状态都在这里。附件 admission 由 [AttachmentDrafts] 执行。
@riverpod
class ComposerDraftController extends _$ComposerDraftController {
  @override
  ComposerThreadState build(String threadId) {
    ref.onDispose(() {
      if (state.isSubmissionPending) return;
      final ids = [for (final attachment in state.attachments) attachment.id];
      if (ids.isEmpty) return;
      final projectId = _projectId();
      unawaited(
        ref
            .read(attachmentDraftsProvider.notifier)
            .releaseOrphans(
              projectId: projectId,
              threadId: threadId,
              draftIds: ids,
            ),
      );
    });
    return const ComposerThreadState.idle();
  }

  void updateDraft(String value) {
    final next = state.updateDraft(value);
    if (identical(next, state)) return;
    state = next;
  }

  void reportFailure(Object error) {
    final next = state.reportFailure(error);
    if (identical(next, state)) return;
    state = next;
  }

  void apply(ComposerThreadState next) {
    if (!ref.mounted || next == state) return;
    state = next;
  }

  Future<void> addLocalAttachments(List<String> paths) {
    if (paths.isEmpty) return Future<void>.value();
    return ref
        .read(attachmentDraftsProvider.notifier)
        .admitThread(
          threadId: threadId,
          binding: _binding,
          projectId: _projectId(),
          sources: [
            for (final path in paths) AttachmentDraftSource.localFile(path),
          ],
        );
  }

  Future<void> addRemoteAttachment(String url) {
    return ref
        .read(attachmentDraftsProvider.notifier)
        .admitThread(
          threadId: threadId,
          binding: _binding,
          projectId: _projectId(),
          sources: [AttachmentDraftSource.remoteUrl(url.trim())],
        );
  }

  Future<void> addClipboardImage(Uint8List pngBytes) {
    return ref
        .read(attachmentDraftsProvider.notifier)
        .addThreadClipboard(
          threadId: threadId,
          pngBytes: pngBytes,
          binding: _binding,
          projectId: _projectId(),
        );
  }

  Future<void> removeAttachment(String draftId) {
    return ref
        .read(attachmentDraftsProvider.notifier)
        .removeThreadDraft(
          threadId: threadId,
          draftId: draftId,
          binding: _binding,
          projectId: _projectId(),
        );
  }

  /// 提交前确认 threadSessionStore 仍有该会话快照。失败只改本地草稿。
  Future<void> submit() async {
    if (state.isSubmissionPending) return;
    if (state.draft.trim().isEmpty && state.attachments.isEmpty) return;
    if (ref.read(selectionStoreProvider).selectedThreadId != threadId) return;
    if (_blocksThread(threadId)) return;
    final session = ref.read(threadSessionStoreProvider(threadId));
    if (!session.hasSnapshot || session.workspace?.thread.id != threadId) {
      reportFailure(
        StateError('Thread submission target is no longer available.'),
      );
      return;
    }
    final observedRevision = session.revision;
    await ref.read(attachmentDraftsProvider.notifier).runLocked(
      attachmentLaneKeyForThread(threadId),
      () async {
        if (!ref.mounted) return;
        final latest = ref.read(threadSessionStoreProvider(threadId));
        if (!latest.hasSnapshot ||
            latest.workspace?.thread.id != threadId ||
            (latest.revision < observedRevision &&
                latest.streamEpoch == session.streamEpoch) ||
            ref.read(selectionStoreProvider).selectedThreadId != threadId) {
          reportFailure(
            StateError('Thread submission target is no longer available.'),
          );
          return;
        }
        if (_blocksThread(threadId) || state.isSubmissionPending) return;
        if (state.draft.trim().isEmpty && state.attachments.isEmpty) return;
        final submitting = state.beginSubmission();
        if (submitting is! SubmittingComposerThreadState) return;
        state = submitting;
        final input = StudioPromptInput(
          inputId: submitting.inputId,
          text: submitting.draft.trim(),
          attachmentDraftIds: [
            for (final attachment in submitting.attachments) attachment.id,
          ],
        );
        try {
          await ref
              .read(threadCommandsProvider.notifier)
              .submitComposer(threadId, input);
          if (!ref.mounted) return;
          if (state.inputId != submitting.inputId ||
              state.submissionRevision != submitting.submissionRevision) {
            return;
          }
          state = ComposerThreadState.idle(
            submissionRevision: submitting.submissionRevision,
            attachmentGeneration: submitting.attachmentGeneration,
            cleanupFailureDraftIds: submitting.cleanupFailureDraftIds,
          );
        } catch (error) {
          if (!ref.mounted) return;
          state = state.fail(
            error,
            submissionRevision: submitting.submissionRevision,
          );
        }
      },
    );
  }

  ComposerDraftBinding get _binding => ComposerDraftBinding(
    read: () => state,
    write: apply,
    mounted: () => ref.mounted,
  );

  String? _projectId() {
    final session = ref.read(threadSessionStoreProvider(threadId));
    final fromSession = session.workspace?.thread.projectId;
    if (fromSession != null && fromSession.isNotEmpty) return fromSession;
    for (final thread
        in ref.read(threadDirectoryStoreProvider).window.threads) {
      if (thread.id == threadId && thread.projectId.isNotEmpty) {
        return thread.projectId;
      }
    }
    final selection = ref.read(selectionStoreProvider);
    if (selection.selectedThreadId == threadId) {
      return selection.selectedProjectId;
    }
    return null;
  }

  bool _blocksThread(String id) {
    final issues = ref.read(recoveryStoreProvider).value?.values ?? const [];
    return issues.any(
      (issue) =>
          issue.blocksAccess &&
          issue.scope == RecoveryIssueScope.thread &&
          issue.threadId == id,
    );
  }
}
