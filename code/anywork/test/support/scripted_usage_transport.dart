import 'dart:async';

import 'package:anywork_client/accounts.dart';
import 'package:anywork_client/accounts_ports.dart';
import 'package:anywork_client/account_usage.dart';
import 'package:anywork_client/studio_client.dart';

import 'unused_account_ports.dart';

AccountSummary usageAccount(String id, {String? name, int query = 1}) =>
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
  ScriptedUsageCall(this.identity, this.queryRevision);
  final NativeAccountIdentity identity;
  final int queryRevision;
  final reply = Completer<AccountUsageFrame>();
}

/// Scripted backend facts only: it publishes Querying before the provider wait.
/// The real SDK owns visibility, deduplication, stale rejection and diagnostics.
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
    final call = ScriptedUsageCall(identity, query);
    calls.add(call);
    final number = calls.where((call) => call.identity == identity).length;
    _emit(_usageFrame(identity, query, AccountUsagePhase.querying));
    final gate = _entered.remove((identity.accountId, number));
    gate?.complete(call);
    return call.reply.future;
  }

  AccountUsageFrame _usageFrame(
    NativeAccountIdentity identity,
    int query,
    AccountUsagePhase phase,
  ) {
    _usageRevision++;
    _values[identity] = AccountUsageObservation(
      identity: identity,
      queryRevision: query,
      revision: _usageRevision,
      phase: phase,
      checkedAt: phase == AccountUsagePhase.querying ? null : _usageRevision,
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
    ),
  );
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
    AccountObservationTarget target,
  ) async {
    late final _UsageFeed feed;
    feed = _UsageFeed(() => _feeds[target]?.remove(feed));
    _feeds.putIfAbsent(target, () => {}).add(feed);
    final baseline = switch (target) {
      AccountSummariesTarget() => _summaries,
      AccountUsageTarget() => _usage,
      _ => throw StateError('Unexpected usage test target: ${target.key}'),
    };
    if (baseline != null) feed.emit(baseline);
    return feed;
  }

  @override
  Stream<ProductTopicFrame> subscribeProductTopic(ProductTopic topic) =>
      const Stream.empty();
}

final class _UsageFeed implements AccountDomainObservation {
  _UsageFeed(this.onClosed);
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
}
