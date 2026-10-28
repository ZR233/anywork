import 'dart:async';
import 'dart:typed_data';

import 'package:anywork_client/conversation.dart';
import 'package:anywork_client/drafts.dart';
import 'package:anywork_client/modes.dart';
import 'package:anywork_client/operations.dart';
import 'package:anywork_client/resources.dart';
import 'package:anywork_client/workspace.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../app/app_bindings.dart';
import '../state/composer_view_state.dart';
import '../state/editor_keys.dart';
import 'conversation_view_model.dart';

part 'composer_view_model.g.dart';

@riverpod
class ComposerViewModel extends _$ComposerViewModel {
  late DraftsRepository _drafts;
  ComposerDraft? _draft;
  StartDraft? _start;
  ConversationSession? _session;
  Object? _lifetime;
  final List<Observation> _observations = [];
  Observation? _operationObservation;
  int _platformReads = 0;
  int _platformAttempt = 0;
  bool _commandBoundary = false;

  @override
  FutureOr<ComposerViewState> build(ComposerKey target) {
    final lifetime = Object();
    _lifetime = lifetime;
    _platformReads = 0;
    _platformAttempt = 0;
    _drafts = ref.read(draftsRepositoryProvider);
    _draft = null;
    _start = null;
    _session = null;
    ref.onDispose(() {
      if (identical(_lifetime, lifetime)) _lifetime = null;
      for (final observation in _observations) {
        observation.cancel();
      }
      _observations.clear();
      _operationObservation?.cancel();
      _operationObservation = null;
      // No discard/closeSession/cancel-operation on observation disposal.
    });
    switch (target) {
      case ThreadComposerKey(:final threadId):
        final conversations = ref.read(conversationRepositoryProvider);
        var session = conversations.existingSession(threadId);
        final active = conversations.active.watchLatest((_) {
          if (ref.mounted &&
              !identical(conversations.existingSession(threadId), session)) {
            ref.invalidateSelf();
          }
        });
        _observations.add(active.observation);
        // Read after registration, without opening a Session or copying Thread
        // existence into a second store. Missing observation owns no draft.
        session = conversations.existingSession(threadId);
        if (session == null) {
          throw const StudioFailure(
            code: StudioFailureCode.unavailable,
            message: 'The conversation Session is not available',
            retryable: true,
            correlationId: 'composer-session-unavailable',
          );
        }
        _session = session;
        final draft = _draft = _drafts.composer(threadId);
        final watch = draft.state.watchLatest((value) {
          if (ref.mounted && state.hasValue) {
            state = AsyncData(state.requireValue.copyWith(draft: value));
          }
        });
        _observations.add(watch.observation);
        return ComposerViewState(key: target, draft: watch.value);
      case StartComposerKey(:final projectId):
        final draft = _start = _drafts.start(projectId);
        final watch = draft.state.watchLatest((value) {
          if (ref.mounted && state.hasValue) {
            state = AsyncData(state.requireValue.copyWith(startDraft: value));
          }
        });
        _observations.add(watch.observation);
        final preferences = _drafts.startRoutes.watchLatest((value) {
          if (ref.mounted && state.hasValue) {
            state = AsyncData(state.requireValue.copyWith(preferences: value));
          }
        });
        _observations.add(preferences.observation);
        return ComposerViewState(
          key: target,
          startDraft: watch.value,
          preferences: preferences.value,
        );
    }
  }

  void setText(String raw) {
    if (state.requireValue.closing) return;
    _draft?.setText(raw);
    _start?.setText(raw);
  }

  void setMode(ThreadModeId mode) {
    if (!state.requireValue.closing) _start?.setMode(mode);
  }

  void setWorkspaceMode(ThreadWorkspaceMode mode) {
    if (!state.requireValue.closing) _start?.setWorkspaceMode(mode);
  }

  void setStartModel(String accountId, String modelId) {
    final mode = state.requireValue.startDraft?.mode;
    if (mode == null || state.requireValue.closing) return;
    _drafts.setStartModel(mode, accountId, modelId);
  }

  void setStartEffort(String effort) {
    final mode = state.requireValue.startDraft?.mode;
    if (mode == null || state.requireValue.closing) return;
    _drafts.setStartEffort(mode, effort);
  }

  void setUrl(String raw) =>
      state = AsyncData(state.requireValue.copyWith(urlRaw: raw));

  /// Platform waits belong to this concrete VM lifetime and logical draft, not
  /// to a replacement notifier/draft that happens to use the same family key.
  bool Function() captureAttachmentTarget() {
    final lifetime = _lifetime;
    final draft = _draft;
    final start = _start;
    final draftId =
        draft?.state.value.stamp.draftId ?? start?.state.value.stamp.draftId;
    return () =>
        ref.mounted &&
        lifetime != null &&
        identical(_lifetime, lifetime) &&
        identical(_draft, draft) &&
        identical(_start, start) &&
        draftId != null &&
        (draft?.state.value.stamp.draftId ??
                start?.state.value.stamp.draftId) ==
            draftId;
  }

  Future<void> addLocalFiles(List<String> paths) => _perform(
    () =>
        _draft?.addLocalFiles(List.of(paths)) ??
        _start!.addLocalFiles(List.of(paths)),
  );
  Future<void> addRemoteUrl() {
    final raw = state.requireValue.urlRaw;
    return _perform(
      () => _draft?.addRemoteUrl(raw) ?? _start!.addRemoteUrl(raw),
    );
  }

  Future<void> addClipboardImage(Uint8List pngBytes) => _perform(
    () =>
        _draft?.addClipboardImage(pngBytes) ??
        _start!.addClipboardImage(pngBytes),
  );
  Future<void> removeAttachment(String id) => _perform(
    () => _draft?.removeAttachment(id) ?? _start!.removeAttachment(id),
  );
  Future<void> discard() =>
      _perform(() => _draft?.discard() ?? _start!.discard());

  /// No await before D1's non-async submit admission/freeze.
  Future<void> send() {
    final view = state.requireValue;
    if (_commandBoundary ||
        view.pending ||
        view.platformPending ||
        view.submission is SubmittingDraft ||
        view.submission is UnknownDraftSubmission) {
      return Future<void>.value();
    }
    if (!view.hasInput || view.closing) {
      state = AsyncData(
        view.copyWith(
          inputIssue: const ValidationIssue(
            code: 'emptyInput',
            path: 'text',
            message: 'Enter a message or add an attachment',
          ),
        ),
      );
      return Future<void>.value();
    }
    final draft = _draft;
    if (draft != null) {
      // Borrow at this intent's synchronous freeze boundary, not VM build time:
      // the repository may have replaced a Session while retaining the same ID.
      final session = _session;
      final repository = ref.read(conversationRepositoryProvider);
      if (session == null ||
          !identical(repository.existingSession(draft.threadId), session)) {
        state = AsyncData(
          view.copyWith(
            error: const StudioFailure(
              code: StudioFailureCode.unavailable,
              message: 'The conversation Session is not available',
              retryable: true,
              correlationId: 'composer-session-unavailable',
            ),
          ),
        );
        return Future<void>.value();
      }
      final prepare = ref.read(prepareConversationPresentationProvider);
      final execution = session.execution.value;
      final configuration = session.configuration.value;
      final action = ref
          .read(conversationViewModelProvider(draft.threadId).notifier)
          .primaryAction(
            hasContent: view.hasInput,
            submissionPending:
                view.platformPending ||
                view.submission is SubmittingDraft ||
                view.submission is UnknownDraftSubmission,
          );
      if (execution.sync.phase != FacetSyncPhase.ready ||
          !session.acceptsUserInput ||
          !action.enterSubmits ||
          execution.value == null ||
          const {
            ThreadStatus.closing,
            ThreadStatus.closed,
            ThreadStatus.faulted,
          }.contains(execution.value?.status)) {
        state = AsyncData(
          view.copyWith(
            error: const StudioFailure(
              code: StudioFailureCode.unavailable,
              message: 'The conversation is not ready to accept input',
              retryable: true,
              correlationId: 'composer-execution-unavailable',
            ),
          ),
        );
        return Future<void>.value();
      }
      return _perform(() {
        // _perform may notify UI observers synchronously. The SDK freeze
        // immediately below must still borrow this exact original source,
        // execution/point and route, not a same-ID replacement Session.
        if (!identical(repository.existingSession(draft.threadId), session) ||
            session.execution.value != execution ||
            session.configuration.value != configuration) {
          throw const StudioFailure(
            code: StudioFailureCode.superseded,
            message: 'The original composer source changed before dispatch',
            retryable: false,
            correlationId: 'composer-source-replaced',
          );
        }
        return draft.submit(preparePresentation: () => prepare(session));
      });
    }
    final start = _start!;
    return _perform(start.submit);
  }

  /// Platform read failures are presentation failures, not fabricated receipts.
  void reportPlatformFailure(StudioFailure failure) {
    if (ref.mounted) {
      state = AsyncData(state.requireValue.copyWith(platformError: failure));
    }
  }

  /// Smart captures this VM before starting a picker/clipboard/drop transfer.
  /// Keep only this observer alive until that platform transfer and D1's
  /// admission finish; navigating never redirects the late files to a new VM.
  Future<R?> withPlatformRead<R>(Future<R> Function() read) async {
    if (state.requireValue.closing) return null;
    final lifetime = _lifetime;
    bool current() => ref.mounted && identical(_lifetime, lifetime);
    final keepAlive = ref.keepAlive();
    final attempt = ++_platformAttempt;
    _platformReads++;
    state = AsyncData(
      state.requireValue.copyWith(platformPending: true, platformError: null),
    );
    try {
      return await read();
    } on StudioFailure catch (failure) {
      if (current() && attempt == _platformAttempt) {
        reportPlatformFailure(failure);
      }
    } catch (_) {
      if (current() && attempt == _platformAttempt) {
        reportPlatformFailure(
          const StudioFailure(
            code: StudioFailureCode.unavailable,
            message: 'The attachment source could not be read',
            retryable: true,
            correlationId: 'composer-platform-read',
          ),
        );
      }
    } finally {
      if (current()) {
        _platformReads--;
        state = AsyncData(
          state.requireValue.copyWith(platformPending: _platformReads != 0),
        );
      }
      keepAlive.close();
    }
    return null;
  }

  Future<void> _perform<T>(OperationTicket<T> Function() command) {
    final view = state.requireValue;
    if (view.closing || _commandBoundary) return Future<void>.value();
    final intent = view.latestIntent + 1;
    _commandBoundary = true;
    try {
      _operationObservation?.cancel();
      _operationObservation = null;
      state = AsyncData(
        state.requireValue.copyWith(
          latestIntent: intent,
          pending: true,
          error: null,
          inputIssue: null,
        ),
      );
      final ticket = command();
      final watch = ticket.state.watchLatest((record) {
        if (_current(intent)) {
          state = AsyncData(state.requireValue.copyWith(operation: record));
        }
      });
      _operationObservation = watch.observation;
      state = AsyncData(state.requireValue.copyWith(operation: watch.value));
      return _settle(ticket, intent);
    } on StudioFailure catch (failure) {
      if (_current(intent)) {
        state = AsyncData(
          state.requireValue.copyWith(pending: false, error: failure),
        );
      }
      return Future<void>.value();
    } finally {
      _commandBoundary = false;
    }
  }

  bool _current(int intent) =>
      ref.mounted &&
      state.hasValue &&
      state.requireValue.latestIntent == intent;

  Future<void> _settle<T>(OperationTicket<T> ticket, int intent) async {
    final result = await ticket.result;
    if (!_current(intent)) return;
    final error = switch (result) {
      RejectedCommandResult<T>(:final error) ||
      UnknownOutcomeCommandResult<T>(:final error) ||
      SyncFailedCommandResult<T>(:final error) ||
      AcknowledgedSyncFailedCommandResult<T>(:final error) => error,
      CommittedCommandResult<T>() || AcknowledgedCommandResult<T>() => null,
    };
    state = AsyncData(
      state.requireValue.copyWith(pending: false, error: error),
    );
    // Draft clearing, frozen attachments and unknown operation retention are D1
    // facts. No success handler or old finally edits the new raw draft here.
  }
}
