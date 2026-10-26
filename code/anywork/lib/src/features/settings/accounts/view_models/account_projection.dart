import 'dart:async';

import 'package:anywork_client/accounts.dart';
import 'package:anywork_client/account_usage.dart';
import 'package:anywork_client/studio_client.dart'
    show OperationPhase, OperationState, StudioFailure;

import '../state/account_presentations.dart';

/// The Connector supplies localized text, never business rules or reducers.
/// Keeping this value Dart-only also makes locale changes independent of form
/// identity and of the lifetime of the Widget carrying the form.
final class AccountStrings {
  const AccountStrings(this.values, {this.retryCount});
  const AccountStrings.empty() : values = const {}, retryCount = null;
  final Map<String, String> values;
  final String Function(int)? retryCount;
  String operator [](String key) => values[key] ?? '';
  String retryValue(int count) => retryCount?.call(count) ?? count.toString();
  String date(int? seconds) => seconds == null || seconds <= 0
      ? this['notChecked']
      : DateTime.fromMillisecondsSinceEpoch(seconds * 1000)
            .toLocal()
            .toString()
            .substring(0, 16);
}

/// No rounding, decimal, exponent or sign is accepted for token budgets.
int? positiveAccountInteger(String raw) {
  if (!RegExp(r'^[0-9]+$').hasMatch(raw)) return null;
  final value = int.tryParse(raw);
  return value != null && value > 0 ? value : null;
}

AccountIdentity domainIdentity(AccountDisplayKey key) =>
    key.kind == AccountKind.native
    ? NativeAccountIdentity(key.id)
    : AcpAccountIdentity(key.id);

AccountDisplayKey displayIdentity(AccountIdentity identity) =>
    AccountDisplayKey(
      kind: identity is NativeAccountIdentity
          ? AccountKind.native
          : AccountKind.acp,
      id: identity.accountId,
    );

AccountBilling displayBilling(BillingKind? billing) => switch (billing) {
  BillingKind.metered => AccountBilling.metered,
  BillingKind.subscription => AccountBilling.subscription,
  BillingKind.noCharge => AccountBilling.noCharge,
  _ => AccountBilling.unknown,
};

BillingKind domainBilling(AccountBilling billing) => switch (billing) {
  AccountBilling.metered => BillingKind.metered,
  AccountBilling.subscription => BillingKind.subscription,
  AccountBilling.noCharge => BillingKind.noCharge,
  AccountBilling.unknown => BillingKind.unknown,
};

String safeAccountError(Object error, AccountStrings strings) =>
    error is StudioFailure ? error.message : strings['failed'];

bool operationSaved(OperationState operation) =>
    operation.receipt != null &&
    operation.observed &&
    operation.durable &&
    operation.failurePhase == null;

String? operationMessage(OperationState operation, AccountStrings strings) =>
    operation.failurePhase == OperationPhase.unknownOutcome
    ? strings['unknownOutcome']
    : operation.failurePhase != null
    ? strings['saveFailed']
    : !operationSaved(operation)
    ? strings['awaitingObservation']
    : null;

/// Only releases this display demand. Admitted work remains SDK-owned.
void releaseAccountDemand(AccountDemand? demand) {
  if (demand == null) return;
  unawaited(
    demand.release().then<void>((_) {}, onError: (Object _, StackTrace _) {}),
  );
}

AccountUsagePresentation projectUsage(
  AccountSummary summary,
  AccountResource<Map<NativeAccountIdentity, AccountUsageObservation>> resource,
  Map<NativeAccountIdentity, StudioFailure> queryFailures,
  AccountStrings strings,
) {
  final identity = summary.identity as NativeAccountIdentity;
  final candidate = resource.value?[identity];
  final usage = candidate?.queryRevision == summary.usageQueryRevision
      ? candidate
      : null;
  final success = usage?.lastGood;
  final value = success?.value;
  final transport = queryFailures[identity];
  final stale = resource.stale;
  final error =
      transport?.message ??
      (stale ? strings['stale'] : resource.failure?.message) ??
      (usage?.failure == null ? null : strings['usageFailed']);
  return AccountUsagePresentation(
    phase: stale || error != null
        ? AccountQueryPhase.failed
        : switch (usage?.phase) {
            null || AccountUsagePhase.unchecked => AccountQueryPhase.idle,
            AccountUsagePhase.querying => AccountQueryPhase.loading,
            AccountUsagePhase.succeeded => AccountQueryPhase.ready,
            AccountUsagePhase.unsupported => AccountQueryPhase.unsupported,
            AccountUsagePhase.missingCredential =>
              AccountQueryPhase.missingCredential,
            AccountUsagePhase.failed => AccountQueryPhase.failed,
          },
    balanceHealth: value is AccountBalance
        ? (value.available
              ? AccountBalanceHealth.sufficient
              : AccountBalanceHealth.insufficient)
        : value is AccountSubscription &&
              value.quotas.any((quota) => quota.percentage >= 90)
        ? AccountBalanceHealth.insufficient
        : AccountBalanceHealth.unknown,
    balances: value is AccountBalance
        ? [
            for (final balance in value.balances)
              AccountCurrencyBalance(
                currency: balance.currency,
                total: balance.total.isEmpty ? null : balance.total,
                granted: balance.granted.isEmpty ? null : balance.granted,
                toppedUp: balance.toppedUp.isEmpty ? null : balance.toppedUp,
              ),
          ]
        : const [],
    quotas: value is AccountSubscription
        ? [
            for (final quota in value.quotas)
              AccountQuotaPresentation(
                label: switch (quota.window.kind) {
                  AccountQuotaWindowKind.fiveHour => strings['fiveHour'],
                  AccountQuotaWindowKind.weekly => strings['weekly'],
                  AccountQuotaWindowKind.mcpMonthly => strings['monthly'],
                  AccountQuotaWindowKind.other =>
                    quota.window.name ?? strings['quota'],
                },
                remaining:
                    quota.remaining?.toString() ??
                    '${(100 - quota.percentage).clamp(0, 100)}%',
                remainingFraction: ((100 - quota.percentage) / 100).clamp(0, 1),
                resetLabel: quota.resetAt == null
                    ? null
                    : strings.date(quota.resetAt),
                low: quota.percentage >= 90,
              ),
          ]
        : const [],
    hasLastGood: success != null,
    updatedLabel: success == null ? null : strings.date(success.checkedAt),
    error: error,
    canRefresh:
        summary.capabilities.queryUsage &&
        !stale &&
        usage?.phase != AccountUsagePhase.querying,
    canRetry:
        !stale &&
        (transport != null ||
            usage?.failure?.retryable == true ||
            resource.failure?.retryable == true),
  );
}
