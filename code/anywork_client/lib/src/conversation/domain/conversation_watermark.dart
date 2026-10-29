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
