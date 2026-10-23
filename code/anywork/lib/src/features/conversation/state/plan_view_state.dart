import 'package:anywork_client/conversation.dart';
import 'package:anywork_client/resources.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'plan_view_state.freezed.dart';

@Freezed(toStringOverride: false)
abstract class PlanViewState with _$PlanViewState {
  const factory PlanViewState({
    required String threadId,
    ThreadFacetStamp? origin,
    PlanBrief? plan,
    PlanDocumentValue? document,
    @Default(false) bool expanded,
    @Default(false) bool loading,
    @Default(0) int latestIntent,
    StudioFailure? error,
  }) = _PlanViewState;
}
