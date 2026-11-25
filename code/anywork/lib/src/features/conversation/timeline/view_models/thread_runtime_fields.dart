import 'dart:async';

import 'package:anywork_client/conversation.dart';
import 'package:anywork_client/models.dart';
import 'package:riverpod/riverpod.dart';

import '../../../../presentation/providers/observe_client.dart';
import '../../../../presentation/providers/thread_session_store.dart';
import 'timeline_view_model.dart';

final threadTodoProvider = FutureProvider.autoDispose
    .family<TimelineTodoListUpdate?, String>(
      (ref, threadId) => _runtimeField(
        ref,
        threadId,
        'todo',
        inline: (session) => session.workspace?.todo,
        decode: decodeCurrentTodoState,
      ),
      retry: (_, _) => null,
    );

final threadWorkflowRunProvider = FutureProvider.autoDispose
    .family<ThreadWorkflowRun?, String>(
      (ref, threadId) => _runtimeField(
        ref,
        threadId,
        'workflow',
        inline: (session) => _workflowRun(session.workflow?.currentRun),
        decode: (value) =>
            _workflowRun(decodeCurrentWorkflowState(value).currentRun),
      ),
      retry: (_, _) => null,
    );

ThreadWorkflowRun? _workflowRun(WorkflowRunView? run) =>
    run == null ? null : ThreadWorkflowRun(run);

/// Observes the original run, including fields its SDK equality omits that
/// are used by the graph query or status readout.
final class ThreadWorkflowRun {
  const ThreadWorkflowRun(this.run);

  final WorkflowRunView run;

  @override
  bool operator ==(Object other) =>
      other is ThreadWorkflowRun &&
      run == other.run &&
      run.modeId == other.run.modeId &&
      run.graphRevision == other.run.graphRevision &&
      run.graphHash == other.run.graphHash &&
      run.terminal == other.run.terminal;

  @override
  int get hashCode => Object.hash(
    run,
    run.modeId,
    run.graphRevision,
    run.graphHash,
    run.terminal,
  );
}

FutureOr<T?> _runtimeField<T>(
  Ref ref,
  String threadId,
  String name, {
  required T? Function(ThreadSessionState) inline,
  required T? Function(Object?) decode,
}) {
  final source = threadSessionStoreProvider(threadId).select((session) {
    final field = session.runtime?.deferredField(name);
    return (field: field, value: field == null ? inline(session) : null);
  });
  final (:field, :value) = ref.watch(source);
  if (field == null) return value;

  final owner = ref.watch(timelineSessionOwnerProvider);
  ref.watch(
    timelineViewModelProvider(threadId)
        .select((state) => state.asData?.value?.generation),
  );
  final lease = owner.lease(threadId);
  final reader = lease?.current;
  // Current can join an existing History lease without changing its generation.
  observeClient(ref, owner.source, (_) {
    final currentLease = owner.lease(threadId);
    if (!identical(currentLease, lease) ||
        !identical(currentLease?.current, reader)) {
      ref.invalidateSelf();
    }
  });
  if (lease == null || reader == null) {
    // The deferred field already exists. Stay loading until lease or reader
    // admission rebuilds this provider, and settle the superseded future.
    final waiting = Completer<T?>();
    ref.onDispose(() => waiting.complete(null));
    return waiting.future;
  }

  final scope = lease.openCurrentScope();
  ref.onDispose(scope.retire);

  return _readField(
    scope,
    field,
    decode,
    isCurrent: () {
      return ref.mounted &&
          identical(ref.read(timelineSessionOwnerProvider), owner) &&
          identical(owner.lease(threadId), lease) &&
          identical(lease.current, reader) &&
          ref.read(source).field == field;
    },
  );
}

Future<T?> _readField<T>(
  CurrentReadScope scope,
  CurrentStateField field,
  T? Function(Object?) decode, {
  required bool Function() isCurrent,
}) async {
  try {
    final Object? value;
    try {
      value = await scope.readStateField(field);
    } finally {
      await scope.close();
    }
    return isCurrent() ? decode(value) : null;
  } catch (_) {
    if (isCurrent()) rethrow;
    return null;
  }
}
