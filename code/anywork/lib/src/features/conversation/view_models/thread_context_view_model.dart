import 'dart:async';

import 'package:anywork_client/conversation.dart';
import 'package:anywork_client/resources.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../app/app_bindings.dart';
import '../state/thread_context_state.dart';
import 'read_scope_borrow.dart';
import 'detail_demand.dart';
import 'read_validation.dart';
import 'session_facet_observer.dart';

part 'thread_context_view_model.g.dart';

@riverpod
class ThreadContextViewModel extends _$ThreadContextViewModel {
  late SessionFacetObserver<ThreadContextState> _context;
  late SessionFacetObserver<ThreadExecutionState> _execution;
  ReadScopeBorrow<ContextReadScope>? _borrow;
  int _binding = 0;
  final Map<(int, int), Future<void>> _texts = {};
  late DetailDemand _detailDemand;
  void Function() beginDetailsDemand() => _detailDemand.begin();

  @override
  FutureOr<ThreadContextViewState> build(String threadId) {
    final repository = ref.read(conversationRepositoryProvider);
    _detailDemand = DetailDemand(setDetailsVisible);
    _context = SessionFacetObserver<ThreadContextState>(
      repository: repository,
      threadId: threadId,
      source: (session) => session.context,
      onValue: _changed,
    );
    _execution = SessionFacetObserver<ThreadExecutionState>(
      repository: repository,
      threadId: threadId,
      source: (session) => session.execution,
      onValue: (value) {
        if (ref.mounted &&
            state.hasValue &&
            value.value?.status != state.requireValue.status) {
          state = AsyncData(
            state.requireValue.copyWith(status: value.value?.status),
          );
        }
      },
    );
    _binding = _context.generation;
    ref.onDispose(() {
      _detailDemand.seal();
      _context.cancel();
      _execution.cancel();
      _borrow?.retire();
    });
    return ThreadContextViewState(
      threadId: threadId,
      source: _context.value,
      status: _execution.value?.value?.status,
    );
  }

  void _changed(ThreadContextState source) {
    if (!ref.mounted || !state.hasValue) return;
    final before = state.requireValue;
    final changed =
        _binding != _context.generation ||
        before.source?.value?.details != source.value?.details;
    _binding = _context.generation;
    if (changed) {
      _borrow?.retire();
      _borrow = null;
    }
    state = AsyncData(
      before.copyWith(
        source: source,
        generation: changed ? before.generation + 1 : before.generation,
        header: changed ? null : before.header,
        costs: changed ? [] : before.costs,
        cacheSavings: changed ? [] : before.cacheSavings,
        texts: changed ? {} : before.texts,
        nextCostOffset: changed ? null : before.nextCostOffset,
        nextSavingOffset: changed ? null : before.nextSavingOffset,
        loading: changed ? false : before.loading,
        error: changed ? null : before.error,
      ),
    );
    // Only actual details identity changes re-read. Live token samples don't.
    if (changed && before.detailsVisible) loadDetails();
  }

  void setDetailsVisible(bool visible) {
    if (!ref.mounted || !state.hasValue) return;
    state = AsyncData(state.requireValue.copyWith(detailsVisible: visible));
    if (visible && state.requireValue.header == null) loadDetails();
  }

  Future<void> loadDetails() async {
    final before = state.requireValue;
    final session = _context.session;
    final origin = before.source?.stamp;
    final reference = before.source?.value?.details;
    if (!before.detailsVisible ||
        before.loading ||
        session == null ||
        origin == null ||
        reference == null) {
      return;
    }
    final borrow = _borrow ??= ReadScopeBorrow<ContextReadScope>(
      open: () => session.openContext(reference, origin: origin),
      requestClose: (scope) => scope.requestClose(),
      close: (scope) => scope.close(),
      retryCleanup: (scope) => scope.retryCleanup(),
    );
    bool current() =>
        ref.mounted &&
        identical(_borrow, borrow) &&
        identical(_context.session, session) &&
        state.requireValue.generation == before.generation;
    state = AsyncData(before.copyWith(loading: true, error: null));
    try {
      final scope = await borrow.open();
      final header = await scope.header();
      if (!current()) return;
      if (header.scope.runtimeEpoch != origin.runtimeEpoch ||
          header.scope.incarnation != origin.incarnation) {
        throw readProtocol('context-origin');
      }
      final texts = registerReadTexts({}, [
        ?header.frozenModelId,
        ?header.promptCachePolicy,
      ]);
      state = AsyncData(
        state.requireValue.copyWith(
          header: header,
          texts: texts,
          nextCostOffset: header.estimatedCostCount > 0 ? 0 : null,
          nextSavingOffset: header.estimatedCacheSavingCount > 0 ? 0 : null,
          costs: [],
          cacheSavings: [],
        ),
      );
    } on StudioFailure catch (error) {
      if (current()) {
        state = AsyncData(state.requireValue.copyWith(error: error));
      }
    } finally {
      if (current()) {
        state = AsyncData(state.requireValue.copyWith(loading: false));
      }
    }
    if (current() && state.requireValue.header != null) {
      await loadCosts();
      if (current()) await loadCacheSavings();
    }
  }

  Future<void> loadCosts() => _costPage(false);
  Future<void> loadCacheSavings() => _costPage(true);

  Future<void> _costPage(bool savings) async {
    final before = state.requireValue;
    final borrow = _borrow;
    final offset = savings ? before.nextSavingOffset : before.nextCostOffset;
    if (!before.detailsVisible ||
        before.loading ||
        borrow == null ||
        offset == null ||
        before.header == null) {
      return;
    }
    bool current() =>
        ref.mounted &&
        identical(_borrow, borrow) &&
        state.requireValue.generation == before.generation;
    state = AsyncData(before.copyWith(loading: true, error: null));
    try {
      final scope = await borrow.open();
      final page = await (savings
          ? scope.cacheSavings(offset: offset, limit: 32)
          : scope.costs(offset: offset, limit: 32));
      if (!current()) return;
      checkReadPage(
        expectedScope: before.header!.scope,
        scope: page.scope,
        requested: offset,
        offset: page.offset,
        total: page.total,
        count: page.items.length,
        next: page.nextOffset,
        expectedTotal: savings
            ? before.header!.estimatedCacheSavingCount
            : before.header!.estimatedCostCount,
      );
      for (final (position, item) in page.items.indexed) {
        if (item.index != offset + position) throw readProtocol('cost-index');
      }
      final next = state.requireValue;
      state = AsyncData(
        next.copyWith(
          costs: savings ? next.costs : [...next.costs, ...page.items],
          cacheSavings: savings
              ? [...next.cacheSavings, ...page.items]
              : next.cacheSavings,
          nextCostOffset: savings ? next.nextCostOffset : page.nextOffset,
          nextSavingOffset: savings ? page.nextOffset : next.nextSavingOffset,
          texts: registerReadTexts(
            next.texts,
            page.items.map((item) => item.currency),
          ),
        ),
      );
    } on StudioFailure catch (error) {
      if (current()) {
        state = AsyncData(state.requireValue.copyWith(error: error));
      }
    } finally {
      if (current()) {
        state = AsyncData(state.requireValue.copyWith(loading: false));
      }
    }
  }

  Future<void> loadText(int fieldId) {
    final identity = (state.requireValue.generation, fieldId);
    final running = _texts[identity];
    if (running != null) return running;
    final task = _text(fieldId);
    _texts[identity] = task;
    task.whenComplete(() {
      if (identical(_texts[identity], task)) _texts.remove(identity);
    }).ignore();
    return task;
  }

  Future<void> _text(int fieldId) async {
    final before = state.requireValue;
    final borrow = _borrow;
    final progress = before.texts[fieldId];
    if (borrow == null ||
        progress == null ||
        progress.complete ||
        !before.detailsVisible) {
      return;
    }
    bool current() =>
        ref.mounted &&
        identical(_borrow, borrow) &&
        state.requireValue.generation == before.generation;
    try {
      final scope = await borrow.open();
      final chunk = await scope.text(
        fieldId,
        offset: progress.loadedUtf8Bytes,
        maxBytes: 65536,
      );
      if (current()) {
        state = AsyncData(
          state.requireValue.copyWith(
            texts: {
              ...state.requireValue.texts,
              fieldId: applyReadChunk(progress, chunk),
            },
          ),
        );
      }
    } on StudioFailure catch (error) {
      if (current()) {
        state = AsyncData(state.requireValue.copyWith(error: error));
      }
    }
  }
}
