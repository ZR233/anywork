import 'dart:math';
import 'dart:typed_data';

import 'attachment_models.dart';
import 'collection_equality.dart';
import 'thread_directory_models.dart';
import 'settings_models.dart';
import 'studio_enums.dart';

class SubmitPromptReceipt {
  const SubmitPromptReceipt({
    required this.threadId,
    required this.inputId,
    required this.cursor,
  });

  final String threadId;
  final String inputId;
  final int cursor;
}

/// A target-scoped diagnostic that remains observable even after the target
/// composer or workspace has been removed from canonical state.
class ComposerTargetDiagnostic {
  ComposerTargetDiagnostic({
    required this.projectId,
    required this.threadId,
    required this.message,
    List<String> cleanupFailureDraftIds = const [],
  }) : cleanupFailureDraftIds = List.unmodifiable(cleanupFailureDraftIds);

  final String projectId;
  final String? threadId;
  final String message;
  final List<String> cleanupFailureDraftIds;

  String get targetKey => attachmentTargetKey(projectId, threadId);

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is ComposerTargetDiagnostic &&
            projectId == other.projectId &&
            threadId == other.threadId &&
            message == other.message &&
            listEquals(cleanupFailureDraftIds, other.cleanupFailureDraftIds);
  }

  @override
  int get hashCode => Object.hash(
    projectId,
    threadId,
    message,
    Object.hashAll(cleanupFailureDraftIds),
  );
}

String attachmentTargetKey(String projectId, String? threadId) =>
    '$projectId\u0000${threadId ?? '<new>'}';

class StartNewThreadResult {
  const StartNewThreadResult({required this.thread, required this.receipt});

  final StudioThread thread;
  final SubmitPromptReceipt receipt;
}

class ArchiveThreadResult {
  const ArchiveThreadResult({
    required this.archivedRootId,
    required this.removedThreadIds,
    this.nextRoot,
  });

  final String archivedRootId;
  final List<String> removedThreadIds;
  final StudioThread? nextRoot;
}

// An identity belongs to one immutable submission; unchanged failed drafts reuse it.
String newPromptInputId() {
  final random = Random.secure();
  return 'input-${List.generate(16, (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0')).join()}';
}

sealed class ComposerThreadState {
  const ComposerThreadState();
  const factory ComposerThreadState.idle({
    String draft,
    List<AttachmentDraftView> attachments,
    int submissionRevision,
    int attachmentGeneration,
    List<String> cleanupFailureDraftIds,
  }) = IdleComposerThreadState;
  const factory ComposerThreadState.failure({
    required String error,
    String draft,
    List<AttachmentDraftView> attachments,
    int submissionRevision,
    int attachmentGeneration,
    String? inputId,
    List<String> cleanupFailureDraftIds,
  }) = FailedComposerThreadState;

  String get draft;
  List<AttachmentDraftView> get attachments;
  int get submissionRevision;
  int get attachmentGeneration;
  List<String> get cleanupFailureDraftIds;
  String? get inputId => switch (this) {
    SubmittingComposerThreadState(:final inputId) => inputId,
    FailedComposerThreadState(:final inputId) => inputId,
    IdleComposerThreadState() => null,
  };
  String? get error => switch (this) {
    FailedComposerThreadState(:final error, :final cleanupFailureDraftIds) =>
      _composerError(error, cleanupFailureDraftIds),
    IdleComposerThreadState(:final cleanupFailureDraftIds) =>
      _cleanupFailureMessage(cleanupFailureDraftIds),
    SubmittingComposerThreadState(:final cleanupFailureDraftIds) =>
      _cleanupFailureMessage(cleanupFailureDraftIds),
  };
  bool get isSubmissionPending => this is SubmittingComposerThreadState;

  ComposerThreadState updateDraft(String value) {
    if (value == draft) return this;
    if (this case SubmittingComposerThreadState(:final inputId)) {
      return SubmittingComposerThreadState(
        draft: value,
        attachments: attachments,
        submissionRevision: submissionRevision,
        attachmentGeneration: attachmentGeneration,
        inputId: inputId,
        cleanupFailureDraftIds: cleanupFailureDraftIds,
      );
    }
    return IdleComposerThreadState(
      draft: value,
      attachments: attachments,
      submissionRevision: submissionRevision,
      attachmentGeneration: attachmentGeneration,
      cleanupFailureDraftIds: cleanupFailureDraftIds,
    );
  }

  ComposerThreadState updateAttachments(List<AttachmentDraftView> value) {
    if (this case SubmittingComposerThreadState(:final inputId)) {
      return SubmittingComposerThreadState(
        draft: draft,
        attachments: List.unmodifiable(value),
        submissionRevision: submissionRevision,
        attachmentGeneration: attachmentGeneration + 1,
        inputId: inputId,
        cleanupFailureDraftIds: cleanupFailureDraftIds,
      );
    }
    return IdleComposerThreadState(
      draft: draft,
      attachments: List.unmodifiable(value),
      submissionRevision: submissionRevision,
      attachmentGeneration: attachmentGeneration + 1,
      cleanupFailureDraftIds: cleanupFailureDraftIds,
    );
  }

  /// Remove one durable draft from the current canonical composer. The
  /// collection generation advances so previews that captured the old
  /// collection must revalidate before writing; the controller reschedules
  /// still-present drafts against that newer generation.
  ComposerThreadState removeAttachment(String draftId) {
    if (!attachments.any((attachment) => attachment.id == draftId)) {
      return this;
    }
    final next = <AttachmentDraftView>[
      for (final attachment in attachments)
        if (attachment.id != draftId) attachment,
    ];
    if (this case SubmittingComposerThreadState()) {
      return SubmittingComposerThreadState(
        draft: draft,
        attachments: List.unmodifiable(next),
        submissionRevision: submissionRevision,
        attachmentGeneration: attachmentGeneration + 1,
        inputId: inputId!,
        cleanupFailureDraftIds: cleanupFailureDraftIds,
      );
    }
    return updateAttachments(next);
  }

  /// Replace one admitted draft's preview without starting another attachment
  /// generation. All previews from one admission batch can therefore finish
  /// independently while retaining the same race guard.
  ComposerThreadState updateAttachmentPreview(
    String draftId,
    Uint8List previewBytes,
  ) {
    final index = attachments.indexWhere(
      (attachment) => attachment.id == draftId,
    );
    if (index < 0 ||
        listEquals(attachments[index].previewBytes, previewBytes)) {
      return this;
    }
    final next = <AttachmentDraftView>[...attachments];
    next[index] = next[index].copyWith(previewBytes: previewBytes);
    return _replaceAttachments(next);
  }

  ComposerThreadState _replaceAttachments(List<AttachmentDraftView> value) {
    final List<AttachmentDraftView> next = List.unmodifiable(value);
    return switch (this) {
      IdleComposerThreadState() => IdleComposerThreadState(
        draft: draft,
        attachments: next,
        submissionRevision: submissionRevision,
        attachmentGeneration: attachmentGeneration,
        cleanupFailureDraftIds: cleanupFailureDraftIds,
      ),
      FailedComposerThreadState(:final error) => FailedComposerThreadState(
        error: error,
        draft: draft,
        attachments: next,
        submissionRevision: submissionRevision,
        attachmentGeneration: attachmentGeneration,
        inputId: inputId,
        cleanupFailureDraftIds: cleanupFailureDraftIds,
      ),
      SubmittingComposerThreadState(:final inputId) =>
        SubmittingComposerThreadState(
          draft: draft,
          attachments: next,
          submissionRevision: submissionRevision,
          attachmentGeneration: attachmentGeneration,
          inputId: inputId,
          cleanupFailureDraftIds: cleanupFailureDraftIds,
        ),
    };
  }

  /// Preserve an already admitted batch when a preview fails.
  ComposerThreadState reportAttachmentFailure(Object error) {
    if (isSubmissionPending) return this;
    return FailedComposerThreadState(
      draft: draft,
      attachments: attachments,
      error: error.toString(),
      submissionRevision: submissionRevision,
      attachmentGeneration: attachmentGeneration,
      inputId: inputId,
      cleanupFailureDraftIds: cleanupFailureDraftIds,
    );
  }

  /// Preserve cleanup obligations even while a submission is in flight. A
  /// normal composer failure cannot represent an error on a submitting state,
  /// so the IDs are carried as a dedicated typed diagnostic.
  ComposerThreadState reportAttachmentCleanupFailure(
    Iterable<String> draftIds,
  ) {
    final ids = {...cleanupFailureDraftIds, ...draftIds}.toList()..sort();
    if (ids.isEmpty) return this;
    final message = _cleanupFailureMessage(ids)!;
    return switch (this) {
      IdleComposerThreadState() => IdleComposerThreadState(
        draft: draft,
        attachments: attachments,
        submissionRevision: submissionRevision,
        attachmentGeneration: attachmentGeneration,
        cleanupFailureDraftIds: ids,
      ),
      SubmittingComposerThreadState() => SubmittingComposerThreadState(
        draft: draft,
        attachments: attachments,
        submissionRevision: submissionRevision,
        attachmentGeneration: attachmentGeneration,
        inputId: inputId!,
        cleanupFailureDraftIds: ids,
      ),
      FailedComposerThreadState() => FailedComposerThreadState(
        error: error ?? message,
        draft: draft,
        attachments: attachments,
        submissionRevision: submissionRevision,
        attachmentGeneration: attachmentGeneration,
        inputId: inputId,
        cleanupFailureDraftIds: ids,
      ),
    };
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is ComposerThreadState &&
            runtimeType == other.runtimeType &&
            draft == other.draft &&
            listEquals(attachments, other.attachments) &&
            submissionRevision == other.submissionRevision &&
            attachmentGeneration == other.attachmentGeneration &&
            inputId == other.inputId &&
            error == other.error &&
            listEquals(cleanupFailureDraftIds, other.cleanupFailureDraftIds);
  }

  @override
  int get hashCode => Object.hash(
    runtimeType,
    draft,
    Object.hashAll(attachments),
    submissionRevision,
    attachmentGeneration,
    inputId,
    error,
    Object.hashAll(cleanupFailureDraftIds),
  );

  ComposerThreadState reportFailure(Object error) {
    if (isSubmissionPending) return this;
    return FailedComposerThreadState(
      draft: draft,
      attachments: attachments,
      error: error.toString(),
      submissionRevision: submissionRevision,
      attachmentGeneration: attachmentGeneration,
      inputId: inputId,
      cleanupFailureDraftIds: cleanupFailureDraftIds,
    );
  }

  ComposerThreadState beginSubmission() {
    if (isSubmissionPending || (draft.trim().isEmpty && attachments.isEmpty)) {
      return this;
    }
    return _startSubmission();
  }

  ComposerThreadState beginCommandSubmission() =>
      isSubmissionPending ? this : _startSubmission();
  ComposerThreadState _startSubmission() => SubmittingComposerThreadState(
    draft: draft,
    attachments: attachments,
    submissionRevision: submissionRevision + 1,
    attachmentGeneration: attachmentGeneration,
    inputId: inputId ?? newPromptInputId(),
    cleanupFailureDraftIds: cleanupFailureDraftIds,
  );

  ComposerThreadState accept(
    SubmitPromptReceipt receipt, {
    required int submissionRevision,
    required String inputId,
  }) {
    if (!_matchesSubmittingRevision(submissionRevision) ||
        receipt.inputId != inputId) {
      return this;
    }
    return IdleComposerThreadState(
      submissionRevision: this.submissionRevision,
      attachmentGeneration: attachmentGeneration,
      cleanupFailureDraftIds: cleanupFailureDraftIds,
    );
  }

  ComposerThreadState fail(Object error, {required int submissionRevision}) {
    if (!_matchesSubmittingRevision(submissionRevision)) return this;
    return FailedComposerThreadState(
      draft: draft,
      attachments: attachments,
      error: error.toString(),
      submissionRevision: this.submissionRevision,
      attachmentGeneration: attachmentGeneration,
      inputId: inputId,
      cleanupFailureDraftIds: cleanupFailureDraftIds,
    );
  }

  bool _matchesSubmittingRevision(int revision) =>
      this is SubmittingComposerThreadState && submissionRevision == revision;
}

String? _cleanupFailureMessage(List<String> draftIds) {
  if (draftIds.isEmpty) return null;
  return 'Attachment cleanup failed for draft IDs: ${draftIds.join(', ')}';
}

String? _composerError(String? error, List<String> cleanupFailureDraftIds) {
  final cleanup = _cleanupFailureMessage(cleanupFailureDraftIds);
  if (cleanup == null || error == cleanup) return error ?? cleanup;
  if (error == null || error.isEmpty) return cleanup;
  return '$cleanup\n$error';
}

final class IdleComposerThreadState extends ComposerThreadState {
  const IdleComposerThreadState({
    this.draft = '',
    this.attachments = const [],
    this.submissionRevision = 0,
    this.attachmentGeneration = 0,
    this.cleanupFailureDraftIds = const [],
  });
  @override
  final String draft;
  @override
  final List<AttachmentDraftView> attachments;
  @override
  final int submissionRevision;
  @override
  final int attachmentGeneration;
  @override
  final List<String> cleanupFailureDraftIds;
}

final class SubmittingComposerThreadState extends ComposerThreadState {
  const SubmittingComposerThreadState({
    required this.draft,
    required this.attachments,
    required this.submissionRevision,
    required this.attachmentGeneration,
    required this.inputId,
    this.cleanupFailureDraftIds = const [],
  });
  @override
  final String draft;
  @override
  final List<AttachmentDraftView> attachments;
  @override
  final int submissionRevision;
  @override
  final int attachmentGeneration;
  @override
  final String inputId;
  @override
  final List<String> cleanupFailureDraftIds;
}

final class FailedComposerThreadState extends ComposerThreadState {
  const FailedComposerThreadState({
    required this.error,
    this.draft = '',
    this.attachments = const [],
    this.submissionRevision = 0,
    this.attachmentGeneration = 0,
    this.inputId,
    this.cleanupFailureDraftIds = const [],
  });
  @override
  final String error;
  @override
  final String draft;
  @override
  final List<AttachmentDraftView> attachments;
  @override
  final int submissionRevision;
  @override
  final int attachmentGeneration;
  @override
  final String? inputId;
  @override
  final List<String> cleanupFailureDraftIds;
}

/// 起始页草稿。相等性按值比较，供 ViewProvider 过滤通知。
class StartSessionDraft {
  const StartSessionDraft({
    this.projects = const {},
    this.modelIntents = const {},
    this.effortIntents = const {},
    this.submitting = false,
    this.revision = 0,
  });

  final Map<String, StartSessionProjectDraft> projects;
  final Map<String, StartSessionModelIntent> modelIntents;
  final Map<String, String> effortIntents;
  final bool submitting;
  final int revision;

  StartSessionProjectDraft forProject(String? projectId) {
    if (projectId == null) return const StartSessionProjectDraft();
    return projects[projectId] ?? const StartSessionProjectDraft();
  }

  StartSessionModelIntent? modelIntentFor(ThreadModeId mode) =>
      modelIntents[mode.id];

  String? effortIntentFor(ThreadModeId mode) {
    final effort = effortIntents[mode.id];
    if (effort == null || effort.isEmpty) return null;
    return effort;
  }

  StartSessionDraft copyWith({
    Map<String, StartSessionProjectDraft>? projects,
    Map<String, StartSessionModelIntent>? modelIntents,
    Map<String, String>? effortIntents,
    bool? submitting,
    int? revision,
  }) {
    return StartSessionDraft(
      projects: projects ?? this.projects,
      modelIntents: modelIntents ?? this.modelIntents,
      effortIntents: effortIntents ?? this.effortIntents,
      submitting: submitting ?? this.submitting,
      revision: revision ?? this.revision,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is StartSessionDraft &&
          submitting == other.submitting &&
          revision == other.revision &&
          _mapEquals(projects, other.projects) &&
          _mapEquals(modelIntents, other.modelIntents) &&
          _mapEquals(effortIntents, other.effortIntents);

  @override
  int get hashCode => Object.hash(
    submitting,
    revision,
    _mapHash(projects),
    _mapHash(modelIntents),
    _mapHash(effortIntents),
  );
}

class StartSessionProjectDraft {
  const StartSessionProjectDraft({
    this.text = '',
    this.mode = ThreadModeId.simple,
    this.workspaceMode = ThreadWorkspaceMode.local,
  });

  final String text;
  final ThreadModeId mode;
  final ThreadWorkspaceMode workspaceMode;

  StartSessionProjectDraft copyWith({
    String? text,
    ThreadModeId? mode,
    ThreadWorkspaceMode? workspaceMode,
  }) {
    return StartSessionProjectDraft(
      text: text ?? this.text,
      mode: mode ?? this.mode,
      workspaceMode: workspaceMode ?? this.workspaceMode,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is StartSessionProjectDraft &&
          text == other.text &&
          mode == other.mode &&
          workspaceMode == other.workspaceMode;

  @override
  int get hashCode => Object.hash(text, mode, workspaceMode);
}

class StartSessionModelIntent {
  const StartSessionModelIntent({
    required this.accountId,
    required this.modelId,
  });

  final String accountId;
  final String modelId;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is StartSessionModelIntent &&
          accountId == other.accountId &&
          modelId == other.modelId;

  @override
  int get hashCode => Object.hash(accountId, modelId);
}

/// 显示规则：显式 intent 优先，否则使用命令 lane 已组合的 `pending.target ?? canonical`。
ModeModelRouteView? overlayStartSessionRoute({
  required ThreadModeId mode,
  required ModeModelRouteView? laneRoute,
  StartSessionModelIntent? modelIntent,
  String? effortIntent,
}) {
  final explicitEffort = effortIntent != null && effortIntent.isNotEmpty
      ? effortIntent
      : null;
  if (modelIntent == null && explicitEffort == null) return laneRoute;
  final accountId = modelIntent?.accountId ?? laneRoute?.accountId;
  final modelId = modelIntent?.modelId ?? laneRoute?.modelId;
  if (accountId == null ||
      modelId == null ||
      accountId.isEmpty ||
      modelId.isEmpty) {
    return laneRoute;
  }
  return ModeModelRouteView(
    modeId: mode,
    accountId: accountId,
    modelId: modelId,
    effort:
        explicitEffort ??
        (laneRoute != null &&
                laneRoute.accountId == accountId &&
                laneRoute.modelId == modelId
            ? laneRoute.effort
            : ''),
  );
}

bool _mapEquals<K, V>(Map<K, V> left, Map<K, V> right) {
  if (identical(left, right)) return true;
  if (left.length != right.length) return false;
  for (final entry in left.entries) {
    if (right[entry.key] != entry.value) return false;
  }
  return true;
}

int _mapHash<K, V>(Map<K, V> values) => Object.hashAll(
  (values.entries.toList()..sort(
        (left, right) => left.key.toString().compareTo(right.key.toString()),
      ))
      .map((entry) => Object.hash(entry.key, entry.value)),
);

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
