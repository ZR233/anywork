import 'dart:async';

import 'package:anywork_client/conversation.dart';
import 'package:anywork_client/resources.dart';
import 'package:anywork_client/workspace.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../app/app_bindings.dart';
import '../state/conversation_view_state.dart';
import '../state/editor_keys.dart';
import 'session_facet_observer.dart';

part 'conversation_view_model.g.dart';

@riverpod
class ConversationViewModel extends _$ConversationViewModel {
  late ThreadMetadata _metadata;
  Observation? _metadataObservation;
  late SessionFacetObserver<InteractionIndexReadState> _index;
  late SessionFacetObserver<ThreadExecutionState> _execution;
  final Set<ConversationSession> _initialIndexReads = Set<ConversationSession>.identity();
  final Set<InteractionEditorKey> _dismissed = {};
  final Map<ConversationSession, Future<void>> _loadingIndex = Map<ConversationSession, Future<void>>.identity();
  final Set<InteractionEditorKey> _dirtyEditors = {};
  KeepAliveLink? _editing;
  int _indexBinding = 0;
  late ComposerKey composerTarget;

  @override
  FutureOr<ConversationViewState> build(String threadId) {
    composerTarget = ComposerKey.thread(threadId: threadId);
    final repository = ref.read(conversationRepositoryProvider);
    _metadata = ref.read(workspaceRepositoryProvider).thread(threadId);
    final metadata = _metadata.state.watchLatest((value) {
      if (ref.mounted && state.hasValue) state = AsyncData(state.requireValue.copyWith(metadata: value));
    });
    _metadataObservation = metadata.observation;
    _index = SessionFacetObserver<InteractionIndexReadState>(repository: repository,
      threadId: threadId, source: (session) => session.interactions, onValue: _indexChanged);
    _execution = SessionFacetObserver<ThreadExecutionState>(repository: repository,
      threadId: threadId, source: (session) => session.execution, onValue: (value) {
        if (ref.mounted && state.hasValue) state = AsyncData(_mergeIndex(
          state.requireValue.copyWith(execution: value), _index.value));
      });
    _indexBinding = _index.generation;
    ref.onDispose(() {
      _metadataObservation?.cancel(); _metadataObservation = null;
      _index.cancel(); _execution.cancel();
      _metadata.requestClose();
      // D3 retains the query owner and unresolved native cleanup; only this
      // independent metadata borrow is released, never a Conversation Session.
      _metadata.close().ignore();
    });
    scheduleMicrotask(_ensureInitialIndexRead);
    return _mergeIndex(ConversationViewState(threadId: threadId, metadata: metadata.value,
      execution: _execution.value, interactions: _index.value), _index.value);
  }

  void _indexChanged(InteractionIndexReadState value) {
    if (!ref.mounted || !state.hasValue) return;
    final changed = _indexBinding != _index.generation;
    _indexBinding = _index.generation;
    final session = _index.session;
    state = AsyncData(_mergeIndex(state.requireValue.copyWith(
      indexLoading: session != null && _loadingIndex.containsKey(session),
      indexError: changed ? null : state.requireValue.indexError), value));
    _ensureInitialIndexRead();
  }

  ConversationViewState _mergeIndex(ConversationViewState before, InteractionIndexReadState? value) {
    final current = <InteractionEditorKey>{};
    final snapshot = value?.current;
    final execution = before.execution;
    if (snapshot != null && value?.error == null &&
        identical(_execution.session, _index.session) &&
        execution?.sync.phase == FacetSyncPhase.ready &&
        execution?.stamp?.runtimeEpoch == snapshot.origin.runtimeEpoch &&
        execution?.stamp?.incarnation == snapshot.origin.incarnation &&
        execution?.value?.interactions.reference == snapshot.index.reference) {
      for (final item in snapshot.items) {
        if (item.status != InteractionStatus.pending) continue;
        current.add(InteractionEditorKey(threadId: before.threadId,
          incarnation: snapshot.origin.incarnation, interactionId: item.interactionId,
          revision: item.revision));
      }
    }
    // These are UI editor identities, never copied interaction bodies or a
    // second index reducer. Removal/unknown/revision change keeps the old raw
    // editor visible but disabled until the user explicitly closes that editor.
    return before.copyWith(interactions: value, currentEditors: current,
      visibleEditors: [...before.visibleEditors,
        for (final key in current) if (!before.visibleEditors.contains(key) && !_dismissed.contains(key)) key]);
  }

  void _ensureInitialIndexRead() {
    if (!ref.mounted) return;
    final session = _index.session;
    if (session != null && _initialIndexReads.add(session)) loadInteractions().ignore();
  }

  Future<void> loadInteractions() {
    final session = _index.session;
    if (session == null || !ref.mounted || !state.hasValue) return Future<void>.value();
    final running = _loadingIndex[session];
    if (running != null) return running;
    final done = Completer<void>();
    _loadingIndex[session] = done.future;
    state = AsyncData(state.requireValue.copyWith(indexLoading: true, indexError: null));
    Future<void>(() async {
      try { await session.loadInteractionsPage(); }
      on StudioFailure catch (error) {
        if (ref.mounted && identical(_index.session, session)) {
          state = AsyncData(state.requireValue.copyWith(indexError: error));
        }
      } catch (_) {
        if (ref.mounted && identical(_index.session, session)) state = AsyncData(state.requireValue.copyWith(
          indexError: const StudioFailure(code: StudioFailureCode.internal,
            message: 'The interaction index could not be read', retryable: false,
            correlationId: 'conversation-interaction-index-internal')));
      } finally {
        if (ref.mounted && identical(_index.session, session)) {
          state = AsyncData(state.requireValue.copyWith(indexLoading: false));
        }
        if (identical(_loadingIndex[session], done.future)) _loadingIndex.remove(session);
        done.complete();
      }
    });
    return done.future;
  }

  void closeEditor(InteractionEditorKey key) {
    setEditorDirty(key, false);
    _dismissed.add(key);
    final before = state.requireValue;
    state = AsyncData(before.copyWith(visibleEditors: [
      for (final existing in before.visibleEditors) if (existing != key) existing]));
  }

  /// Keep only editor identities across Settings/navigation while their unique
  /// Interaction VM retains raw. No answer, secret, scope or operation is copied.
  void setEditorDirty(InteractionEditorKey key, bool dirty) {
    if (dirty) {
      _dirtyEditors.add(key);
      _editing ??= ref.keepAlive();
    } else {
      _dirtyEditors.remove(key);
      if (_dirtyEditors.isEmpty) { _editing?.close(); _editing = null; }
    }
  }

  void reopenCurrentEditors() {
    _dismissed.removeAll(state.requireValue.currentEditors);
    state = AsyncData(_mergeIndex(state.requireValue, _index.value));
  }

  Future<void> retryMetadata() => _metadata.retry();
}
