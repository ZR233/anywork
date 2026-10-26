import 'package:anywork_client/conversation.dart';
import 'package:anywork_client/resources.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'plan_view_state.freezed.dart';

/// Reading projection of the one Plan document.
///
/// [open] and [fullWidth] are GUI-only view state, never a second source of the
/// plan document, decision or lifecycle: they only place the same published
/// document in the reading area. [panelWidth] is the last dragged side-by-side
/// width and is likewise never persisted (design/13-plan.md §13.5).
@Freezed(toStringOverride: false)
abstract class PlanViewState with _$PlanViewState {
  const factory PlanViewState({
    required String threadId,
    ThreadFacetStamp? origin,
    PlanBrief? plan,
    PlanDocumentValue? document,

    /// The reading panel is open in the conversation reading area.
    @Default(false) bool open,

    /// Full-width reading instead of side-by-side. A narrow window forces this
    /// at layout time without writing it here.
    @Default(false) bool fullWidth,

    /// Current side-by-side panel width; the split component owns the drag.
    @Default(planDefaultPanelWidth) double panelWidth,
    @Default(false) bool loading,
    @Default(0) int latestIntent,
    StudioFailure? error,
  }) = _PlanViewState;
}

/// Default side-by-side width of the Plan reading panel (design/13 §13.5).
const double planDefaultPanelWidth = 720;

/// Minimum width the Plan panel keeps while side-by-side.
const double planMinimumPanelWidth = 360;

/// Minimum width kept for the conversation and its operations.
const double planMinimumConversationWidth = 400;
