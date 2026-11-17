import 'conversation_watermark.dart';

final class ProtocolVersionMismatch implements Exception {
  const ProtocolVersionMismatch({
    required this.received,
    required this.supported,
    required this.field,
  });
  final int? received;
  final int supported;
  final String field;
  @override
  String toString() =>
      'ProtocolVersionMismatch($field=$received, supported=$supported)';
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
