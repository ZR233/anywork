import '../../accounts/domain/account_identity.dart';
import '../../accounts/domain/account_values.dart';
import '../../accounts/domain/accounts_repository.dart';
import '../../contracts/stamps.dart';
import '../../commands/mutation_board.dart';
import '../../models/acp_models.dart';
import '../../models/acp_install_models.dart';
import '../../observation/latest_value.dart';

abstract interface class AcpService {
  ValueObservation<AcpAccountCatalogView> get templates;
  ValueObservation<AccountResource<AcpAuthSnapshotView>> get auth;
  ValueObservation<AccountResource<AcpInstallSnapshotView>> get install;
  Future<void> loadTemplates();
  AccountDemand observeAuth();
  AccountDemand observeInstall();

  /// Save and remove return this operation's frozen failure after admission;
  /// errors before admission still throw. A normal return may still be pending.
  Future<OperationState> save(
    AcpAccountUpdateView account, {
    DraftStamp? draft,
  });
  Future<OperationState> remove(AcpAccountIdentity identity);

  /// 已准入保存失败交回同一操作；确认保存后才检查，两个结果独立。
  /// 尚未准入的错误仍抛出，不自动重发未知结果的保存。
  Future<AcpSaveAndConnectResult> saveAndConnect(
    AcpAccountUpdateView account, {
    DraftStamp? draft,
  });
  Future<AcpAuthSnapshotView> check(AcpAccountIdentity identity);
  Future<AcpAuthSnapshotView> login(
    AcpAccountIdentity identity, {
    required String methodId,
  });
  Future<AcpAuthSnapshotView> cancelAuth(AcpAccountIdentity identity);
  Future<AcpInstallSnapshotView> prepare(AcpProviderView provider);
  Future<AcpInstallSnapshotView> cancelPreparation(AcpProviderView provider);
}
