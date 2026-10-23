import 'dart:async';

import 'package:anywork_client/conversation.dart';
import 'package:anywork_client/resources.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../app/app_bindings.dart';
import '../state/todo_view_state.dart';
import 'read_scope_borrow.dart';
import 'read_validation.dart';
import 'session_facet_observer.dart';

part 'todo_view_model.g.dart';

@riverpod
class TodoViewModel extends _$TodoViewModel {
  late SessionFacetObserver<ThreadAuthoringState> _observer;
  ReadScopeBorrow<TodoReadScope>? _borrow;
  int _binding = 0;
  final Map<(int, int), Future<void>> _textWork = {};

  @override
  FutureOr<TodoViewState> build(String threadId) {
    _observer = SessionFacetObserver<ThreadAuthoringState>(
      repository: ref.read(conversationRepositoryProvider), threadId: threadId,
      source: (session) => session.authoring, onValue: _changed);
    _binding = _observer.generation;
    ref.onDispose(() { _observer.cancel(); _borrow?.retire(); });
    return TodoViewState(threadId: threadId, origin: _observer.value?.stamp,
      todo: _observer.value?.value?.todo);
  }

  void _changed(ThreadAuthoringState source) {
    if (!ref.mounted || !state.hasValue) return;
    final before = state.requireValue;
    final todo = source.value?.todo;
    final changed = _binding != _observer.generation || todo != before.todo;
    _binding = _observer.generation;
    if (!changed) return;
    _borrow?.retire(); _borrow = null;
    state = AsyncData(before.copyWith(origin: source.stamp, todo: todo, header: null,
      items: [], texts: {}, nextOffset: null, error: null, loading: false, generation: before.generation + 1));
    if (before.expanded) loadMore();
  }

  void setExpanded(bool expanded) {
    final before = state.requireValue;
    if (!expanded) {
      _borrow?.retire(); _borrow = null;
      state = AsyncData(before.copyWith(expanded: false, generation: before.generation + 1, loading: false));
    } else {
      state = AsyncData(before.copyWith(expanded: true));
      if (_borrow == null) loadMore();
    }
  }
  void toggle() => setExpanded(!state.requireValue.expanded);

  Future<void> loadMore() async {
    final before = state.requireValue;
    final session = _observer.session;
    final origin = before.origin;
    final reference = before.todo?.reference;
    if (!before.expanded || before.loading || session == null || origin == null || reference == null) return;
    if (_borrow != null && before.header != null && before.nextOffset == null) return;
    final generation = before.generation;
    final newScope = _borrow == null;
    final borrow = _borrow ??= ReadScopeBorrow<TodoReadScope>(
      open: () => session.openTodo(reference, origin: origin),
      requestClose: (scope) => scope.requestClose(), close: (scope) => scope.close(),
      retryCleanup: (scope) => scope.retryCleanup());
    bool current() => ref.mounted && identical(_borrow, borrow) && identical(_observer.session, session) &&
        state.requireValue.generation == generation && state.requireValue.todo?.reference == reference;
    state = AsyncData(before.copyWith(loading: true, error: null));
    try {
      final scope = await borrow.open();
      if (!current()) return;
      if (newScope || before.header == null) {
        final header = await scope.header();
        if (!current()) return;
        if (header.scope.runtimeEpoch != origin.runtimeEpoch || header.scope.incarnation != origin.incarnation ||
            header.itemCount != before.todo!.itemCount) throw readProtocol('todo-header');
        final texts = <ReadText>[
          ?header.callId, ?header.agentId, ?header.path, ?header.parentPath, ?header.explanation,
        ];
        state = AsyncData(state.requireValue.copyWith(header: header, items: [],
          texts: registerReadTexts({}, texts), nextOffset: header.itemCount > 0 ? 0 : null));
      }
      if (!current()) return;
      final value = state.requireValue;
      final offset = value.nextOffset;
      if (offset == null) return;
      final page = await scope.items(offset: offset, limit: 32);
      if (!current()) return;
      checkReadPage(expectedScope: value.header!.scope, scope: page.scope,
        requested: offset, offset: page.offset, total: page.total,
        count: page.items.length, next: page.nextOffset, expectedTotal: value.header!.itemCount);
      for (final (position, item) in page.items.indexed) {
        if (item.index != offset + position) throw readProtocol('todo-index');
      }
      state = AsyncData(state.requireValue.copyWith(items: [...value.items, ...page.items],
        nextOffset: page.nextOffset, texts: registerReadTexts(value.texts, page.items.map((item) => item.step))));
    } on StudioFailure catch (error) {
      if (current()) state = AsyncData(state.requireValue.copyWith(error: error));
    } finally {
      if (current()) state = AsyncData(state.requireValue.copyWith(loading: false));
    }
  }

  Future<void> loadText(int fieldId) {
    final identity = (state.requireValue.generation, fieldId);
    final running = _textWork[identity];
    if (running != null) return running;
    final task = _readText(fieldId);
    _textWork[identity] = task;
    task.whenComplete(() {
      if (identical(_textWork[identity], task)) _textWork.remove(identity);
    }).ignore();
    return task;
  }

  Future<void> _readText(int fieldId) async {
    final before = state.requireValue;
    final progress = before.texts[fieldId];
    final borrow = _borrow;
    if (!before.expanded || borrow == null || progress == null || progress.complete) return;
    bool current() => ref.mounted && identical(_borrow, borrow) && state.requireValue.generation == before.generation;
    try {
      final scope = await borrow.open();
      final chunk = await scope.text(fieldId, offset: progress.loadedUtf8Bytes, maxBytes: 65536);
      if (current()) state = AsyncData(state.requireValue.copyWith(texts: {
        ...state.requireValue.texts, fieldId: applyReadChunk(progress, chunk)}));
    } on StudioFailure catch (error) {
      if (current()) state = AsyncData(state.requireValue.copyWith(error: error));
    }
  }
}
