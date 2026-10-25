import 'package:freezed_annotation/freezed_annotation.dart';

import '../../../resources.dart';
import '../../../resources_ports.dart'
    show FeedConnection, ProductSourceStatusReadConnection;
import '../domain/usage_state.dart';
import 'usage_frames.dart';
import 'usage_reads.dart';

part 'account_usage_port.freezed.dart';

abstract interface class AccountUsagePort {
  Future<FeedConnection<AccountUsageFrame>> openAccountUsage();
  Future<AccountUsageReadConnection> openAccountUsageRead(
    AccountUsageReadRef reference, {
    required ProductReadOrigin origin,
  });
  Future<ProductSourceStatusReadConnection> openSourceStatus(
    ProductSourceStatusRef reference, {
    required ProductReadOrigin origin,
  });
  Future<AccountUsageCheckResult> check(
    String accountId, {
    required int expectedUsageQueryRevision,
  });
}

abstract interface class AccountUsageReadConnection {
  Future<AccountUsageReadHeader> header();
  Future<TextChunk> text(int fieldId, {int offset = 0, int maxBytes = 65536});
  Future<AccountUsageEntryPage> entries({int offset = 0, int limit = 32});
  Future<AccountUsageEntityRead> entity(ProductEntityRef reference);
  Future<ProductEntityRef?> lookupAccount(String accountId);
  Future<AccountUsageReadPage> usages(
    int listId, {
    int offset = 0,
    int limit = 32,
  });
  Future<BalanceReadPage> balances(
    int listId, {
    int offset = 0,
    int limit = 32,
  });
  Future<QuotaLimitReadPage> quotaLimits(
    int listId, {
    int offset = 0,
    int limit = 32,
  });
  Future<QuotaDetailReadPage> quotaDetails(
    int listId, {
    int offset = 0,
    int limit = 32,
  });
  void requestClose();
  Future<FeedCloseReport> close();
  Future<FeedCloseReport> retryClose();
}

@freezed
abstract class AccountUsageCheckResult with _$AccountUsageCheckResult {
  const factory AccountUsageCheckResult({
    required AccountUsageReadTarget target,
    required String accountId,
    required int usageQueryRevision,
  }) = _AccountUsageCheckResult;
}
