import 'package:anywork_client/models.dart';

int exactTimelineInt(BigInt value, String what) {
  final result = value.toInt();
  if (value.isNegative || result < 0 || BigInt.from(result) != value) {
    throw StudioFailure(
      code: StudioFailureCode.overloaded,
      message: 'Timeline $what cannot be represented exactly',
      retryable: false,
      correlationId: 'client-timeline-range',
    );
  }
  return result;
}

DateTime dateFromUnix(Object seconds) {
  final value = switch (seconds) {
    final BigInt value => value,
    final int value => BigInt.from(value),
    _ => throw const StudioFailure(
      code: StudioFailureCode.internal,
      message: 'The bridge timestamp is not an integer',
      retryable: false,
      correlationId: 'client-timestamp-type',
    ),
  };
  final milliseconds = value * BigInt.from(1000);
  final converted = milliseconds.toInt();
  if (BigInt.from(converted) == milliseconds) {
    try {
      return DateTime.fromMillisecondsSinceEpoch(converted);
    } on ArgumentError {
      // A valid native timestamp must not wrap into another instant.
    }
  }
  throw const StudioFailure(
    code: StudioFailureCode.overloaded,
    message: 'The bridge timestamp cannot be represented exactly',
    retryable: false,
    correlationId: 'client-timestamp-range',
  );
}
