import '../../../resources.dart';

/// Stable protocol reason labels. Unrecognized future labels remain untyped.
/// The existing typed failure-details union is the only stored representation.
enum StudioFailureReason {
  childThreadRequiresParentScheduling,
  continuationUnavailable,
  continuationClaimed,
  staleContinuation,
  staleExecution,
  noExecution,
  continuationAccepted,
  executionInProgress,
  interactionNotHosted,
  staleInteraction,
  threadArchived;

  String get label => name;
  static StudioFailureReason? fromLabel(String? label) {
    for (final reason in values) {
      if (reason.label == label) return reason;
    }
    return null;
  }
}

StudioFailureReason? studioFailureReason(Object? error) => error is! StudioFailure
    ? null
    : switch (error.details) {
        ReasonFailureDetails(:final reason) ||
        ControlFailureDetails(:final reason) => StudioFailureReason.fromLabel(reason),
        _ => null,
      };
