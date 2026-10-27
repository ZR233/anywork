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
  });
  final AcpCommandNoticeKind kind;
  final String summary;
  final String? detail;
  final String accountId;
  final int connectionRevision;
  final String? operationId;
}

AcpCommandNotice? visibleAcpCommandNotice(
  AcpCommandNotice? notice,
  AcpAccountSettingsView account,
  AcpAuthStateView auth,
) {
  if (notice == null ||
      notice.accountId != account.accountId ||
      notice.connectionRevision != account.connectionRevision) {
    return null;
  }
  if (notice.kind != AcpCommandNoticeKind.authentication) return notice;
  if (notice.operationId != null) {
    return notice.operationId == auth.operationId ? notice : null;
  }
  return auth.isBusy || auth is AcpVerifiedState ? null : notice;
}

bool isAcpAuthDuplicateWhileInFlight({
  required Object error,
  required String accountId,
  required int requestConnectionRevision,
  required AcpAccountSettingsView? account,
  required AcpAuthStateView auth,
}) =>
    error is StudioFailure &&
    error.code == StudioFailureCode.busy &&
    account?.accountId == accountId &&
    account?.connectionRevision == requestConnectionRevision &&
    auth.isBusy;
