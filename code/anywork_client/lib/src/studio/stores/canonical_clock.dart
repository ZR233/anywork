import 'domain_sync.dart';

/// 单 revision 领域时钟。
///
/// [loaded] 为 false 时 revision 0 只是未消费哨兵，首帧（含 revision 0）必须采纳。
/// 已加载后同一水位幂等丢弃，较低水位不得覆盖。revision 与传输状态都参与相等，
/// 避免 Riverpod 3 按 `==` 过滤掉水位前进或局部错误。
class CanonicalClockState<T> {
  const CanonicalClockState({
    this.value,
    this.revision = 0,
    this.loaded = false,
    this.sync = const DomainSyncStatus(),
  });

  final T? value;
  final int revision;
  final bool loaded;
  final DomainSyncStatus sync;

  CanonicalClockState<T> applyRevision(T value, int revision) {
    if (loaded && revision <= this.revision) return this;
    return CanonicalClockState<T>(
      value: value,
      revision: revision,
      loaded: true,
      sync: sync.connected(),
    );
  }

  CanonicalClockState<T> withSync(DomainSyncStatus sync) {
    if (sync == this.sync) return this;
    return CanonicalClockState<T>(
      value: value,
      revision: revision,
      loaded: loaded,
      sync: sync,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CanonicalClockState<T> &&
          loaded == other.loaded &&
          revision == other.revision &&
          sync == other.sync &&
          identical(value, other.value);

  @override
  int get hashCode =>
      Object.hash(loaded, revision, sync, identityHashCode(value));
}
