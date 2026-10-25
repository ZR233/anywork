import 'package:anywork_client/conversation.dart';
import 'package:anywork_client/resources.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

import 'read_progress.dart';

part 'todo_view_state.freezed.dart';

@Freezed(toStringOverride: false)
abstract class TodoViewState with _$TodoViewState {
  const TodoViewState._();
  const factory TodoViewState({
    required String threadId,
    ThreadFacetStamp? origin,
    TodoBrief? todo,
    TodoReadHeader? header,
    @Default([]) List<TodoReadItem> items,
    @Default({}) Map<int, TextReadProgress> texts,
    int? nextOffset,
    @Default(false) bool expanded,
    @Default(false) bool loading,
    @Default(0) int generation,
    StudioFailure? error,
  }) = _TodoViewState;
  String? textOf(ReadText? value) => switch (value) {
    null => null,
    InlineReadText(:final text) => text,
    DeferredReadText(:final fieldId) =>
      texts[fieldId]?.complete == true ? texts[fieldId]!.text : null,
  };
}
