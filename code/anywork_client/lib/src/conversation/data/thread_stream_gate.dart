import '../../../studio_ports.dart';
import '../domain/conversation_watermark.dart';

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
