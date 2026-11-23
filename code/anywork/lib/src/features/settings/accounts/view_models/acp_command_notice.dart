import 'package:anywork_client/acp.dart';
import 'package:anywork_client/studio_client.dart'
    show StudioFailure, StudioFailureCode;

enum AcpCommandNoticeKind { authentication, configuration, remove }

/// Local command failure, bound to an explicit account/connection/operation.
/// Authentication progress never clears an unrelated configuration failure.
final class AcpCommandNotice {
  const AcpCommandNotice({
    required this.kind,
    required this.summary,
    this.detail,
    required this.accountId,
    required this.connectionRevision,
    this.operationId,
    this.clearOnVerified = true,
  });
  final AcpCommandNoticeKind kind;
  final String summary;
  final String? detail;
  final String accountId;
  final int connectionRevision;
  final String? operationId;
  final bool clearOnVerified;
}

AcpCommandNotice? visibleAcpCommandNotice(
  AcpCommandNotice? notice,
  AcpAccountSettingsView account,
  AcpAuthStateView auth, {
  AcpAuthActiveOperationView? activeOperation,
}) {
  if (notice == null ||
      notice.accountId != account.accountId ||
      notice.connectionRevision != account.connectionRevision) {
    return null;
  }
  if (notice.kind != AcpCommandNoticeKind.authentication) return notice;
  final activeId = activeOperation?.operationId ?? auth.operationId;
  if (notice.operationId != null) {
    return notice.operationId == activeId ? notice : null;
  }
  final busy = activeOperation != null || auth.isBusy;
  return busy || (notice.clearOnVerified && auth is AcpVerifiedState)
      ? null
      : notice;
}

bool isAcpAuthDuplicateWhileInFlight({
  required Object error,
  required String accountId,
  required int requestConnectionRevision,
  required AcpAccountSettingsView? account,
  required AcpAuthStateView auth,
  AcpAuthActiveOperationView? activeOperation,
}) =>
    error is StudioFailure &&
    error.code == StudioFailureCode.busy &&
    account?.accountId == accountId &&
    account?.connectionRevision == requestConnectionRevision &&
    (activeOperation != null || auth.isBusy);
