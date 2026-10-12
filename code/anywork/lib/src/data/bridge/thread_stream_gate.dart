import '../frb/studio_api.dart';

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
