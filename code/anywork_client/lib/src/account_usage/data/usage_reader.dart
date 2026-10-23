import '../../../resources.dart';
import '../domain/usage_values.dart';
import 'account_read_fields.dart';
import 'account_usage_port.dart';
import 'usage_reads.dart';

final class UsageReader {
  const UsageReader(this.scope);
  final AccountUsageReadConnection scope;
  Future<String> text(ReadText value) => readAccountText(value, scope.text);
  Future<String?> optional(ReadText? value) async => value == null ? null : await text(value);

  Future<AccountUsageRecord> record(AccountUsageRead value) async => AccountUsageRecord(
    accountId: await text(value.accountId), revision: value.revision, updatedAt: value.updatedAt,
    lastOperationId: await text(value.lastOperationId), state: await result(value.state),
  );

  Future<AccountUsageResult> result(AccountUsageResultRead value) async => switch (value) {
    UsageUnsupportedRead() => const AccountUsageResult.unsupported(),
    UsageMissingCredentialRead(:final message) => AccountUsageResult.missingCredential(message: await text(message)),
    UsageReadyRead(:final data) => AccountUsageResult.ready(data: await dataValue(data)),
    UsageFailedRead(:final error) => AccountUsageResult.failed(error: SourceStateError(code: await text(error.code), message: await text(error.message), retryable: error.retryable)),
  };

  Future<AccountUsageData> dataValue(AccountUsageDataRead value) async => switch (value) {
    DeepSeekBalanceRead(:final isAvailable, :final balances) => AccountUsageData.deepSeekBalance(isAvailable: isAvailable, balances: await balanceValues(balances)),
    ZhipuCodingPlanRead(:final level, :final limits) => AccountUsageData.zhipuCodingPlan(level: await optional(level), limits: await quotaValues(limits)),
  };

  Future<List<Balance>> balanceValues(TypedListRef reference) async {
    final values = await readAccountList<BalanceRead>(reference, (offset) async {
      final page = await scope.balances(reference.listId, offset: offset, limit: 32);
      return (listId: page.listId, offset: page.offset, total: page.total, items: page.items, nextOffset: page.nextOffset);
    });
    return List.unmodifiable([for (final value in values) Balance(currency: await text(value.currency), totalBalance: await text(value.totalBalance), grantedBalance: await text(value.grantedBalance), toppedUpBalance: await text(value.toppedUpBalance))]);
  }

  Future<List<QuotaLimit>> quotaValues(TypedListRef reference) async {
    final values = await readAccountList<QuotaLimitRead>(reference, (offset) async {
      final page = await scope.quotaLimits(reference.listId, offset: offset, limit: 32);
      return (listId: page.listId, offset: page.offset, total: page.total, items: page.items, nextOffset: page.nextOffset);
    });
    return List.unmodifiable([for (final value in values) QuotaLimit(window: await window(value.window), percentage: value.percentage, currentValue: value.currentValue, total: value.total, remaining: value.remaining, nextResetAt: value.nextResetAt, usageDetails: await details(value.usageDetails))]);
  }

  Future<QuotaWindow> window(QuotaWindowRead value) async => switch (value) {
    FiveHourQuotaRead() => const QuotaWindow.fiveHour(), WeeklyQuotaRead() => const QuotaWindow.weekly(), McpMonthlyQuotaRead() => const QuotaWindow.mcpMonthly(), OtherQuotaRead(:final value) => QuotaWindow.other(await text(value)),
  };

  Future<List<QuotaDetail>> details(TypedListRef reference) async {
    final values = await readAccountList<QuotaDetailRead>(reference, (offset) async {
      final page = await scope.quotaDetails(reference.listId, offset: offset, limit: 32);
      return (listId: page.listId, offset: page.offset, total: page.total, items: page.items, nextOffset: page.nextOffset);
    });
    return List.unmodifiable([for (final value in values) QuotaDetail(name: await text(value.name), currentValue: value.currentValue, total: value.total, percentage: value.percentage)]);
  }
}
