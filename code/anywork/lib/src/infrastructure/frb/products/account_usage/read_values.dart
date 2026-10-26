import 'package:anywork_client/account_usage_ports.dart';

import '../../../../rust/api/studio/products/read/account_usage.dart' as native;
import '../../shared/exact_numbers.dart';
import '../../shared/read_converters.dart';
import '../identity_converters.dart';
import '../source_converters.dart';

AccountUsageReadHeader usageReadHeaderFromBridge(
  native.BridgeAccountUsageReadHeader value,
) => AccountUsageReadHeader(
  configFingerprint: readTextFromBridge(value.configFingerprint),
  usages: typedListFromBridge(value.usages),
);

AccountUsageRead usageReadFromBridge(native.BridgeAccountUsageRead value) =>
    AccountUsageRead(
      accountId: readTextFromBridge(value.accountId),
      revision: exactU64(value.revision, 'account usage revision'),
      updatedAt: exactI64(
        BigInt.from(value.updatedAt),
        'account usage updated Unix seconds',
      ),
      lastOperationId: readTextFromBridge(value.lastOperationId),
      state: usageResultReadFromBridge(value.state),
    );

AccountUsageResultRead usageResultReadFromBridge(
  native.BridgeAccountUsageResultRead value,
) => switch (value) {
  native.BridgeAccountUsageResultRead_Unsupported() =>
    const AccountUsageResultRead.unsupported(),
  native.BridgeAccountUsageResultRead_MissingCredential(:final message) =>
    AccountUsageResultRead.missingCredential(
      message: readTextFromBridge(message),
    ),
  native.BridgeAccountUsageResultRead_Ready(:final data) =>
    AccountUsageResultRead.ready(data: usageDataReadFromBridge(data)),
  native.BridgeAccountUsageResultRead_Failed(:final error) =>
    AccountUsageResultRead.failed(error: sourceErrorReadFromBridge(error)),
};

AccountUsageDataRead usageDataReadFromBridge(
  native.BridgeAccountUsageDataRead value,
) => switch (value) {
  native.BridgeAccountUsageDataRead_DeepSeekBalance(
    :final isAvailable,
    :final balances,
  ) =>
    AccountUsageDataRead.deepSeekBalance(
      isAvailable: isAvailable,
      balances: typedListFromBridge(balances),
    ),
  native.BridgeAccountUsageDataRead_ZhipuCodingPlan(
    :final level,
    :final limits,
  ) =>
    AccountUsageDataRead.zhipuCodingPlan(
      level: nullableReadText(level),
      limits: typedListFromBridge(limits),
    ),
};

BalanceRead balanceReadFromBridge(native.BridgeBalanceRead value) =>
    BalanceRead(
      currency: readTextFromBridge(value.currency),
      totalBalance: readTextFromBridge(value.totalBalance),
      grantedBalance: readTextFromBridge(value.grantedBalance),
      toppedUpBalance: readTextFromBridge(value.toppedUpBalance),
    );

QuotaWindowRead quotaWindowReadFromBridge(native.BridgeQuotaWindowRead value) =>
    switch (value) {
      native.BridgeQuotaWindowRead_FiveHour() =>
        const QuotaWindowRead.fiveHour(),
      native.BridgeQuotaWindowRead_Weekly() => const QuotaWindowRead.weekly(),
      native.BridgeQuotaWindowRead_McpMonthly() =>
        const QuotaWindowRead.mcpMonthly(),
      native.BridgeQuotaWindowRead_Other(:final field0) =>
        QuotaWindowRead.other(readTextFromBridge(field0)),
    };

QuotaLimitRead quotaLimitReadFromBridge(native.BridgeQuotaLimitRead value) =>
    QuotaLimitRead(
      window: quotaWindowReadFromBridge(value.window),
      percentage: value.percentage,
      currentValue: value.currentValue,
      total: value.total,
      remaining: value.remaining,
      nextResetAt: nullableI64(
        value.nextResetAt == null ? null : BigInt.from(value.nextResetAt!),
        'quota reset Unix seconds',
      ),
      usageDetails: typedListFromBridge(value.usageDetails),
    );

QuotaDetailRead quotaDetailReadFromBridge(native.BridgeQuotaDetailRead value) =>
    QuotaDetailRead(
      name: readTextFromBridge(value.name),
      currentValue: value.currentValue,
      total: value.total,
      percentage: value.percentage,
    );

AccountUsageEntryPage usageEntriesFromBridge(
  native.BridgeAccountUsageEntryPage value,
) => AccountUsageEntryPage(
  collection: collectionRefFromBridge(value.collection),
  offset: exactU64(value.offset, 'account usage entries offset'),
  items: value.items.map(entityRefFromBridge).toList(growable: false),
  nextOffset: nullableU64(
    value.nextOffset,
    'account usage entries next offset',
  ),
);

AccountUsageEntityRead usageEntityFromBridge(
  native.BridgeAccountUsageEntityRead value,
) => AccountUsageEntityRead(
  reference: entityRefFromBridge(value.reference),
  value: usageReadFromBridge(value.value),
);

AccountUsageReadPage usagesPageFromBridge(
  native.BridgeAccountUsageReadPage value,
) => AccountUsageReadPage(
  listId: exactU64(value.listId, 'account usage list'),
  offset: exactU64(value.offset, 'account usage offset'),
  total: exactU64(value.total, 'account usage total'),
  items: value.items.map(usageReadFromBridge).toList(growable: false),
  nextOffset: nullableU64(value.nextOffset, 'account usage next offset'),
);

BalanceReadPage balancesPageFromBridge(native.BridgeBalanceReadPage value) =>
    BalanceReadPage(
      listId: exactU64(value.listId, 'balance list'),
      offset: exactU64(value.offset, 'balance offset'),
      total: exactU64(value.total, 'balance total'),
      items: value.items.map(balanceReadFromBridge).toList(growable: false),
      nextOffset: nullableU64(value.nextOffset, 'balance next offset'),
    );

QuotaLimitReadPage quotaLimitsPageFromBridge(
  native.BridgeQuotaLimitReadPage value,
) => QuotaLimitReadPage(
  listId: exactU64(value.listId, 'quota limit list'),
  offset: exactU64(value.offset, 'quota limit offset'),
  total: exactU64(value.total, 'quota limit total'),
  items: value.items.map(quotaLimitReadFromBridge).toList(growable: false),
  nextOffset: nullableU64(value.nextOffset, 'quota limit next offset'),
);

QuotaDetailReadPage quotaDetailsPageFromBridge(
  native.BridgeQuotaDetailReadPage value,
) => QuotaDetailReadPage(
  listId: exactU64(value.listId, 'quota detail list'),
  offset: exactU64(value.offset, 'quota detail offset'),
  total: exactU64(value.total, 'quota detail total'),
  items: value.items.map(quotaDetailReadFromBridge).toList(growable: false),
  nextOffset: nullableU64(value.nextOffset, 'quota detail next offset'),
);
