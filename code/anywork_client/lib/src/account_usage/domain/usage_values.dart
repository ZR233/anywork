import 'package:freezed_annotation/freezed_annotation.dart';

import '../../../resources.dart';

part 'usage_values.freezed.dart';

@freezed
abstract class AccountUsageQueryIdentity with _$AccountUsageQueryIdentity {
  const factory AccountUsageQueryIdentity({required String accountId, required int usageQueryRevision, required String ownerEpoch}) = _AccountUsageQueryIdentity;
}

@freezed
abstract class AccountUsageValue with _$AccountUsageValue {
  const factory AccountUsageValue({required String configFingerprint, required List<AccountUsageRecord> usages}) = _AccountUsageValue;
}

@freezed
abstract class AccountUsageRecord with _$AccountUsageRecord {
  const factory AccountUsageRecord({required String accountId, required int revision, required int updatedAt, required String lastOperationId, required AccountUsageResult state}) = _AccountUsageRecord;
}

@freezed
sealed class AccountUsageResult with _$AccountUsageResult {
  const factory AccountUsageResult.unsupported() = UsageUnsupported;
  const factory AccountUsageResult.missingCredential({required String message}) = UsageMissingCredential;
  const factory AccountUsageResult.ready({required AccountUsageData data}) = UsageReady;
  const factory AccountUsageResult.failed({required SourceStateError error}) = UsageFailed;
}

@freezed
sealed class AccountUsageData with _$AccountUsageData {
  const factory AccountUsageData.deepSeekBalance({required bool isAvailable, required List<Balance> balances}) = DeepSeekBalance;
  const factory AccountUsageData.zhipuCodingPlan({required String? level, required List<QuotaLimit> limits}) = ZhipuCodingPlan;
}

/// Provider decimal text is not rounded or converted to double.
@freezed
abstract class Balance with _$Balance {
  const factory Balance({required String currency, required String totalBalance, required String grantedBalance, required String toppedUpBalance}) = _Balance;
}

@freezed
abstract class QuotaLimit with _$QuotaLimit {
  const factory QuotaLimit({required QuotaWindow window, required double percentage, required double? currentValue, required double? total, required double? remaining, required int? nextResetAt, required List<QuotaDetail> usageDetails}) = _QuotaLimit;
}

@freezed
sealed class QuotaWindow with _$QuotaWindow {
  const factory QuotaWindow.fiveHour() = FiveHourQuota;
  const factory QuotaWindow.weekly() = WeeklyQuota;
  const factory QuotaWindow.mcpMonthly() = McpMonthlyQuota;
  const factory QuotaWindow.other(String value) = OtherQuota;
}

@freezed
abstract class QuotaDetail with _$QuotaDetail {
  const factory QuotaDetail({required String name, required double? currentValue, required double? total, required double? percentage}) = _QuotaDetail;
}
