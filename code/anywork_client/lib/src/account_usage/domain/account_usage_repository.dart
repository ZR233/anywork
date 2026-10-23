import '../../../operations.dart';
import '../../../resources.dart';
import 'usage_state.dart';
import 'usage_values.dart';

abstract interface class AccountUsageRepository {
  ReadonlyLatestValue<AccountUsageState> get state;
  ReadonlyLatestValue<Map<String, AccountUsageCheck>> get checks;
  Future<void> loadSourceStatus();
  Future<void> loadRecordsPage({int limit = 32});
  Future<AccountUsageRecord> load(String accountId);
  OperationTicket<AccountUsageRecord> check(String accountId);
  void setVisibleAccounts(Set<String> accountIds);
  void seal();
  Future<CloseReport> close({DateTime? deadline});
  Future<CloseReport> retryCleanup({DateTime? deadline});
}

/// A read-only runtime borrow of a repository-owned check, not serializable
/// state. The original ticket remains authoritative for progress and failures.
abstract interface class AccountUsageCheck {
  String get accountId;
  AccountUsageQueryIdentity? get identity;
  OperationTicket<AccountUsageRecord> get ticket;
}
