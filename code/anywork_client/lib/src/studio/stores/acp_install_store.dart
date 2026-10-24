import '../../../models.dart';
import '../../../anywork_client.dart' show ReadModel;
import 'canonical_clock.dart';
import 'domain_sync.dart';

/// `acpInstall` 领域的唯一 reducer。
///
/// 产品 topic 帧、命令响应与按需读取都进入同一入口，并按领域 revision 收敛：
/// 领域未加载时接受首个快照（即使 revision 为 0），之后只接受更高水位，迟到或
/// 重复事实不得回退当前状态。这里只保存后端发布的事实，不合成“已安装”或
/// “进度前进”；下载 100% 也不是就绪。
class AcpInstallStore
    extends ReadModel<CanonicalClockState<AcpInstallSnapshotView>> {
  AcpInstallStore()
    : super(const CanonicalClockState<AcpInstallSnapshotView>());

  void apply(AcpInstallSnapshotView next) {
    state = state.applyRevision(next, next.revision);
  }

  void applyTransport(DomainSyncStatus sync) {
    state = state.withSync(sync);
  }

  /// 已加载的 canonical 快照；未加载时为 null（不能当成“未准备”的事实）。
  AcpInstallSnapshotView? get snapshot => state.value;

  /// 给定 provider 的准备状态；未加载或条目缺失都按“未准备”处理。
  AcpInstallStateView stateOf(AcpProviderView provider) =>
      state.value?.stateOf(provider) ?? const AcpInstallIdleState();

  /// 已匹配的安装条目；缺失时为 null。
  AcpInstallEntryView? entryOf(AcpProviderView provider) =>
      state.value?.entry(provider);

  /// 该 provider 当前 canonical 的就绪结果（任何操作身份）。
  ///
  /// 调用方必须再用 [AcpPreparationIntent] 判断这是否属于本草稿的意图。
  AcpInstalledServerView? readyServer(AcpProviderView provider) =>
      state.value?.readyServer(provider);
}
