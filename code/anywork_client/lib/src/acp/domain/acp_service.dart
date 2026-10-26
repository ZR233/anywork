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
  Future<OperationState> save(
    AcpAccountUpdateView account, {
    DraftStamp? draft,
  });
  Future<OperationState> remove(AcpAccountIdentity identity);
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
