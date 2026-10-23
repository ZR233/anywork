import 'package:freezed_annotation/freezed_annotation.dart';

import '../../../resources.dart';

part 'usage_reads.freezed.dart';

@Freezed(toStringOverride: false)
abstract class AccountUsageReadHeader with _$AccountUsageReadHeader {
  const factory AccountUsageReadHeader({required ReadText configFingerprint, required TypedListRef usages}) = _AccountUsageReadHeader;
}

@Freezed(toStringOverride: false)
abstract class AccountUsageRead with _$AccountUsageRead {
  const factory AccountUsageRead({required ReadText accountId, required int revision, required int updatedAt, required ReadText lastOperationId, required AccountUsageResultRead state}) = _AccountUsageRead;
}

@Freezed(toStringOverride: false)
sealed class AccountUsageResultRead with _$AccountUsageResultRead {
  const factory AccountUsageResultRead.unsupported() = UsageUnsupportedRead;
  const factory AccountUsageResultRead.missingCredential({required ReadText message}) = UsageMissingCredentialRead;
  const factory AccountUsageResultRead.ready({required AccountUsageDataRead data}) = UsageReadyRead;
  const factory AccountUsageResultRead.failed({required SourceStateErrorRead error}) = UsageFailedRead;
}

@Freezed(toStringOverride: false)
sealed class AccountUsageDataRead with _$AccountUsageDataRead {
  const factory AccountUsageDataRead.deepSeekBalance({required bool isAvailable, required TypedListRef balances}) = DeepSeekBalanceRead;
  const factory AccountUsageDataRead.zhipuCodingPlan({required ReadText? level, required TypedListRef limits}) = ZhipuCodingPlanRead;
}

@Freezed(toStringOverride: false)
abstract class BalanceRead with _$BalanceRead {
  const factory BalanceRead({required ReadText currency, required ReadText totalBalance, required ReadText grantedBalance, required ReadText toppedUpBalance}) = _BalanceRead;
}

@Freezed(toStringOverride: false)
abstract class QuotaLimitRead with _$QuotaLimitRead {
  const factory QuotaLimitRead({required QuotaWindowRead window, required double percentage, required double? currentValue, required double? total, required double? remaining, required int? nextResetAt, required TypedListRef usageDetails}) = _QuotaLimitRead;
}

@Freezed(toStringOverride: false)
sealed class QuotaWindowRead with _$QuotaWindowRead {
  const factory QuotaWindowRead.fiveHour() = FiveHourQuotaRead;
  const factory QuotaWindowRead.weekly() = WeeklyQuotaRead;
  const factory QuotaWindowRead.mcpMonthly() = McpMonthlyQuotaRead;
  const factory QuotaWindowRead.other(ReadText value) = OtherQuotaRead;
}

@Freezed(toStringOverride: false)
abstract class QuotaDetailRead with _$QuotaDetailRead {
  const factory QuotaDetailRead({required ReadText name, required double? currentValue, required double? total, required double? percentage}) = _QuotaDetailRead;
}

@freezed
abstract class AccountUsageEntryPage with _$AccountUsageEntryPage {
  const factory AccountUsageEntryPage({required ProductCollectionRef collection, required int offset, required List<ProductEntityRef> items, required int? nextOffset}) = _AccountUsageEntryPage;
}

@Freezed(toStringOverride: false)
abstract class AccountUsageEntityRead with _$AccountUsageEntityRead {
  const factory AccountUsageEntityRead({required ProductEntityRef reference, required AccountUsageRead value}) = _AccountUsageEntityRead;
}

@Freezed(toStringOverride: false)
abstract class AccountUsageReadPage with _$AccountUsageReadPage {
  const factory AccountUsageReadPage({required int listId, required int offset, required int total, required List<AccountUsageRead> items, required int? nextOffset}) = _AccountUsageReadPage;
}

@Freezed(toStringOverride: false)
abstract class BalanceReadPage with _$BalanceReadPage {
  const factory BalanceReadPage({required int listId, required int offset, required int total, required List<BalanceRead> items, required int? nextOffset}) = _BalanceReadPage;
}

@Freezed(toStringOverride: false)
abstract class QuotaLimitReadPage with _$QuotaLimitReadPage {
  const factory QuotaLimitReadPage({required int listId, required int offset, required int total, required List<QuotaLimitRead> items, required int? nextOffset}) = _QuotaLimitReadPage;
}

@Freezed(toStringOverride: false)
abstract class QuotaDetailReadPage with _$QuotaDetailReadPage {
  const factory QuotaDetailReadPage({required int listId, required int offset, required int total, required List<QuotaDetailRead> items, required int? nextOffset}) = _QuotaDetailReadPage;
}
