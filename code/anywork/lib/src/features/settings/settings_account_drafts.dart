import 'package:flutter/material.dart';

import 'package:anywork_client/studio_client.dart';

import '../../l10n/studio_l10n.dart';

enum AccountDraftMode { create, edit }

class AccountDraft {
  const AccountDraft({
    required this.mode,
    required this.originalId,
    required this.account,
  });

  factory AccountDraft.create(AccountSettingsView account) {
    return AccountDraft(
      mode: AccountDraftMode.create,
      originalId: account.id,
      account: account,
    );
  }

  factory AccountDraft.edit(AccountSettingsView account) {
    return AccountDraft(
      mode: AccountDraftMode.edit,
      originalId: account.id,
      account: account,
    );
  }

  final AccountDraftMode mode;
  final String originalId;
  final AccountSettingsView account;

  AccountDraft copyWith({AccountSettingsView? account}) {
    return AccountDraft(
      mode: mode,
      originalId: originalId,
      account: account ?? this.account,
    );
  }
}

/// 创建与切换模板的唯一草稿工厂。
///
/// 模板是创建的唯一数据源：名称、endpoint、协议、凭据提示与默认模型都来自
/// catalog descriptor，不按模板 ID、显示名或地址猜特性。模板身份变化时重建
/// 整组表单状态，既有账号的显示名、地址与模型声明由用户继续编辑。
abstract final class AccountDraftFactory {
  /// 以 catalog 模板创建草稿；模板不存在时返回 `null`，调用方展示目录错误。
  static AccountDraft? create({
    required AccountCatalogView catalog,
    required String templateId,
    required String accountId,
  }) {
    final account = _accountFromTemplate(
      catalog: catalog,
      templateId: templateId,
      accountId: accountId,
    );
    return account == null ? null : AccountDraft.create(account);
  }

  /// 切换模板：以新模板完整重建草稿，账号 ID 保持稳定。
  ///
  /// 未知模板不静默退回其它模板，也不改写当前协议。
  static AccountDraft? changeTemplate({
    required AccountDraft draft,
    required AccountCatalogView catalog,
    required String templateId,
    required String accountId,
  }) {
    final account = _accountFromTemplate(
      catalog: catalog,
      templateId: templateId,
      accountId: accountId,
    );
    return account == null ? null : draft.copyWith(account: account);
  }

  static AccountSettingsView? _accountFromTemplate({
    required AccountCatalogView catalog,
    required String templateId,
    required String accountId,
  }) {
    final template = catalog.template(templateId);
    if (template == null) {
      return null;
    }
    return template.createAccount(
      accountId,
      catalog.modelsFor(template.modelCatalogId),
    );
  }
}

String accountModelPriceLabel(AccountModelView model) {
  final first = model.priceTiers.firstOrNull;
  if (model.currency.isEmpty || first == null) return '';
  return '${model.currency} ${_trimNumber(first.input)}/${_trimNumber(first.output)}${model.priceTiers.length > 1 ? ' · …' : ''}';
}

String _trimNumber(double value) {
  if (value.truncateToDouble() == value) {
    return value.toStringAsFixed(0);
  }
  return value
      .toStringAsFixed(3)
      .replaceFirst(RegExp(r'0+$'), '')
      .replaceFirst(RegExp(r'\.$'), '');
}

String accountUsageSummary(
  BuildContext context,
  AccountSettingsView account,
  AccountUsageView? usage,
  bool loading,
) {
  if (loading && usage == null) {
    return context.l10n.settingsUsageCheckingShort;
  }
  if (usage == null) {
    return context.l10n.settingsUsageNotLoaded;
  }
  return switch (usage.state) {
    UnsupportedAccountUsageView() => context.l10n.settingsUsageUnsupported,
    MissingCredentialAccountUsageView() => context.l10n.settingsUsageMissingKey,
    FailedAccountUsageView() => context.l10n.settingsUsageFailed,
    ReadyAccountUsageView(:final data) => _readyAccountUsageSummary(
      context,
      data,
    ),
  };
}

String _readyAccountUsageSummary(
  BuildContext context,
  AccountUsageDataView data,
) {
  if (data case DeepSeekBalanceAccountUsageView(:final balance)) {
    final primary =
        balance.balances
            .where((item) => item.currency.toUpperCase() == 'CNY')
            .firstOrNull ??
        balance.balances.firstOrNull;
    return primary == null
        ? context.l10n.settingsUsageUnavailable
        : balance.balances
              .map(
                (item) => [
                  '${item.currency} ${item.totalBalance}',
                  '${context.l10n.settingsUsageGrantedBalance}: ${item.grantedBalance}',
                  '${context.l10n.settingsUsageToppedUpBalance}: ${item.toppedUpBalance}',
                ].join(' · '),
              )
              .join(' · ');
  }
  if (data case ZhipuCodingPlanAccountUsageView(:final codingPlan)) {
    final fiveHour = findQuotaLimit(codingPlan.limits, 'fiveHour');
    final weekly = findQuotaLimit(codingPlan.limits, 'weekly');
    if (fiveHour != null && weekly != null) {
      return '5h ${formatPercent(quotaRemainingPercent(fiveHour))} · 7d ${formatPercent(quotaRemainingPercent(weekly))}';
    }
  }
  return context.l10n.settingsUsageUnavailable;
}

String accountUsageMessage(
  BuildContext context,
  AccountSettingsView account,
  AccountUsageView usage,
) {
  return switch (usage.state) {
    MissingCredentialAccountUsageView(:final message) =>
      message.isEmpty ? context.l10n.settingsUsageApiKeyMissing : message,
    FailedAccountUsageView(:final message) =>
      message.isEmpty ? context.l10n.settingsUsageQueryFailed : message,
    UnsupportedAccountUsageView() =>
      context.l10n.settingsUsageUnsupportedForAccount(account.name),
    ReadyAccountUsageView() => context.l10n.settingsUsageUnavailable,
  };
}

String usageUpdatedLabel(BuildContext context, int? seconds) {
  if (seconds == null || seconds <= 0) {
    return context.l10n.settingsUsageNotChecked;
  }
  return context.l10n.settingsUsageUpdated(_formatUnixShort(seconds));
}

ZhipuQuotaLimitView? findQuotaLimit(
  List<ZhipuQuotaLimitView> limits,
  String window,
) {
  return limits.where((limit) => limit.window == window).firstOrNull;
}

double quotaRemainingPercent(ZhipuQuotaLimitView limit) {
  final remaining = limit.remaining;
  final total = limit.total;
  if (remaining != null && total != null && total > 0) {
    return _clampPercent((remaining / total) * 100);
  }
  return _clampPercent(100 - limit.percentage);
}

String quotaTitle(BuildContext context, ZhipuQuotaLimitView limit) {
  return switch (limit.window) {
    'fiveHour' => context.l10n.settingsUsageFiveHourQuota,
    'weekly' => context.l10n.settingsUsageWeeklyQuota,
    'mcpMonthly' => context.l10n.settingsUsageMcpQuota,
    _ => limit.label.isEmpty ? context.l10n.settingsUsageQuota : limit.label,
  };
}

String quotaDetail(BuildContext context, ZhipuQuotaLimitView limit) {
  final remaining = limit.remaining;
  final currentValue = limit.currentValue;
  final total = limit.total;
  final format = _quotaValueFormatter(limit);
  if (remaining != null && total != null) {
    return context.l10n.settingsUsageQuotaRemaining(
      format(remaining),
      format(total),
    );
  }
  if (currentValue != null && total != null) {
    return context.l10n.settingsUsageQuotaUsed(
      format(currentValue),
      format(total),
    );
  }
  return context.l10n.settingsUsagePercentRemaining(
    formatPercent(quotaRemainingPercent(limit)),
  );
}

/// 额度数值按后端 limit 类型选择展示格式。
///
/// 5 小时与每周额度由后端分类为 `TOKENS_LIMIT`，是词元用量，统一走共享词元 formatter；
/// MCP 月度由 `TIME_LIMIT` 分类、其余为未知窗口，不是词元，沿用计数紧凑格式，避免把
/// 时间/次数伪装成词元。
String Function(num value) _quotaValueFormatter(ZhipuQuotaLimitView limit) {
  if (limit.window == 'fiveHour' || limit.window == 'weekly') {
    return (value) => formatTokenCount(value.round());
  }
  return _formatCompactNumber;
}

String quotaResetLabel(BuildContext context, int? seconds) {
  if (seconds == null || seconds <= 0) {
    return '';
  }
  return context.l10n.settingsUsageReset(_formatUnixShort(seconds));
}

String formatToolUsage(ZhipuToolUsageDetailView detail) {
  final currentValue = detail.currentValue;
  final total = detail.total;
  if (currentValue != null && total != null) {
    return '${_formatCompactNumber((total - currentValue).clamp(0, total))}/${_formatCompactNumber(total)}';
  }
  if (currentValue != null) {
    return _formatCompactNumber(currentValue);
  }
  if (detail.percentage != null) {
    return formatPercent(_clampPercent(100 - detail.percentage!));
  }
  return '';
}

String _formatUnixShort(int seconds) {
  final date = DateTime.fromMillisecondsSinceEpoch(seconds * 1000);
  final hour = date.hour.toString().padLeft(2, '0');
  final minute = date.minute.toString().padLeft(2, '0');
  return '${date.month}/${date.day} $hour:$minute';
}

String _formatCompactNumber(num value) {
  final number = value.toDouble();
  final abs = number.abs();
  if (abs >= 1000000) {
    return '${_trimNumber(number / 1000000)}M';
  }
  if (abs >= 1000) {
    return '${_trimNumber(number / 1000)}K';
  }
  return _trimNumber(number);
}

String formatPercent(double value) => '${_trimNumber(value)}%';

double _clampPercent(double value) {
  if (!value.isFinite) {
    return 0;
  }
  if (value < 0) {
    return 0;
  }
  if (value > 100) {
    return 100;
  }
  return value;
}
