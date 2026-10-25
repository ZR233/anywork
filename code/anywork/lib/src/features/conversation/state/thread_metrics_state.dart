import 'package:anywork_client/conversation.dart';
import 'package:anywork_client/resources.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'thread_metrics_state.freezed.dart';

@Freezed(toStringOverride: false)
abstract class ThreadMetricsViewState with _$ThreadMetricsViewState {
  const ThreadMetricsViewState._();
  const factory ThreadMetricsViewState({
    required String threadId,
    ThreadMetricsState? source,
    @Default(true) bool visible,
    @Default(false) bool detailsVisible,
    @Default(false) bool retrying,
    @Default(0) int latestIntent,
    StudioFailure? error,
  }) = _ThreadMetricsViewState;

  /// Choose only a complete same-source pair. Partial live never erases the
  /// previous authoritative pair or borrows its denominator.
  ({int tokens, int millis})? get sample {
    final value = source?.value;
    final live = value?.live;
    final tokens = live?.completionTokens;
    final millis = live?.responseMillis;
    if (tokens != null && millis != null && millis > 0) {
      return (tokens: tokens, millis: millis);
    }
    final authoritative = value?.authoritative;
    if (authoritative == null || authoritative.responseMillis <= 0) return null;
    return (
      tokens: authoritative.completionTokens,
      millis: authoritative.responseMillis,
    );
  }

  double? get tokensPerSecond {
    final pair = sample;
    return pair == null ? null : pair.tokens * 1000 / pair.millis;
  }
}
