import 'package:freezed_annotation/freezed_annotation.dart';

import 'identity.dart';

part 'closing.freezed.dart';

enum CleanupRecovery { awaitCompletion, retryClose, terminal }

@Freezed(toStringOverride: false)
abstract class StudioShutdownIssue with _$StudioShutdownIssue {
  const factory StudioShutdownIssue({
    required String stage,
    required String code,
    required String message,
    required bool retryable,
    required String correlationId,
  }) = _StudioShutdownIssue;
}

@Freezed(toStringOverride: false)
abstract class FeedCloseIssue with _$FeedCloseIssue {
  const factory FeedCloseIssue({
    required StudioShutdownIssue diagnostic,
    required CleanupRecovery recovery,
  }) = _FeedCloseIssue;
}

@Freezed(toStringOverride: false)
sealed class FeedCloseOutcome with _$FeedCloseOutcome {
  const FeedCloseOutcome._();

  const factory FeedCloseOutcome.clean() = CleanFeedCloseOutcome;

  factory FeedCloseOutcome.unresolved({required List<FeedCloseIssue> issues}) =
      UnresolvedFeedCloseOutcome;
}

/// Ejected Freezed case: own the copied list, not a view of caller storage.
@Freezed(toStringOverride: false)
final class UnresolvedFeedCloseOutcome extends FeedCloseOutcome
    with _$UnresolvedFeedCloseOutcome {
  UnresolvedFeedCloseOutcome({required List<FeedCloseIssue> issues})
    : issues = List.unmodifiable(issues),
      super._() {
    if (this.issues.isEmpty) {
      throw ArgumentError('Unresolved requires issues');
    }
  }

  final List<FeedCloseIssue> issues;
}

@Freezed(toStringOverride: false)
abstract class FeedCloseReport with _$FeedCloseReport {
  FeedCloseReport._({required String feedId}) {
    if (feedId.isEmpty) throw ArgumentError.value(feedId, 'feedId');
  }

  factory FeedCloseReport({
    required String feedId,
    required FeedCloseOutcome outcome,
  }) = _FeedCloseReport;
}

@Freezed(toStringOverride: false)
final class UnresolvedResource with _$UnresolvedResource {
  UnresolvedResource({
    required this.owner,
    required this.attemptId,
    required List<FeedCloseIssue> issues,
  }) : issues = List.unmodifiable(issues) {
    if (this.issues.isEmpty) {
      throw ArgumentError('Unresolved requires issues');
    }
  }

  final String owner;
  final AttemptId attemptId;
  final List<FeedCloseIssue> issues;
}

@Freezed(toStringOverride: false)
final class CloseReport with _$CloseReport {
  CloseReport({required List<UnresolvedResource> unresolved})
    : unresolved = List.unmodifiable(unresolved);

  final List<UnresolvedResource> unresolved;

  bool get complete => unresolved.isEmpty;
}
