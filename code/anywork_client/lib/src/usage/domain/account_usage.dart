import '../../accounts/domain/account_identity.dart';
import '../../accounts/domain/account_values.dart';
import '../../accounts/domain/accounts_repository.dart';
import '../../observation/latest_value.dart';
import '../../models/failure_models.dart';

enum AccountUsagePhase {
  unchecked,
  querying,
  succeeded,
  unsupported,
  missingCredential,
  failed,
}

enum AccountUsageFailureCode { configuration, query, cancelled, taskFailed }

final class AccountUsageFailure {
  const AccountUsageFailure({required this.code, required this.retryable});
  final AccountUsageFailureCode code;
  final bool retryable;
}

final class AccountUsageObservation {
  const AccountUsageObservation({
    required this.identity,
    required this.queryRevision,
    required this.revision,
    required this.phase,
    this.operationId,
    this.checkedAt,
    this.failure,
    this.lastGood,
  });
  final NativeAccountIdentity identity;
  final int queryRevision;
  final int revision;
  final AccountUsagePhase phase;
  final String? operationId;
  final int? checkedAt;
  final AccountUsageFailure? failure;
  final AccountUsageSuccess? lastGood;
}

final class AccountUsageSuccess {
  const AccountUsageSuccess({required this.checkedAt, required this.value});
  final int checkedAt;
  final AccountUsageValue value;
}

sealed class AccountUsageValue {
  const AccountUsageValue();
}

final class AccountBalance extends AccountUsageValue {
  AccountBalance({
    required this.available,
    required Iterable<AccountMoneyBalance> balances,
  }) : balances = List.unmodifiable(balances);
  final bool available;
  final List<AccountMoneyBalance> balances;
}

final class AccountMoneyBalance {
  const AccountMoneyBalance({
    required this.currency,
    required this.total,
    required this.granted,
    required this.toppedUp,
  });
  final String currency;
  final String total;
  final String granted;
  final String toppedUp;
}

final class AccountSubscription extends AccountUsageValue {
  AccountSubscription({this.level, required Iterable<AccountQuota> quotas})
    : quotas = List.unmodifiable(quotas);
  final String? level;
  final List<AccountQuota> quotas;
}

enum AccountQuotaWindowKind { fiveHour, weekly, mcpMonthly, other }

final class AccountQuotaWindow {
  const AccountQuotaWindow(this.kind, {this.name});
  final AccountQuotaWindowKind kind;
  final String? name;
}

final class AccountQuota {
  AccountQuota({
    required this.window,
    required this.percentage,
    this.used,
    this.total,
    this.remaining,
    this.resetAt,
    Iterable<AccountQuotaDetail> details = const [],
  }) : details = List.unmodifiable(details);
  final AccountQuotaWindow window;
  final double percentage;
  final double? used;
  final double? total;
  final double? remaining;
  final int? resetAt;
  final List<AccountQuotaDetail> details;
}

final class AccountQuotaDetail {
  const AccountQuotaDetail({
    required this.name,
    this.used,
    this.total,
    this.percentage,
  });
  final String name;
  final double? used;
  final double? total;
  final double? percentage;
}

abstract interface class AccountUsageRepository {
  /// Local query transport diagnostics, not provider health or fabricated
  /// canonical phases. Another account's success cannot erase this failure.
  ValueObservation<Map<NativeAccountIdentity, StudioFailure>> get queryFailures;
  ValueObservation<
    AccountResource<Map<NativeAccountIdentity, AccountUsageObservation>>
  >
  get state;

  /// Visibility starts only unattempted current query identities. Release stops
  /// new automatic work; already admitted requests retain application ownership.
  AccountDemand observeVisible();
  Future<void> refresh(NativeAccountIdentity identity);
}
