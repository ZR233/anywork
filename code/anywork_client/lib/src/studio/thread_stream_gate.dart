import '../../studio_ports.dart';

/// Thread 单流水位：epoch + baseRevision + revision。
///
/// 快照可以低于上一订阅代次的 revision，因此快照不按低水位丢弃；
/// 通知必须接在当前水位之后，缺口走重同步而不是拼接。
class ThreadStreamWatermark {
  const ThreadStreamWatermark({
    required this.hasSnapshot,
    required this.revision,
    this.epoch,
    this.baseRevision,
  });

  final bool hasSnapshot;
  final int revision;
  final int? epoch;
  final int? baseRevision;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ThreadStreamWatermark &&
          hasSnapshot == other.hasSnapshot &&
          revision == other.revision &&
          epoch == other.epoch &&
          baseRevision == other.baseRevision;

  @override
  int get hashCode => Object.hash(hasSnapshot, revision, epoch, baseRevision);
}

enum ThreadFrameDecision { drop, apply, resync }

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

/// Bridge 在调用 store reduce 之前的第一道拒收。
ThreadFrameDecision classifyThreadFrame(
  ThreadStreamWatermark? watermark,
  ThreadStreamFrame frame,
) {
  return switch (frame) {
    ThreadSnapshotFrame() => ThreadFrameDecision.apply,
    ThreadResyncRequiredFrame() => ThreadFrameDecision.resync,
    ThreadNotificationFrame(
      :final revision,
      :final epoch,
      :final baseRevision,
    ) =>
      _classifyNotification(
        watermark,
        revision: revision,
        epoch: epoch,
        baseRevision: baseRevision,
      ),
  };
}

ThreadFrameDecision _classifyNotification(
  ThreadStreamWatermark? watermark, {
  required int revision,
  required int? epoch,
  required int? baseRevision,
}) {
  if (watermark == null || !watermark.hasSnapshot) {
    return ThreadFrameDecision.resync;
  }
  if (epoch != null && watermark.epoch != null && epoch != watermark.epoch) {
    return ThreadFrameDecision.resync;
  }
  if (baseRevision != null && baseRevision != watermark.revision) {
    return ThreadFrameDecision.resync;
  }
  if (revision <= watermark.revision) return ThreadFrameDecision.drop;
  if (revision != watermark.revision + 1) return ThreadFrameDecision.resync;
  return ThreadFrameDecision.apply;
}
