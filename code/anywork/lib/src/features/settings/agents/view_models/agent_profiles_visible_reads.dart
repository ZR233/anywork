import 'package:anywork_client/configuration.dart';
import 'package:anywork_client/models.dart';
import 'package:anywork_client/recovery.dart';
import 'package:anywork_client/resources.dart';

import '../../view_models/collection_values.dart';
import '../../view_models/read_values.dart';
import '../../view_models/visible_read_demand.dart';
import '../state/agent_profiles_state.dart';

final class AgentProfilesVisibleReads {
  AgentProfilesVisibleReads(this.configuration, this.models, this.recovery, this.changed) {
    _profiles = VisibleReadDemand(read: (key) async {
      final value = configuration.profiles.value;
      if (_profileKey != key) return;
      await Future.wait<void>([
        if (!_hasPage(value.profiles, key.$1)) configuration.loadProfilesPage(),
        if (!isCurrentRead(value.diagnostics, key.$2, key.$1)) configuration.loadProfileDiagnostics().then((_) {}),
      ]);
    }, changed: (key, error, current) => changed(AgentProfilesReadField.profiles, error, current, _profiles.reading));
    _configuration = VisibleReadDemand(read: (key) async {
      final value = configuration.state.value;
      if (_configurationKey != key) return;
      await Future.wait<void>([
        if (!_hasPage(value.accounts, key.$1)) configuration.loadAccountsPage(),
      ]);
    }, changed: (key, error, current) => changed(AgentProfilesReadField.configuration, error, current, _configuration.reading));
    _models = VisibleReadDemand(read: (key) async {
      if (_modelKey == key) await models.loadAccountsPage();
    }, changed: (key, error, current) => changed(AgentProfilesReadField.models, error, current, _models.reading));
    _recovery = VisibleReadDemand(read: (key) async {
      if (_recoveryKey == key) await recovery.loadIssuesPage();
    }, changed: (key, error, current) => changed(AgentProfilesReadField.recovery, error, current, _recovery.reading));
    for (final field in [AgentProfilesReadField.profilesSource, AgentProfilesReadField.configurationSource,
      AgentProfilesReadField.modelSource, AgentProfilesReadField.recoverySource]) {
      _sources[field] = VisibleReadDemand(read: (key) async {
        if (_sourceKey(field) != key) return;
        switch (field) {
          case AgentProfilesReadField.profilesSource: await configuration.loadProfilesSourceStatus();
          case AgentProfilesReadField.configurationSource: await configuration.loadSourceStatus();
          case AgentProfilesReadField.modelSource: await models.loadSourceStatus();
          case AgentProfilesReadField.recoverySource: await recovery.loadSourceStatus();
          default: throw StateError('Not a Profiles source field');
        }
      }, changed: (key, error, current) {
        final reading = _sources[field]!.reading;
        // Settle the old demand before publishing, so a reentrant explicit
        // retry cannot be consumed by the previous request's completion.
        if (field == AgentProfilesReadField.configurationSource && !reading && _configurationRetryKey == key) _configurationRetryKey = null;
        changed(field, error, current, reading);
      });
    }
  }
  final ConfigurationRepository configuration;
  final ModelsRepository models;
  final RecoveryRepository recovery;
  final void Function(AgentProfilesReadField, StudioFailure?, bool, bool) changed;
  late final VisibleReadDemand<(ProductReadOrigin, AgentProfilesReadRef)> _profiles;
  late final VisibleReadDemand<(ProductReadOrigin, ConfigurationReadRef)> _configuration;
  late final VisibleReadDemand<(ProductReadOrigin, ModelCatalogReadRef)> _models;
  late final VisibleReadDemand<(ProductReadOrigin, RecoveryReadRef)> _recovery;
  final _sources = <AgentProfilesReadField, VisibleReadDemand<(ProductReadOrigin, ProductSourceStatusRef)>>{};
  (ProductReadOrigin, ProductSourceStatusRef)? _configurationRetryKey;
  bool _visible = false;
  (ProductReadOrigin, R)? _key<R extends Object>(ProductReadOrigin? origin, R? reference) =>
    origin == null || reference == null ? null : (origin, reference);
  (ProductReadOrigin, AgentProfilesReadRef)? get _profileKey => _key(configuration.profiles.value.projection.stamp?.origin,
    configuration.profiles.value.projection.header?.reference);
  (ProductReadOrigin, ConfigurationReadRef)? get _configurationKey => _key(configuration.state.value.projection.stamp?.origin,
    configuration.state.value.projection.header?.reference);
  (ProductReadOrigin, ModelCatalogReadRef)? get _modelKey => _key(models.state.value.projection.stamp?.origin, models.state.value.projection.header?.reference);
  (ProductReadOrigin, RecoveryReadRef)? get _recoveryKey => _key(recovery.state.value.projection.stamp?.origin, recovery.state.value.projection.header?.reference);
  (ProductReadOrigin, ProductSourceStatusRef)? _sourceKey(AgentProfilesReadField field) => switch (field) {
    AgentProfilesReadField.profilesSource => _key(configuration.profiles.value.projection.stamp?.origin, configuration.profiles.value.projection.header?.source.status),
    AgentProfilesReadField.configurationSource => _key(configuration.state.value.projection.stamp?.origin, configuration.state.value.projection.header?.source.status),
    AgentProfilesReadField.modelSource => _key(models.state.value.projection.stamp?.origin, models.state.value.projection.header?.source.status),
    AgentProfilesReadField.recoverySource => _key(recovery.state.value.projection.stamp?.origin, recovery.state.value.projection.header?.source.status),
    _ => null,
  };
  void visible(bool value) {
    _visible = value;
    if (!value) _configurationRetryKey = null;
    refresh();
  }
  void refresh() {
    if (_configurationRetryKey != _sourceKey(AgentProfilesReadField.configurationSource)) _configurationRetryKey = null;
    final profiles = configuration.profiles.value;
    final config = configuration.state.value;
    final model = models.state.value;
    final recoveryValue = recovery.state.value;
    _target(_profiles, _profileKey, !_hasPage(profiles.profiles, _profileKey?.$1) || !isCurrentRead(profiles.diagnostics, _profileKey?.$2, _profileKey?.$1));
    _target(_configuration, _configurationKey, !_hasPage(config.accounts, _configurationKey?.$1));
    _target(_models, _modelKey, !_hasPage(model.accounts, _modelKey?.$1));
    _target(_recovery, _recoveryKey, !_hasPage(recoveryValue.issues, _recoveryKey?.$1));
    for (final entry in _sources.entries) {
      final key = _sourceKey(entry.key);
      final value = switch (entry.key) {
        AgentProfilesReadField.profilesSource => profiles.sourceStatus,
        AgentProfilesReadField.configurationSource => config.sourceStatus,
        AgentProfilesReadField.modelSource => model.sourceStatus,
        AgentProfilesReadField.recoverySource => recoveryValue.sourceStatus,
        _ => null,
      };
      final retryConfiguration = entry.key == AgentProfilesReadField.configurationSource && key != null && _configurationRetryKey == key;
      _target(entry.value, key, retryConfiguration || !isCurrentRead(value, key?.$2, key?.$1));
    }
  }
  void _target<K extends Object>(VisibleReadDemand<K> value, K? key, bool needed) {
    value.visible(false); value.target(key, needed: needed); value.visible(_visible);
  }
  static bool _hasPage<T>(CollectionMirror<T> value, ProductReadOrigin? origin) => value is CurrentCollectionMirror<T> &&
    value.window.origin == origin && (displayCollectionRows(value).isNotEmpty || value.window.complete);
  void rememberInitialFailures() {
    final profiles = configuration.profiles.value;
    final config = configuration.state.value;
    final model = models.state.value;
    final recoveryValue = recovery.state.value;
    if (_profileKey case final key?) {
      if (_failedPage(profiles.profiles, key.$1) || failedReadIdentity(profiles.diagnostics) == key) _profiles.remember(key);
  }
    if (_configurationKey case final key?) {
      if (_failedPage(config.accounts, key.$1)) _configuration.remember(key);
    }
    if (_modelKey case final key?) { if (_failedPage(model.accounts, key.$1)) _models.remember(key); }
    if (_recoveryKey case final key?) { if (_failedPage(recoveryValue.issues, key.$1)) _recovery.remember(key); }
    for (final entry in _sources.entries) {
      final failed = switch (entry.key) {
        AgentProfilesReadField.profilesSource => failedReadIdentity(profiles.sourceStatus),
        AgentProfilesReadField.configurationSource => failedReadIdentity(config.sourceStatus),
        AgentProfilesReadField.modelSource => failedReadIdentity(model.sourceStatus),
        AgentProfilesReadField.recoverySource => failedReadIdentity(recoveryValue.sourceStatus),
        _ => null,
      };
      if (failed != null && failed == _sourceKey(entry.key)) entry.value.remember(failed);
    }
  }
  static bool _failedPage<T>(CollectionMirror<T> value, ProductReadOrigin origin) =>
    value is CurrentCollectionMirror<T> && value.window.origin == origin && value.window.error != null;
  void retry() {
    refresh(); _profiles.retry(); _configuration.retry(); _models.retry(); _recovery.retry();
    for (final value in _sources.values) { value.retry(); }
  }
  /// Explicit recovery over the original source key, even when last-known
  /// fields are materialized. The existing demand owns pending/inflight merge.
  void retryConfigurationSource((ProductReadOrigin, ProductSourceStatusRef) target) {
    final demand = _sources[AgentProfilesReadField.configurationSource]!;
    if (!_visible || _sourceKey(AgentProfilesReadField.configurationSource) != target) return;
    _configurationRetryKey = target;
    _target(demand, target, true);
    // An active read is joined; a different source key stays the sole next
    // demand. Publishing pending may hide/dispose or replace this owner.
    if (_visible && _configurationRetryKey == target && _sourceKey(AgentProfilesReadField.configurationSource) == target) demand.retry();
  }
  void dispose() {
    _visible = false; _configurationRetryKey = null;
    _profiles.dispose(); _configuration.dispose(); _models.dispose(); _recovery.dispose();
    for (final value in _sources.values) { value.dispose(); }
  }
}
