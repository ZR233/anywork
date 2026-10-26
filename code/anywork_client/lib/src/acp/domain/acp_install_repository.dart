/// `acpInstall` 资源 owner：共享资产的 canonical 镜像、观察租约与准备命令。
library;

import '../../../operations.dart';
import '../../../resources.dart';

import 'acp_install_state.dart';
import 'acp_observation_lease.dart';
import 'acp_values.dart';

/// `acpInstall` 的唯一 Dart owner。
///
/// 安装是共享资产而不是账号字段：它拥有独立 revision、独立 topic 与独立命令，不复用
/// Settings 或 `acpAuth` 的水位，观察者可以多人共享同一操作。观察按 owner/revision
/// 单调收敛，领域未加载时接受首个快照（含 revision 0），之后只接受更高水位。
///
/// 开始受理与安装终态是两件事：准备命令只快速返回受理身份和受理时的 canonical
/// 快照，进度与终态全部由 topic 推进。下载 100%、进程退出或模板声明能力都不是就绪，
/// 就绪也不是账号已保存或已认证。同一 provider/宿主目标同时最多一个操作；重复 start
/// 在到达 transport 之前就被拒绝为 [StudioFailureCode.busy]，不会创建第二个任务。
///
/// 取消命中当前 operation 身份，走独立通道，不受 start 受理等待或本地 busy 影响；
/// 在途取消以 provider + 目标 operation 为键去重，不同目标允许并行。未知结果不自动
/// 重发，关闭失败如实保留。
abstract interface class AcpInstallRepository {
  /// 唯一 canonical 发布源；观察者各自持有租约。
  ReadonlyLatestValue<AcpInstallObservation> get state;

  /// 首次需求打开 `acpInstall` 订阅并等待 ready；之后复用同一订阅。
  Future<void> synchronize();

  /// 显式重连被替换或失败的订阅；不联网、不重放已受理的准备。
  Future<void> retrySync();

  /// 取得本页面自己的观察租约；重复调用共享同一订阅。
  AcpObservationLease<AcpInstallObservation> observe({
    void Function(AcpInstallObservation state)? onState,
    bool fireImmediately = true,
  });

  /// 具名有界读取：当前 canonical 安装快照。
  ///
  /// 只观察既有事实，不联网、不扫描、不启动下载。订阅仍是唯一发布源：读结果只交回
  /// 调用方，不会以迟到事实回退已发布的进度或终态。
  Future<AcpInstallSnapshot> readCanonical();

  /// 受理一次官方 server 准备；返回受理后的 canonical 快照（不是完成）。
  ///
  /// 返回快照中该 provider 的状态携带本次 operation 身份，调用方据此把结果绑定到
  /// 草稿（见 [AcpPreparationIntent]）。
  OperationTicket<AcpInstallSnapshot> prepare(AcpProvider provider);

  /// 取消该 provider 当前的操作。
  ///
  /// [targetOperationId] 必须来自 canonical 观察给出的操作身份；取消只影响共享资产
  /// 的当前操作，不删除安装目录，也不触及任何账号配置。
  OperationTicket<AcpInstallSnapshot> cancel(
    AcpProvider provider, {
    required String targetOperationId,
  });

  /// 封闭命令准入；不影响已受理的准备，仍由 [close] join。
  void seal();

  /// 封闭准入、取消并 join 在途任务；收束未完成时保持非终态而不是伪造 Clean。
  Future<CloseReport> close({DateTime? deadline});

  /// 在既有预算内重试未收束的资源；不重放下载或发布。
  Future<CloseReport> retryCleanup({DateTime? deadline});
}
