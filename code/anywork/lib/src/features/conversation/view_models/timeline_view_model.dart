import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../app/app_bindings.dart';
import '../state/timeline_view_state.dart';
import 'timeline_actions.dart';

part 'timeline_view_model.g.dart';

@riverpod
class TimelineViewModel extends _$TimelineViewModel {
  late TimelineActions _actions;

  @override
  FutureOr<TimelineViewState> build(String threadId) {
    _actions = ref.read(timelineActionsProvider);
    final observation = _actions.changes.listen((next) {
      if (!ref.mounted) return;
      if (next == null) {
        final previous = state.value;
        if (previous != null) state = AsyncData(previous.copyWith(ready: false));
      } else if (next.threadId == threadId) {
        state = AsyncData(next);
      }
    });
    ref.onDispose(observation.cancel);
    // Register and read synchronously, with no snapshot→await→listen gap.
    final value = _actions.value;
    return value?.threadId == threadId ? value! : TimelineViewState(threadId: threadId);
  }

  void enterHistory() => _actions.enterHistory(threadId);
  Future<void> loadOlder() => _actions.loadOlder(threadId, state.requireValue.generation);
  Future<void> retryOlder() => _actions.loadOlder(threadId, state.requireValue.generation, retry: true);
  Future<void> returnLive() => _actions.returnLive(threadId);
  Future<void> retryConnection() => _actions.retryConnection(threadId);
}
