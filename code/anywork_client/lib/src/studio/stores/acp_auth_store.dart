import '../../../models.dart';
import '../../../anywork_client.dart' show ReadModel;
import 'canonical_clock.dart';
import 'domain_sync.dart';

/// `acpAuth` 领域的唯一 reducer。
///
/// 产品 topic 帧、命令响应与按需读取都进入同一入口，并按领域 revision 收敛：
/// 领域未加载时接受首个快照（即使 revision 为 0），之后只接受更高水位，迟到或
/// 重复事实不得回退当前状态。这里只保存后端发布的事实，不合成登录成功。
class AcpAuthStore extends ReadModel<CanonicalClockState<AcpAuthSnapshotView>> {
  AcpAuthStore() : super(const CanonicalClockState<AcpAuthSnapshotView>());

  void apply(AcpAuthSnapshotView next) {
    state = state.applyRevision(next, next.revision);
  }

  void applyTransport(DomainSyncStatus sync) {
    state = state.withSync(sync);
  }

  /// 已加载的 canonical 快照；未加载时为 null（不能当成“全部未检查”的事实）。
  AcpAuthSnapshotView? get snapshot => state.value;

  /// 单个接入在给定连接身份下的观察状态。
  ///
  /// 未加载、条目缺失或连接身份不匹配都按未检查处理：调用方必须传当前配置的
  /// `connectionRevision`，不能只用 accountId 猜测。
  AcpAuthStateView stateOf(
    String accountId, {
    required int connectionRevision,
  }) =>
      state.value?.stateOf(accountId, connectionRevision: connectionRevision) ??
      const AcpUncheckedState();

  /// 已匹配的观察条目（含所属连接身份）；不匹配时为 null。
  AcpAuthAccountView? accountOf(
    String accountId, {
    required int connectionRevision,
  }) => state.value?.account(accountId, connectionRevision: connectionRevision);
}
