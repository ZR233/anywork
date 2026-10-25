import '../../../resources.dart';

/// Runtime-only diagnostic borrowed from the concrete failed attempt. It is
/// not a wire DTO and never serializes or prints the original private cause.
/// A caller can recognize its original error without depending on its type.
final class TimelineFailureIdentity {
  TimelineFailureIdentity({
    required this.attemptId,
    required this.failure,
    required Object originalError,
    required this.diagnosticError,
  }) : _originalError = originalError;

  final AttemptId attemptId;
  final StudioFailure failure;
  final Object _originalError;

  bool isOriginal(Object error) => identical(_originalError, error);

  /// The object a diagnostic-visible state retains for this attempt: [failure]
  /// for a canonical typed failure, otherwise the original object itself.
  ///
  /// A holder may read its runtime type; it must not call `toString()`, copy a
  /// message/details/stack, or serialize it. An unknown error is never replaced
  /// by a synthesized failure here (design/26 §26.9).
  final Object diagnosticError;

  @override
  String toString() => 'TimelineFailureIdentity($attemptId, $failure)';
}
