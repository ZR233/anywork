import '../../accounts/domain/account_identity.dart';
import '../../accounts/domain/account_values.dart';
import '../../accounts/domain/accounts_repository.dart';
import '../../contracts/stamps.dart';
import '../../commands/mutation_board.dart';
import '../../models/acp_models.dart';
import '../../models/acp_install_models.dart';
import '../../models/acp_local_detection_models.dart';
import '../../observation/latest_value.dart';

/// ACP 账号卡片额度刷新的本地协调结算。
enum AcpUsageRefreshDisposition {
  /// 本次意图成为一次新受理的真实额度查询操作。
  started,

  /// 已共享或观察既有额度查询（本进程其他等待者或外部来源），不新发命令。
  joined,

  /// 意图在发出前被撤销：cancelPending，或连接/所有者身份已替换。
  cancelled,
}

/// 一次按账号与冻结连接修订登记、可撤销未发出意图的额度刷新请求。
abstract interface class AcpUsageRefreshRequest {
  /// 已准入或已决定观察既有额度操作时的本地结算；不是用量终态。
  ///
  /// 真实额度结果仍只来自 `acpAuth` 认证观察。已发出的尝试失败、结果未知
  /// 或同步失败时以原错误完成；不以新的操作身份自动重发。
  Future<AcpUsageRefreshDisposition> get result;

  /// 撤销尚未发出的意图并结算 [AcpUsageRefreshDisposition.cancelled]。
  ///
  /// 不影响已准入的业务操作或其他等待者；最后一个等待者离开后不保留
  /// 无界等待。
  void cancelPending();
}

abstract interface class AcpService {
  ValueObservation<AcpAccountCatalogView> get templates;
  ValueObservation<AccountResource<AcpAuthSnapshotView>> get auth;
  ValueObservation<AccountResource<AcpInstallSnapshotView>> get install;
  Future<void> loadTemplates();
  AccountDemand observeAuth();
  AccountDemand observeInstall();
  ValueObservation<AccountResource<AcpLocalDetectionSnapshotView>>
  get localDetection;
  AccountDemand observeLocalDetection();
  Future<AcpLocalDetectionCommandReply> startLocalDetection(
    OperationId operationId,
  );
  Future<AcpLocalDetectionCommandReply> cancelLocalDetection({
    required OperationId operationId,
    required OperationId targetOperationId,
  });

  /// Save and remove return this operation's frozen failure after admission;
  /// errors before admission still throw. A normal return may still be pending.
  Future<OperationState> save(
    AcpAccountUpdateView account, {
    required BigInt? expectedDocumentRevision,
    DraftStamp? draft,
  });
  Future<OperationState> remove(AcpAccountIdentity identity);

  /// 已准入保存失败交回同一操作；确认保存后才检查，两个结果独立。
  /// 尚未准入的错误仍抛出，不自动重发未知结果的保存。
  Future<AcpSaveAndConnectResult> saveAndConnect(
    AcpAccountUpdateView account, {
    required BigInt? expectedDocumentRevision,
    DraftStamp? draft,
  });
  Future<AcpAuthSnapshotView> check(AcpAccountIdentity identity);
  Future<AcpAuthSnapshotView> queryUsage(AcpAccountIdentity identity);

  /// 为账号卡片登记一次额度刷新意图，按冻结的 [connectionRevision] 限定资格。
  ///
  /// 同账号同连接已有额度查询时共享原查询；其他认证操作在途时等待其结算，
  /// 仅在来源、账号与连接仍匹配时至多准入一次。失败、需要准备或需要登录
  /// 不伪造成功，也不自动安装或登录。
  AcpUsageRefreshRequest requestUsageRefresh(
    AcpAccountIdentity identity, {
    required int connectionRevision,
  });

  Future<AcpAuthSnapshotView> login(
    AcpAccountIdentity identity, {
    required String methodId,
  });
  Future<AcpAuthSnapshotView> cancelAuth(AcpAccountIdentity identity);
  Future<AcpInstallSnapshotView> prepare(AcpProviderView provider);
  Future<AcpInstallSnapshotView> cancelPreparation(AcpProviderView provider);
}
