import 'dart:typed_data';

import '../domain/draft_owners.dart';
import '../domain/drafts_repository.dart';
import 'drafts_dependencies.dart';
import 'attachment_drafts_impl.dart';
import 'composer_draft_impl.dart';
import 'start_draft_impl.dart';

final class DraftsRepositoryImpl implements DraftsRepository {
  DraftsRepositoryImpl(
    this.dependencies, {
    Future<String?> Function(Uint8List)? clipboardImageStager,
    Future<void> Function(String)? clipboardImageCleanup,
  }) {
    attachments = AttachmentDraftsImpl(
      dependencies,
      clipboardImageStager: clipboardImageStager,
      clipboardImageCleanup: clipboardImageCleanup,
    );
    dependencies.attachments = attachments;
    startDraft = StartSessionDraftImpl(dependencies);
    dependencies.startDraft = startDraft;
  }
  final DraftsDependencies dependencies;
  final Map<String, ComposerDraftOwner> _composers = {};
  Future<void>? _closing;
  @override
  late final AttachmentDraftsImpl attachments;
  @override
  late final StartSessionDraftOwner startDraft;

  @override
  ComposerDraftOwner composer(String threadId) {
    final existing = _composers[threadId];
    if (existing != null) return existing;
    if (dependencies.isClosed) throw StateError('Drafts repository is closed');
    return _composers.putIfAbsent(
      threadId,
      () => ComposerDraftImpl(dependencies, threadId),
    );
  }

  @override
  ComposerDraftOwner? existingComposer(String threadId) => _composers[threadId];
  @override
  List<ComposerDraftOwner> projectComposers(String projectId) =>
      List.unmodifiable([
        for (final owner in _composers.values)
          if ((dependencies.conversations
                      .sessionState(owner.threadId)
                      ?.workspace
                      ?.thread
                      .projectId ??
                  dependencies.findThread(owner.threadId)?.projectId) ==
              projectId)
            owner,
      ]);
  @override
  Future<void> discardProjectDrafts(
    String projectId,
    List<ComposerDraftOwner> owners,
  ) async {
    await Future.wait<void>([
      startDraft.discardProject(projectId),
      for (final owner in owners)
        () async {
          await owner.discard();
          await owner.close();
          if (identical(_composers[owner.threadId], owner))
            _composers.remove(owner.threadId);
        }(),
    ]);
  }

  @override
  Future<void> close() => _closing ??= _close();
  Future<void> _close() async {
    dependencies.isClosed = true;
    attachments.sealAdmissions();
    try {
      await Future.wait<void>([
        startDraft.close(),
        for (final owner in _composers.values) owner.close(),
      ]);
    } finally {
      await attachments.close();
    }
  }

  @override
  Future<void> retryCleanup() => attachments.retryCleanup();
}
