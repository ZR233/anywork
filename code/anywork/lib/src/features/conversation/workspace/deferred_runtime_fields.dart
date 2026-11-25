import 'package:anywork_client/conversation.dart';
import 'package:anywork_client/models.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../presentation/providers/thread_session_store.dart';
import '../timeline/view_models/timeline_view_model.dart';

final deferredTodoProvider = FutureProvider.autoDispose
    .family<TimelineTodoListUpdate?, String>(
      (ref, threadId) =>
          _readField(ref, threadId, 'todo', decodeCurrentTodoState),
      retry: (_, _) => null,
    );

final deferredWorkflowRunProvider = FutureProvider.autoDispose
    .family<WorkflowRunView?, String>(
      (ref, threadId) => _readField(
        ref,
        threadId,
        'workflow',
        (value) => decodeCurrentWorkflowState(value).currentRun,
      ),
      retry: (_, _) => null,
    );

final hasDeferredWorkflowProvider = Provider.autoDispose.family<bool, String>(
  (ref, threadId) => ref.watch(
    threadSessionStoreProvider(threadId)
        .select((state) => state.runtime?.deferredField('workflow') != null),
  ),
);

Future<T?> _readField<T>(
  Ref ref,
  String threadId,
  String name,
  T? Function(Object? value) decode,
) async {
  final fieldProvider = threadSessionStoreProvider(threadId)
      .select((state) => state.runtime?.deferredField(name));
  final field = ref.watch(fieldProvider);
  if (field == null) return null;

  // The field may arrive before the timeline publishes its first usable lease.
  ref.watch(
    timelineViewModelProvider(threadId)
        .select((value) => value.asData?.value?.generation),
  );
  final owner = ref.read(timelineSessionOwnerProvider);
  final lease = owner.lease(threadId);
  if (lease == null || lease.current == null) return null;

  final scope = lease.openCurrentScope();
  ref.onDispose(scope.retire);
  bool isCurrent() =>
      ref.mounted &&
      identical(owner.lease(threadId), lease) &&
      identical(lease.current, scope.reader) &&
      ref.read(fieldProvider) == field;

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
