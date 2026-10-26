import 'package:anywork_client/conversation.dart';
import 'package:anywork_client/resources.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'timeline_view_state.freezed.dart';

enum TimelineDisplayMode { live, history }

@Freezed(toStringOverride: false)
abstract class TimelineViewState with _$TimelineViewState {
  const factory TimelineViewState({
    required String threadId,
    @Default(0) int generation,
    @Default(TimelineDisplayMode.live) TimelineDisplayMode displayMode,
    @Default(TimelineConnectionPhase.idle)
    TimelineConnectionPhase connectionPhase,
    // Current connection error, or null. A typed failure stays its
    // [StudioFailure] projection; an unknown exception keeps the original
    // object so diagnostics can read its runtime type instead of a synthesized
    // failure (design/26 §26.9).
    Object? connectionError,
    String? olderCursor,
    @Default(false) bool hasOlder,
    @Default(false) bool olderLoading,

    /// Diagnosis of the last failed older-page read. A canonical failure keeps
    /// its typed projection; an unknown exception keeps the original object so
    /// the identity and runtime type stay observable instead of being replaced
    /// by a synthesized internal failure (design/26 §26.9).
    Object? olderError,
    @Default(false) bool hasNewOutput,
    @Default(false) bool preparingLive,
    @Default(false) bool ready,
  }) = _TimelineViewState;
}

/// The stable diagnostic type token of a retained error object.
///
/// A canonical [StudioFailure] is reported by its public type name instead of
/// Freezed's generated `_StudioFailure` implementation name, so the Driver
/// whitelist keeps one stable token for a typed failure. Any other error keeps
/// its own runtime type. Nothing here calls `toString()` on the error or copies
/// a message, detailsJson, stack or body text.
String? diagnosticTypeName(Object? error) => switch (error) {
  null => null,
  StudioFailure() => 'StudioFailure',
  final other => other.runtimeType.toString(),
};

/// The single projection of [TimelineViewState.connectionError] for the UI and
/// the Driver whitelist.
///
/// Only an actual [StudioFailure] yields code/retryable/correlationId; an
/// unknown error keeps them null and contributes its runtime type name only.
/// Nothing here calls `toString()` on the error or copies its message,
/// detailsJson, stack or body text.
extension TimelineConnectionFailureProjection on TimelineViewState {
  /// The typed projection, or null when the current error is not typed.
  StudioFailure? get connectionFailure => switch (connectionError) {
    final StudioFailure failure => failure,
    _ => null,
  };

  /// `'StudioFailure'` for a typed failure, the original runtime type name
  /// otherwise, and null without a current error.
  String? get connectionErrorType => diagnosticTypeName(connectionError);
  StudioFailureCode? get connectionErrorCode => connectionFailure?.code;
  bool? get connectionErrorRetryable => connectionFailure?.retryable;
  String? get connectionErrorCorrelationId => connectionFailure?.correlationId;
}
