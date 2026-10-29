import 'conversation_watermark.dart';

/// The producer explicitly lost observation frames. This is distinct from a
/// notification whose envelope does not join the current subscription watermark.
final class ThreadStateLagged implements Exception {
  const ThreadStateLagged({
    required this.threadId,
    required this.dropped,
    this.epoch,
  });

  final String threadId;
  final int dropped;
  final int? epoch;

  @override
  String toString() =>
      'Thread state lagged (thread=$threadId, epoch=$epoch, dropped=$dropped)';
}

/// The logical Thread demand ended before its replacement stream established a
/// baseline. This cancels observation only, never a submitted business command.
final class ThreadStateResyncCancelled implements Exception {
  const ThreadStateResyncCancelled(this.threadId);

  final String threadId;

  @override
  String toString() => 'Thread state resync cancelled (thread=$threadId)';
}

/// Bounded, content-free diagnostics for a genuine notification continuity gap.
final class ThreadStateContinuityError implements Exception {
  const ThreadStateContinuityError({
    required this.threadId,
    required this.expected,
    required this.revision,
    this.epoch,
    this.baseRevision,
  });

  final String threadId;
  final ThreadStreamWatermark expected;
  final int revision;
  final int? epoch;
  final int? baseRevision;

  @override
  String toString() =>
      'Thread state continuity gap (thread=$threadId, '
      'hasSnapshot=${expected.hasSnapshot}, '
      'expected epoch=${expected.epoch}, revision=${expected.revision}; '
      'received epoch=$epoch, baseRevision=$baseRevision, revision=$revision)';
}
