import '../../../configuration.dart';
import '../../../resources.dart';
import '../domain/usage_values.dart';
import 'account_read_fields.dart';

typedef UsageAccount = ({ProductReadOrigin origin, ProductEntityRef reference, AccountConfiguration value});

UsageAccount? usageAccount(ConfigurationState state, String id) {
  final projection = state.projection; final mirror = state.accounts;
  if (projection.sync.phase != ResourceSyncPhase.ready || projection.header?.reference == null || mirror is! CurrentCollectionMirror<AccountConfiguration> || mirror.window.origin != projection.stamp?.origin) return null;
  for (final row in mirror.window.rows.values) {
    if (row is ReadyReadValue<AccountConfiguration, ProductEntityRef> && row.current.origin == projection.stamp!.origin && row.current.value.accountId == id) return (origin: row.current.origin, reference: row.current.reference, value: row.current.value);
  }
  return null;
}

AccountUsageQueryIdentity usageIdentity(UsageAccount account) {
  if (account.value.usageQueryRevision < 0 || account.origin.ownerEpoch.isEmpty) throw accountDataProtocol('The account usage query identity is invalid.');
  return AccountUsageQueryIdentity(accountId: account.value.accountId, usageQueryRevision: account.value.usageQueryRevision, ownerEpoch: account.origin.ownerEpoch);
}

/// A concrete preparation attempt over one Configuration capability. Version
/// refs here are only read fences, never the business usage query identity.
final class UsagePreparation {
  UsagePreparation(this.configuration, this.accountId, ConfigurationState snapshot) {
    origin = snapshot.projection.stamp?.origin;
    final account = usageAccount(snapshot, accountId);
    expected = account == null ? null : usageIdentity(account);
    entry = account?.reference.entry;
    if (account == null) reference = snapshot.projection.header?.reference;
  }
  final AccountConfigurationReadSource configuration;
  final String accountId;
  ProductReadOrigin? origin;
  ConfigurationReadRef? reference;
  AccountUsageQueryIdentity? expected;
  int? entry;
  bool invalidated = false;

  void observe(ConfigurationState snapshot) {
    if (invalidated) return;
    final nextOrigin = snapshot.projection.stamp?.origin;
    if (nextOrigin != null) {
      if (origin != null && origin != nextOrigin) { invalidated = true; return; }
      origin ??= nextOrigin;
    }
    final account = usageAccount(snapshot, accountId);
    if (expected case final identity?) {
      if (account != null && usageIdentity(account) != identity) invalidated = true;
      final mirror = snapshot.accounts;
      if (mirror is CurrentCollectionMirror<AccountConfiguration> && mirror.window.origin == origin && (entry != null && !mirror.window.rows.containsKey(entry) || mirror.window.complete && !mirror.window.rows.values.any((row) => accountPrevious(row)?.value.accountId == accountId))) invalidated = true;
    } else {
      final next = snapshot.projection.header?.reference;
      if (reference != null && next != reference) invalidated = true;
      reference ??= next;
    }
  }

  bool compatible(ConfigurationState snapshot) {
    observe(snapshot);
    if (invalidated) return false;
    final account = usageAccount(snapshot, accountId);
    return account == null || expected == null || expected == usageIdentity(account);
  }

  Future<AccountUsageQueryIdentity> resolve() async {
    observe(configuration.state.value);
    if (invalidated) throw accountDataSuperseded;
    var account = usageAccount(configuration.state.value, accountId);
    if (account == null) {
      await configuration.loadAccount(accountId);
      observe(configuration.state.value);
      account = usageAccount(configuration.state.value, accountId);
    }
    if (invalidated || account == null || origin != account.origin) throw accountDataSuperseded;
    final identity = usageIdentity(account);
    if (expected != null && expected != identity) throw accountDataSuperseded;
    expected = identity;
    return identity;
  }
}
