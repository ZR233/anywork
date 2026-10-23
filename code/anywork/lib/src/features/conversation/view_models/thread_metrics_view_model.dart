import 'dart:async';

import 'package:anywork_client/conversation.dart';
import 'package:anywork_client/resources.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../app/app_bindings.dart';
import '../state/thread_metrics_state.dart';
import 'session_facet_observer.dart';

part 'thread_metrics_view_model.g.dart';

@riverpod
class ThreadMetricsViewModel extends _$ThreadMetricsViewModel {
  late SessionFacetObserver<ThreadMetricsState> _observer;
  int _bindingGeneration = 0;

  @override
  FutureOr<ThreadMetricsViewState> build(String threadId) {
    _observer = SessionFacetObserver<ThreadMetricsState>(
      repository: ref.read(conversationRepositoryProvider), threadId: threadId,
      source: (session) => session.metrics,
      onValue: (source) {
        if (!ref.mounted || !state.hasValue) return;
        final changed = _bindingGeneration != _observer.generation;
        _bindingGeneration = _observer.generation;
        final value = state.requireValue;
        state = AsyncData(value.copyWith(source: source,
          retrying: changed ? false : value.retrying,
          latestIntent: changed ? value.latestIntent + 1 : value.latestIntent));
      },
    );
    _bindingGeneration = _observer.generation;
    ref.onDispose(_observer.cancel);
    return ThreadMetricsViewState(threadId: threadId, source: _observer.value);
  }

  void setVisible(bool visible) {
    if (visible) { _observer.resume(); } else { _observer.pause(); }
    state = AsyncData(state.requireValue.copyWith(visible: visible));
  }
  void setDetailsVisible(bool visible) => state = AsyncData(state.requireValue.copyWith(detailsVisible: visible));

  Future<void> retry() async {
    final before = state.requireValue;
    final session = _observer.session;
    if (before.retrying || session == null) return;
    final intent = before.latestIntent + 1;
    state = AsyncData(before.copyWith(retrying: true, latestIntent: intent, error: null));
    try {
      await session.retry(ThreadFacet.metrics);
    } on StudioFailure catch (error) {
      if (_current(session, intent)) state = AsyncData(state.requireValue.copyWith(error: error));
    } finally {
      if (_current(session, intent)) state = AsyncData(state.requireValue.copyWith(retrying: false));
    }
  }
  bool _current(ConversationSession session, int intent) => ref.mounted &&
      identical(_observer.session, session) && state.requireValue.latestIntent == intent;
}
