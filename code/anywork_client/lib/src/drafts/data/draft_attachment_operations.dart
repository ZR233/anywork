import 'dart:typed_data';

import '../../../models.dart';
import '../../contracts/stamps.dart';
import '../domain/draft_owners.dart';

/// Internal attachment/frozen-submission coordination, never exported to UI.
abstract interface class DraftAttachmentOperations
    implements AttachmentDraftsOwner {
  void sealAdmissions();
  Future<T> runLocked<T>(String targetKey, Future<T> Function() action);
  Future<void> admitThread({
    required String threadId,
    required ComposerDraftBinding binding,
    required List<AttachmentDraftSource> sources,
    required String? projectId,
  });
  Future<void> removeThreadDraft({
    required String threadId,
    required String draftId,
    required ComposerDraftBinding binding,
    required String? projectId,
  });
  Future<void> addThreadClipboard({
    required String threadId,
    required Uint8List pngBytes,
    required ComposerDraftBinding binding,
    required String? projectId,
  });
  ComposerDraftBinding newThreadBinding(String projectId);
  DraftStamp newThreadStamp(String projectId);
  void retainFrozen({
    required OperationId operationId,
    required ComposerDraftBinding binding,
    required Iterable<String> attachmentIds,
  });
  Future<void> completeFrozen({
    required OperationId operationId,
    required bool accepted,
    required bool clearCurrent,
    required String? projectId,
    required String? threadId,
  });
  Future<void> discard({
    required ComposerDraftBinding binding,
    required String? projectId,
    required String? threadId,
  });
}

/// 附件 admission 的读写绑定。调用方持有草稿，本控制器不复制第二份正文。
class ComposerDraftBinding {
  const ComposerDraftBinding({
    required this.read,
    required this.write,
    required this.mounted,
    required this.draftId,
    required this.generation,
  });

  final ComposerThreadState Function() read;
  final void Function(ComposerThreadState next) write;
  final bool Function() mounted;
  final String draftId;
  final int Function() generation;
}

String attachmentLaneKeyForThread(String threadId) => 'thread:$threadId';

String attachmentLaneKeyForNewThread(String projectId) => 'new:$projectId';
