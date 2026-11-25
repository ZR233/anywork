import 'dart:async';

import 'package:anywork_client/accounts.dart';
import 'package:anywork_client/accounts_ports.dart';
import 'package:anywork_client/account_usage.dart';
import 'package:anywork_client/studio_client.dart';

import 'unused_account_ports.dart';
import 'test_app_lifecycle.dart';
import 'test_resource_owners.dart';

AccountSummary usageAccount(String id, {String? name, int? query = 1}) =>
    AccountSummary(
      identity: NativeAccountIdentity(id),
      name: name ?? id,
      isDefault: false,
      usageQueryRevision: query,
      credentialReady: true,
      capabilities: const AccountCapabilities(
        setDefault: false,
        edit: true,
        remove: true,
        queryUsage: true,
        syncModels: false,
        editModels: false,
        acpAuth: false,
      ),
    );

final class ScriptedUsageCall {
  ScriptedUsageCall(this.identity, this.queryRevision, this.operationId);
  final NativeAccountIdentity identity;
  final int queryRevision;
  final String operationId;
  final reply = Completer<AccountUsageFrame>();
}

/// Scripted backend facts only: it publishes Querying before the provider wait.
/// The real SDK owns observation, deduplication, stale rejection and diagnostics.
final class ScriptedUsageTransport extends UnusedAccountPorts
    implements StudioTransport {
  final List<ScriptedUsageCall> calls = [];
  final Map<(String, int), Completer<ScriptedUsageCall>> _entered = {};
  final Map<AccountObservationTarget, Set<_UsageFeed>> _feeds = {};
  final Map<NativeAccountIdentity, AccountUsageObservation> _values = {};
  List<AccountSummary> _accounts = const [];
  int _settingsRevision = 0;
  int _usageRevision = 0;
  AccountDomainFrame? _summaries;
  final Map<NativeAccountIdentity, AccountDetailFrame> _details = {};
  AccountUsageFrame? _usage;
  static const epoch = 'usage-owner';
  ResourceStamp _stamp(String source, int revision) =>
      ResourceStamp(resourceKey: source, ownerEpoch: epoch, revision: revision);

  AccountSummariesFrame publishAccounts(List<AccountSummary> accounts) {
    _accounts = List.unmodifiable(accounts);
    final frame = AccountSummariesFrame(
      _stamp('settings', ++_settingsRevision),
      accounts,
    );
    _summaries = frame;
    _emit(frame);
    return frame;
  }

  AccountDetailFrame publishDetails(String id, {int query = 1}) {
    final identity = NativeAccountIdentity(id);
    final frame = AccountDetailFrame(
      _stamp('settings', ++_settingsRevision),
      identity,
      NativeAccountDetails(
        identity: identity,
        name: id,
        protocol: 'open_ai',
        baseUrl: 'https://usage.example.test',
        hasBearerToken: true,
        credentialRequired: true,
        usageQueryRevision: query,
        customModels: const [],
      ),
    );
    _details[identity] = frame;
    _emit(frame);
    return frame;
  }

  Future<ScriptedUsageCall> started(String id, {int number = 1}) {
    final matches = calls
        .where((call) => call.identity.accountId == id)
        .toList();
    return matches.length >= number
        ? Future.value(matches[number - 1])
        : (_entered[(id, number)] ??= Completer<ScriptedUsageCall>()).future;
  }

  @override
  Future<AccountUsageFrame> queryAccountUsage(NativeAccountIdentity identity) {
    final query = _accounts
        .firstWhere((account) => account.identity == identity)
        .usageQueryRevision!;
    final number = calls.where((call) => call.identity == identity).length + 1;
    final call = ScriptedUsageCall(
      identity,
      query,
      'usage-${identity.accountId}-$query-$number',
    );
    calls.add(call);
    _emit(
      _usageFrame(
        identity,
        query,
        AccountUsagePhase.querying,
        operationId: call.operationId,
      ),
    );
    final gate = _entered.remove((identity.accountId, number));
    gate?.complete(call);
    return call.reply.future;
  }

  AccountUsageFrame _usageFrame(
    NativeAccountIdentity identity,
    int query,
    AccountUsagePhase phase, {
    String? operationId,
    AccountUsageSuccess? lastGood,
  }) {
    _usageRevision++;
    _values[identity] = AccountUsageObservation(
      identity: identity,
      queryRevision: query,
      revision: _usageRevision,
      phase: phase,
      operationId: operationId,
      checkedAt: phase == AccountUsagePhase.querying ? null : _usageRevision,
      lastGood: lastGood,
    );
    return _usage = AccountUsageFrame(
      _stamp('account-usage', _usageRevision),
      _values.values,
    );
  }

  void succeed(ScriptedUsageCall call) => call.reply.complete(
    _usageFrame(
      call.identity,
      call.queryRevision,
      AccountUsagePhase.unsupported,
      operationId: call.operationId,
    ),
  );

  void succeedWithQuota(ScriptedUsageCall call) {
    final checkedAt = _usageRevision + 1;
    call.reply.complete(
      _usageFrame(
        call.identity,
        call.queryRevision,
        AccountUsagePhase.succeeded,
        operationId: call.operationId,
        lastGood: AccountUsageSuccess(
          checkedAt: checkedAt,
          value: AccountSubscription(
            quotas: [
              AccountQuota(
                window: const AccountQuotaWindow(
                  AccountQuotaWindowKind.fiveHour,
                ),
                percentage: 0.25,
              ),
            ],
          ),
        ),
      ),
    );
  }

  AccountUsageFrame seedSuccess(
    NativeAccountIdentity identity, {
    int queryRevision = 1,
  }) {
    _usageRevision++;
    final checkedAt = _usageRevision;
    _values[identity] = AccountUsageObservation(
      identity: identity,
      queryRevision: queryRevision,
      revision: _usageRevision,
      phase: AccountUsagePhase.succeeded,
      operationId: 'previous-${identity.accountId}-$queryRevision',
      checkedAt: checkedAt,
      lastGood: AccountUsageSuccess(
        checkedAt: checkedAt,
        value: AccountSubscription(
          quotas: [
            AccountQuota(
              window: const AccountQuotaWindow(AccountQuotaWindowKind.fiveHour),
              percentage: 0.5,
            ),
          ],
        ),
      ),
    );
    return _usage = AccountUsageFrame(
      _stamp('account-usage', _usageRevision),
      _values.values,
    );
  }

  void fail(ScriptedUsageCall call) => call.reply.completeError(
    StateError('Usage transport failed: ${call.identity.accountId}'),
  );
  void _emit(AccountDomainFrame frame) {
    for (final feed in _feeds[frame.target]?.toList() ?? <_UsageFeed>[]) {
      feed.emit(frame);
    }
  }

  @override
  Future<AccountDomainObservation> openAccountObservation(
    AccountObservationTarget target, {
    required ClientResourceId resourceId,
  }) => ownTestAccountObservation(contentScope, resourceId, (operation) async {
    late final _UsageFeed feed;
    feed = _UsageFeed(operation.resourceId, () => _feeds[target]?.remove(feed));
    _feeds.putIfAbsent(target, () => {}).add(feed);
    final baseline = switch (target) {
      AccountSummariesTarget() => _summaries,
      AccountDetailTarget(:final identity) => _details[identity],
      AccountUsageTarget() => _usage,
      _ => throw StateError('Unexpected usage test target: ${target.key}'),
    };
    if (baseline != null) feed.emit(baseline);
    return feed;
  });

  @override
  Future<ProductTopicObservation> openProductTopic(
    ProductTopic topic, {
    required ClientResourceId resourceId,
  }) => ownTestProductTopic(contentScope, resourceId, const Stream.empty());
}

final class _UsageFeed implements AccountDomainObservation {
  _UsageFeed(this.resourceId, this.onClosed);
  @override
  final ClientResourceId resourceId;
  final void Function() onClosed;
  AccountDomainFrame? _latest;
  Completer<AccountDomainFrame?>? _pending;
  bool _closed = false;
  void emit(AccountDomainFrame frame) {
    if (_closed) return;
    final pending = _pending;
    if (pending == null) {
      _latest = frame;
    } else {
      _pending = null;
      pending.complete(frame);
    }
  }

  @override
  Future<AccountDomainFrame?> next() {
    if (_pending != null) throw StateError('Concurrent next');
    if (_closed) return Future.value(null);
    final latest = _latest;
    if (latest != null) {
      _latest = null;
      return Future.value(latest);
    }
    return (_pending = Completer<AccountDomainFrame?>()).future;
  }

  @override
  void requestClose() {
    _closed = true;
    _latest = null;
    _pending?.complete(null);
    _pending = null;
  }

  @override
  Future<void> close() async {
    requestClose();
    onClosed();
  }

  @override
  Future<void> retryClose() => close();
}
