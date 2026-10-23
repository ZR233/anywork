import 'package:anywork_client/account_usage.dart';
import 'package:anywork_client/configuration.dart';
import 'package:anywork_client/operations.dart';
import 'package:anywork_client/resources.dart';

import '../../view_models/collection_values.dart';
import '../state/accounts_state.dart';

/// Borrows the Usage owner's actual tickets. This is only a presentation
/// projection: no check scheduling, OperationState writer or canonical store.
final class AccountUsageChecks {
  AccountUsageChecks(this.configuration, this.usage, this.changed) {
    final watch = usage.checks.watchLatest(_sync);
    _source = watch.observation;
    _sync(watch.value);
  }
  final ConfigurationRepository configuration;
  final AccountUsageRepository usage;
  final void Function(Map<String, AccountUsageCheckPresentation>) changed;
  Observation? _source;
  Map<String, AccountUsageCheck> _checks = const {};
  Set<String> _visibleIds = const {};
  Map<String, AccountUsageCheckPresentation> _snapshot = const {};
  final _observations = <OperationId, Observation>{};
  final _attempted = <OperationId>{};
  final _installing = <OperationId>{};
  final _issues = <OperationId, StudioFailure>{};
  int _generation = 0;
  bool _disposed = false;
  Map<String, AccountUsageCheckPresentation> get snapshot => _snapshot;

  bool _matches(AccountUsageCheck check) {
    if (!_visibleIds.contains(check.accountId)) return false;
    final source = configuration.state.value;
    final origin = source.projection.stamp?.origin;
    final account = currentCollectionRow(source.accounts, origin, (account) => account.accountId == check.accountId)?.value;
    if (account == null || origin == null) return false;
    final identity = check.identity;
    // Null is pure preparation, never proof of native acceptance.
    if (identity == null) return !check.ticket.state.value.acknowledged;
    return identity.accountId == account.accountId && identity.ownerEpoch == origin.ownerEpoch &&
      identity.usageQueryRevision == account.usageQueryRevision;
  }
  bool _needed(OperationId id) => _checks.values.any((check) => _matches(check) && check.ticket.state.value.id == id);

  void _sync(Map<String, AccountUsageCheck> checks) {
    if (_disposed) return;
    final generation = ++_generation;
    _checks = checks;
    final desired = {for (final check in checks.values) if (_matches(check)) check.ticket.state.value.id};
    for (final id in _observations.keys.where((id) => !desired.contains(id)).toList()) {
      _observations.remove(id)?.cancel();
    }
    _attempted.removeWhere((id) => !desired.contains(id));
    _issues.removeWhere((id, issue) => !desired.contains(id));
    for (final check in checks.values) {
      if (!_matches(check)) continue;
      final id = check.ticket.state.value.id;
      if (_attempted.contains(id) || !_installing.add(id)) continue;
      try {
        final watch = check.ticket.state.watchLatest((operation) { if (!_disposed) refresh(); });
        if (!_disposed && _needed(id) && !_observations.containsKey(id)) {
          _observations[id] = watch.observation; _attempted.add(id);
        } else { watch.observation.cancel(); }
      } on StudioFailure catch (error) {
        if (!_disposed && _needed(id)) { _issues[id] = error; _attempted.add(id); }
      } finally { _installing.remove(id); }
      if (_disposed) return;
      if (generation != _generation) { refresh(); return; }
    }
    _publish();
  }
  void _publish() {
    final next = <String, AccountUsageCheckPresentation>{};
    for (final entry in _checks.entries) {
      final check = entry.value;
      if (entry.key != check.accountId || !_matches(check)) continue;
      final operation = check.ticket.state.value;
      next[entry.key] = AccountUsageCheckPresentation(identity: check.identity,
        operation: operation, preparing: check.identity == null, observationError: _issues[operation.id]);
    }
    _snapshot = Map.unmodifiable(next);
    changed(_snapshot);
  }
  void refresh({bool retryObservations = false}) {
    if (_disposed) return;
    if (retryObservations) {
      for (final id in _issues.keys) { _attempted.remove(id); }
      _issues.clear();
    }
    _sync(usage.checks.value);
  }
  void visibleAccounts(Set<String> ids) {
    if (_disposed) return;
    _visibleIds = Set.unmodifiable(ids);
    refresh();
  }
  void dispose() {
    _disposed = true; _generation++; _source?.cancel();
    for (final observation in _observations.values) { observation.cancel(); }
    _observations.clear(); _attempted.clear(); _installing.clear(); _issues.clear(); _checks = const {};
  }
}
