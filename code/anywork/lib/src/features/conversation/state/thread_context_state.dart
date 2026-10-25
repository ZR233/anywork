import 'package:anywork_client/conversation.dart';
import 'package:anywork_client/operations.dart';
import 'package:anywork_client/resources.dart';
import 'package:anywork_client/workspace.dart' show ThreadStatus;
import 'package:freezed_annotation/freezed_annotation.dart';

import 'read_progress.dart';

part 'thread_context_state.freezed.dart';

@Freezed(toStringOverride: false)
abstract class ThreadContextViewState with _$ThreadContextViewState {
  const ThreadContextViewState._();
  const factory ThreadContextViewState({
    required String threadId,
    ThreadContextState? source,
    ThreadStatus? status,
    ContextReadHeader? header,
    @Default([]) List<CostReadItem> costs,
    @Default([]) List<CostReadItem> cacheSavings,
    @Default({}) Map<int, TextReadProgress> texts,
    int? nextCostOffset,
    int? nextSavingOffset,
    @Default(false) bool detailsVisible,
    @Default(false) bool loading,
    @Default(0) int generation,
    StudioFailure? error,
    OperationState? compaction,
  }) = _ThreadContextViewState;

  // Current catalog policy is never written into the frozen request diagnosis.
  CurrentContextPolicy? get currentPolicy => source?.value?.currentPolicy;
  ContextUsage? get frozenUsage => source?.value?.usage;
  int? get usedTokens =>
      source?.value?.liveContext?.latestContextTokens ??
      frozenUsage?.latestContextTokens;
  int? get displayLimit => status == ThreadStatus.idle
      ? currentPolicy?.autoCompactLimit
      : frozenUsage?.autoCompactLimit;
  double? get fraction {
    final used = usedTokens;
    final limit = displayLimit;
    return used == null || limit == null || limit <= 0 ? null : used / limit;
  }

  String? textOf(ReadText? value) => switch (value) {
    null => null,
    InlineReadText(:final text) => text,
    DeferredReadText(:final fieldId) =>
      texts[fieldId]?.complete == true ? texts[fieldId]!.text : null,
  };
}
