import 'acp.dart';
import 'models.dart' show OperationId, SettingsCommandReply;

abstract interface class AcpPort {
  Future<AcpLocalDetectionCommandReply> startAcpLocalDetection({
    required OperationId operationId,
  });
  Future<AcpLocalDetectionCommandReply> cancelAcpLocalDetection({
    required OperationId operationId,
    required OperationId targetOperationId,
  });
  Future<AcpAccountCatalogView> loadAcpAccountCatalog();
  Future<SettingsCommandReply> saveAcpAccount(
    int revision,
    AcpAccountUpdateView account, {
    required OperationId operationId,
    required BigInt? expectedDocumentRevision,
  });
  Future<SettingsCommandReply> removeAcpAccount(
    int revision,
    String accountId, {
    required OperationId operationId,
    required BigInt expectedDocumentRevision,
  });
  Future<AcpAuthCommandReply> startAcpAuth({
    required OperationId operationId,
    required String accountId,
    required int expectedConnectionRevision,
    required AcpAuthActionView action,
  });
  Future<AcpAuthCommandReply> continueAcpAuth({
    required OperationId operationId,
    required String accountId,
    required int expectedConnectionRevision,
    required OperationId targetOperationId,
    required String methodId,
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
