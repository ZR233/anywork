import 'acp.dart';
import 'models.dart' show OperationId, SettingsCommandReply;

abstract interface class AcpPort {
  Future<AcpAccountCatalogView> loadAcpAccountCatalog();
  Future<SettingsCommandReply> saveAcpAccount(
    int revision,
    AcpAccountUpdateView account, {
    required OperationId operationId,
  });
  Future<SettingsCommandReply> removeAcpAccount(
    int revision,
    String accountId, {
    required OperationId operationId,
  });
  Future<AcpAuthCommandReply> startAcpAuth({
    required OperationId operationId,
    required String accountId,
    required int expectedConnectionRevision,
    required AcpAuthActionView action,
  });
  Future<AcpAuthCommandReply> cancelAcpAuth({
    required OperationId operationId,
    required String accountId,
    required OperationId targetOperationId,
  });
  Future<AcpInstallCommandReply> startAcpInstall({
    required OperationId operationId,
    required AcpProviderView provider,
  });
  Future<AcpInstallCommandReply> cancelAcpInstall({
    required OperationId operationId,
    required AcpProviderView provider,
    required OperationId targetOperationId,
  });
}
