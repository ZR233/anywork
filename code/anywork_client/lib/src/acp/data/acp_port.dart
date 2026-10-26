/// ACP 两个 product topic 的 typed 原生能力，只供 Repository 与适配层装配使用。
library;

import '../../../resources_ports.dart' show FeedConnection;
import '../domain/acp_auth_state.dart';
import '../domain/acp_install_state.dart';
import '../domain/acp_values.dart';
import 'acp_frames.dart';
import 'acp_reads.dart';

/// 组合根与适配层之间的 ACP 能力边界。
///
/// 订阅各自最多两个未确认 Data delivery（含基线）。读取与命令都是有界的单次调用：
/// 适配层不得合成 source Ready、命令阶段、空业务值或登录/就绪结果，也不得把
/// transport 成功当作认证成功或安装完成。
///
/// 分发失败使用 CommandDispatchFailure 证据。调用命令后出现的普通 StudioFailure、
/// 错误码或消息都不证明被拒绝；原生成功但无法转换的回执必须保留真实回执
/// （committedButUnobserved 或 confirmedWithoutUsableReceipt），不能伪造 rejected。
///
/// 认证与安装是两条独立资源：本边界不合并它们的 revision、owner epoch 或取消通道。
abstract interface class AcpPort {
  /// 打开 `acpAuth` 订阅；首帧是该领域当前 canonical 基线。
  Future<FeedConnection<AcpAuthFrame>> openAcpAuth();

  /// 打开 `acpInstall` 订阅；首帧是该领域当前 canonical 基线。
  Future<FeedConnection<AcpInstallFrame>> openAcpInstall();

  /// 具名有界读取：只读接入模板目录，不联网、不启动程序、不检查凭据。
  Future<AcpAccountCatalog> readAccountCatalog();

  /// 具名有界读取：当前 canonical 认证快照，不触发检查也不启动进程。
  Future<AcpAuthSnapshot> readAuthState();

  /// 具名有界读取：当前 canonical 安装快照，不联网、不扫描、不启动下载。
  Future<AcpInstallSnapshot> readInstallState();

  /// 受理一次认证操作；快速返回受理身份与受理时快照，进展经 `acpAuth` 发布。
  Future<AcpAuthCommandReply> startAuth(AcpAuthStartRequest request);

  /// 取消当前认证操作；必须命中当前操作身份。
  Future<AcpAuthCommandReply> cancelAuth(AcpAuthCancelRequest request);

  /// 受理一次官方 server 准备；快速返回受理身份与受理时快照。
  Future<AcpInstallCommandReply> startInstall(AcpInstallStartRequest request);

  /// 取消当前准备操作；必须命中当前操作身份。
  Future<AcpInstallCommandReply> cancelInstall(AcpInstallCancelRequest request);
}
