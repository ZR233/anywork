/// `acpAuth` 资源 owner：canonical 镜像、观察租约、认证命令与关闭语义。
library;

import '../../../operations.dart';
import '../../../resources.dart';

import 'acp_auth_state.dart';
import 'acp_observation_lease.dart';
import 'acp_values.dart';

/// `acpAuth` 的唯一 Dart owner。
///
/// 认证是独立版本域：观察按 owner/revision 单调收敛，领域未加载时接受首个快照
/// （含 revision 0），之后只接受更高水位；迟到或重复事实不回退状态，也不合成
/// “登录成功”。检查、登录与取消是显式命令，命令只快速返回受理身份，进展经同一
/// reducer 从 `acpAuth` topic 收敛；查询、订阅、页面进入与重建都不会启动外部程序，
/// 也不会产生认证动作。
///
/// 同一接入同一时刻最多一个操作：重复 start 在到达 transport 之前就被拒绝为
/// [StudioFailureCode.busy]，不会创建第二个进程。取消使用独立通道：只要 canonical
/// 观察给出当前 operation 身份，即使 start 的受理仍在等待也能提交取消；重复取消
/// 只允许一个在途意图。操作身份绑定账号 + 连接代次 + 完整意图，同一身份不能用于
/// 不同操作；旧的同 ID 结果不会套用到当前配置。
abstract interface class AcpAuthRepository {
  /// 唯一 canonical 发布源；观察者各自持有租约。
  ReadonlyLatestValue<AcpAuthObservation> get state;

  /// 首次需求打开 `acpAuth` 订阅并等待 ready；之后复用同一订阅。
  Future<void> synchronize();

  /// 显式重连被替换或失败的订阅；不重放任何已受理命令。
  Future<void> retrySync();

  /// 取得本页面自己的观察租约；重复调用共享同一订阅。
  ///
  /// [onState] 立即收到当前值（当 [fireImmediately] 为 true），之后收到每次发布。
  AcpObservationLease<AcpAuthObservation> observe({
    void Function(AcpAuthObservation state)? onState,
    bool fireImmediately = true,
  });

  /// 具名有界读取：当前 canonical 认证快照。
  ///
  /// 只读取既有事实，不启动检查、也不启动进程。订阅仍是唯一发布源：读结果只交回
  /// 调用方（诊断、进入前的初次读取），不会以迟到或外来事实改写 canonical 状态。
  Future<AcpAuthSnapshot> readCanonical();

  /// 具名有界读取：只读接入模板目录（含固定受管版本与安装资格）。
  ///
  /// 不缓存为第二事实源，也不联网。
  Future<AcpAccountCatalog> readCatalog();

  /// 连接检查：initialize + 空工作区 `session/new` 探测，不发送 prompt。
  ///
  /// [expectedConnectionRevision] 必须在提交前冻结；运行期会拒绝已撤代的连接身份。
  OperationTicket<AcpAuthSnapshot> check({
    required String accountId,
    required int expectedConnectionRevision,
  });

  /// 按服务端实际宣告的 agent 方法登录。
  ///
  /// 缺少 methodId 是本地参数错误，不会创建操作。
  OperationTicket<AcpAuthSnapshot> authenticate({
    required String accountId,
    required int expectedConnectionRevision,
    required String methodId,
  });

  /// 取消指定接入当前的操作。
  ///
  /// [targetOperationId] 必须来自 canonical 观察给出的操作身份；取消不排队在 start
  /// 之后，也不受本地 busy 标志影响。
  OperationTicket<AcpAuthSnapshot> cancel({
    required String accountId,
    required String targetOperationId,
  });

  /// 封闭命令准入；不影响已受理的操作，仍由 [close] join。
  void seal();

  /// 封闭准入、取消并 join 在途操作；失败如实保留，不伪造 Clean。
  Future<CloseReport> close({DateTime? deadline});

  /// 在既有预算内重试未收束的资源；不重放业务命令。
  Future<CloseReport> retryCleanup({DateTime? deadline});
}
