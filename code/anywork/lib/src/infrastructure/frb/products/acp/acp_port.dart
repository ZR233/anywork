import 'package:anywork_client/acp_ports.dart';
import 'package:anywork_client/resources_ports.dart';

import '../../../../rust/api/studio/handlers/acp.dart' as native;
import '../../../../rust/api/studio/handlers/acp_install.dart'
    as native_install;
import '../../shared/bridge_failure.dart';
import '../../shared/exact_numbers.dart';
import 'acp_auth_feed.dart';
import 'acp_command_replies.dart';
import 'acp_converters.dart';
import 'acp_install_feed.dart';

/// ACP 的生产 port：两条独立资源通道 + 三个有界读取 + 四个显式命令。
///
/// 构造与装配没有任何原生调用：不打开订阅、不读快照、不启动官方程序、不触发检查或
/// 下载。认证与安装各自拥有 feed 身份、revision 与关闭报告，本类只把 typed 原生
/// 能力转成领域值，不缓存第二份 canonical，也不从本地布尔值推断登录或就绪。
final class FrbAcpPort implements AcpPort {
  const FrbAcpPort();

  @override
  Future<FeedConnection<AcpAuthFrame>> openAcpAuth() async {
    final connection = FrbAcpAuthConnection();
    // 打开失败直接向上抛：Repository 负责把它归为 source 失败，不在此合成 Ready。
    await connection.opened;
    return connection;
  }

  @override
  Future<FeedConnection<AcpInstallFrame>> openAcpInstall() async {
    final connection = FrbAcpInstallConnection();
    await connection.opened;
    return connection;
  }

  @override
  Future<AcpAccountCatalog> readAccountCatalog() => bridgeQuery(
    () async =>
        acpAccountCatalogFromBridge(await native.loadAcpAccountCatalog()),
  );

  @override
  Future<AcpAuthSnapshot> readAuthState() => bridgeQuery(
    () async => acpAuthSnapshotFromBridge(await native.readAcpAuthState()),
  );

  @override
  Future<AcpInstallSnapshot> readInstallState() => bridgeQuery(
    () async => acpInstallSnapshotFromBridge(
      await native_install.readAcpInstallState(),
    ),
  );

  @override
  Future<AcpAuthCommandReply> startAuth(AcpAuthStartRequest request) =>
      acpAuthCommand(
        () => native.startAcpAuth(
          operationId: request.operationId.value,
          accountId: request.accountId,
          // 冻结的连接代次按 u64 精确提交；越界在本地就是 invalidArgument。
          expectedConnectionRevision: nativeU64(
            request.expectedConnectionRevision,
            'ACP expected connection revision',
          ),
          action: acpAuthActionToBridge(request.action),
        ),
      );

  @override
  Future<AcpAuthCommandReply> cancelAuth(AcpAuthCancelRequest request) =>
      acpAuthCommand(
        () => native.cancelAcpAuth(
          operationId: request.operationId.value,
          accountId: request.accountId,
          // 取消必须命中当前操作身份；适配层不替换、也不排队到 start 之后。
          targetOperationId: request.targetOperationId.value,
        ),
      );

  @override
  Future<AcpInstallCommandReply> startInstall(AcpInstallStartRequest request) =>
      acpInstallCommand(
        () => native_install.startAcpInstall(
          operationId: request.operationId.value,
          // 宿主 target 由后端固定清单决定，客户端不提交平台或下载地址。
          provider: acpProviderToBridge(request.provider),
        ),
      );

  @override
  Future<AcpInstallCommandReply> cancelInstall(
    AcpInstallCancelRequest request,
  ) => acpInstallCommand(
    () => native_install.cancelAcpInstall(
      operationId: request.operationId.value,
      provider: acpProviderToBridge(request.provider),
      targetOperationId: request.targetOperationId.value,
    ),
  );
}
