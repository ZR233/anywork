import '../../../models.dart';
import '../../../anywork_client.dart' show ReadModel;
import 'canonical_clock.dart';
import 'domain_sync.dart';

/// 一个宿主主会话的子任务待决交互领域镜像与真实观察资格。
///
/// [canonical] 是唯一集合与领域时钟（不复制集合、不改通用时钟语义）；
/// [observationGeneration] 与 [hasCurrentBaseline] 表达主题观察的技术生命
/// 周期：全部主题需求释放到 idle 时撤销本代资格并推进观察代次（重复 idle
/// 不空转）；同一仍存续观察内的 connecting/reconnecting/failed 只更新
/// [canonical] 的 sync，保留已取得的资格与 lastKnown 集合。
final class ChildInteractionState {
  const ChildInteractionState({
    this.canonical = const CanonicalClockState<ChildInteractionsStateView>(),
    this.observationGeneration = 0,
    this.hasCurrentBaseline = false,
  });

  final CanonicalClockState<ChildInteractionsStateView> canonical;
  final int observationGeneration;
  final bool hasCurrentBaseline;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ChildInteractionState &&
          canonical == other.canonical &&
          observationGeneration == other.observationGeneration &&
          hasCurrentBaseline == other.hasCurrentBaseline;

  @override
  int get hashCode =>
      Object.hash(canonical, observationGeneration, hasCurrentBaseline);
}

/// 一个宿主主会话的子任务待决交互领域镜像。
///
/// 事实只来自 `ChildInteractions` 主题的基线与事件：按领域 revision 拒旧，
/// 显式只读查询（`readChildInteractions`）不写入本镜像。导航/展示不是
/// canonical 查询结果或决议观察事实；展示资格由本状态独立表达。
class ChildInteractionStore extends ReadModel<ChildInteractionState> {
  ChildInteractionStore(this.hostThreadId)
    : super(const ChildInteractionState());

  final String hostThreadId;

  /// 接纳一帧本代完整基线或完整集合事件。
  ///
  /// incoming >= canonical.revision 才能确认本代资格：更旧帧的内容与资格
  /// 都不变；相等时只确认资格、不重写 canonical 对象；更新时按唯一时钟
  /// 归约。资格与集合变化都在同一个 immutable 状态发布中可观察。
  void accept(ChildInteractionsStateView next) {
    if (next.hostThreadId != hostThreadId) return;
    final canonical = state.canonical;
    if (canonical.loaded && next.revision < canonical.revision) return;
    final CanonicalClockState<ChildInteractionsStateView> canonicalNext;
    if (!canonical.loaded || next.revision > canonical.revision) {
      canonicalNext = canonical.applyRevision(next, next.revision);
    } else {
      // Equal watermark: confirm qualification without rewriting canonical.
      canonicalNext = canonical;
    }
    if (!state.hasCurrentBaseline) {
      state = ChildInteractionState(
        canonical: canonicalNext,
        observationGeneration: state.observationGeneration,
        hasCurrentBaseline: true,
      );
      return;
    }
    if (identical(canonicalNext, canonical)) return;
    state = ChildInteractionState(
      canonical: canonicalNext,
      observationGeneration: state.observationGeneration,
      hasCurrentBaseline: true,
    );
  }

  /// 主题连接状态投影：idle 表示全部主题需求已释放，撤销本代资格并推进
  /// 观察代次；其余相位只更新 canonical.sync，保留资格与 lastKnown 集合。
  void applyTransport(DomainSyncStatus sync) {
    final canonical = state.canonical;
    if (sync.phase == DomainSyncPhase.idle) {
      if (!state.hasCurrentBaseline &&
          canonical.sync.phase == DomainSyncPhase.idle) {
        return;
      }
      state = ChildInteractionState(
        canonical: canonical.withSync(sync),
        observationGeneration: state.observationGeneration + 1,
        hasCurrentBaseline: false,
      );
      return;
    }
    final next = canonical.withSync(sync);
    if (identical(next, canonical)) return;
    state = ChildInteractionState(
      canonical: next,
      observationGeneration: state.observationGeneration,
      hasCurrentBaseline: state.hasCurrentBaseline,
    );
  }
}
