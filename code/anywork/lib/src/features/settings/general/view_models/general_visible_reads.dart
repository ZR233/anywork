import 'dart:async';

import 'package:anywork_client/configuration.dart';
import 'package:anywork_client/models.dart';
import 'package:anywork_client/resources.dart';

import '../../view_models/read_values.dart';
import '../../view_models/visible_read_demand.dart';
import '../state/general_settings_state.dart';

/// Only the General VM's visible scalar demands. No mirror, reducer, editing,
/// business commands, transport access or resource-close ownership lives here.
final class GeneralVisibleReads {
  GeneralVisibleReads(this.configuration, this.models, this.changed) {
    for (final field in [GeneralReadField.general, GeneralReadField.webSearch, GeneralReadField.deepSeek]) {
      _configuration[field] = VisibleReadDemand(
        read: (target) async {
          final source = configuration.state.value;
          if (source.projection.stamp?.origin != target.$1 || source.projection.header?.reference != target.$2) return;
          switch (field) {
            case GeneralReadField.general: await configuration.loadGeneralSettings();
            case GeneralReadField.webSearch: await configuration.loadWebSearchSettings();
            case GeneralReadField.deepSeek: await configuration.loadDeepSeekSettings();
            default: throw StateError('Not a configured General field');
          }
        }, changed: (target, error, current) => _notify(field, error, current, _configuration[field]!.reading),
      );
    }
    for (final field in [GeneralReadField.webPolicy, GeneralReadField.deepSeekPolicy]) {
      _policies[field] = VisibleReadDemand(
        read: (target) async {
          final source = models.state.value;
          if (source.projection.stamp?.origin != target.$1 || source.projection.header?.reference != target.$2) return;
          if (field == GeneralReadField.webPolicy) { await models.loadWebSearch(); }
          else { await models.loadDeepSeekSearch(); }
        }, changed: (target, error, current) => _notify(field, error, current, _policies[field]!.reading),
      );
    }
    _configurationSource = VisibleReadDemand(read: (target) async {
      final source = configuration.state.value;
      if (source.projection.stamp?.origin == target.$1 && source.projection.header?.source.status == target.$2) {
        await configuration.loadSourceStatus();
      }
    }, changed: (target, error, current) => _notify(GeneralReadField.configurationSource, error, current, _configurationSource.reading));
    _modelSource = VisibleReadDemand(read: (target) async {
      final source = models.state.value;
      if (source.projection.stamp?.origin == target.$1 && source.projection.header?.source.status == target.$2) {
        await models.loadSourceStatus();
      }
    }, changed: (target, error, current) => _notify(GeneralReadField.modelSource, error, current, _modelSource.reading));
  }

  final ConfigurationRepository configuration;
  final ModelsRepository models;
  final void Function(GeneralReadField field, StudioFailure? error, bool current, bool reading, bool anyReading) changed;
  final _configuration = <GeneralReadField, VisibleReadDemand<(ProductReadOrigin, ConfigurationReadRef)>>{};
  final _policies = <GeneralReadField, VisibleReadDemand<(ProductReadOrigin, ModelCatalogReadRef)>>{};
  late final VisibleReadDemand<(ProductReadOrigin, ProductSourceStatusRef)> _configurationSource;
  late final VisibleReadDemand<(ProductReadOrigin, ProductSourceStatusRef)> _modelSource;
  final _bootstrapping = <GeneralReadField>{};
  bool _visible = false;
  bool _disposed = false;

  bool get pending => _bootstrapping.isNotEmpty || _configuration.values.any((job) => job.reading) ||
    _policies.values.any((job) => job.reading) || _configurationSource.reading || _modelSource.reading;

  void _notify(GeneralReadField field, StudioFailure? error, bool current, bool reading) =>
      changed(field, error, current, reading, pending);

  void visible(bool value) { _visible = value; refresh(); }

  void rememberInitialFailures() {
    final config = configuration.state.value;
    final model = models.state.value;
    for (final entry in _configuration.entries) {
      final key = switch (entry.key) {
        GeneralReadField.general => failedReadIdentity(config.general),
        GeneralReadField.webSearch => failedReadIdentity(config.webSearch),
        GeneralReadField.deepSeek => failedReadIdentity(config.deepSeekSearch),
        _ => null,
      };
      if (key != null) entry.value.remember(key);
    }
    for (final entry in _policies.entries) {
      final key = entry.key == GeneralReadField.webPolicy
        ? failedReadIdentity(model.webSearch) : failedReadIdentity(model.deepSeekSearch);
      if (key != null) entry.value.remember(key);
    }
    if (failedReadIdentity(config.sourceStatus) case final key?) _configurationSource.remember(key);
    if (failedReadIdentity(model.sourceStatus) case final key?) _modelSource.remember(key);
  }

  void refresh() {
    final config = configuration.state.value;
    final model = models.state.value;
    final configOrigin = config.projection.stamp?.origin;
    final configRef = config.projection.header?.reference;
    final modelOrigin = model.projection.stamp?.origin;
    final modelRef = model.projection.header?.reference;
    for (final entry in _configuration.entries) {
      entry.value.visible(false);
      final needed = switch (entry.key) {
        GeneralReadField.general => !isCurrentRead(config.general, configRef, configOrigin),
        GeneralReadField.webSearch => !isCurrentRead(config.webSearch, configRef, configOrigin),
        GeneralReadField.deepSeek => !isCurrentRead(config.deepSeekSearch, configRef, configOrigin),
        _ => false,
      };
      entry.value.target(configOrigin == null || configRef == null ? null : (configOrigin, configRef),
        needed: needed && !_bootstrapping.contains(entry.key));
      entry.value.visible(_visible);
    }
    for (final entry in _policies.entries) {
      entry.value.visible(false);
      final needed = entry.key == GeneralReadField.webPolicy
        ? !isCurrentRead(model.webSearch, modelRef, modelOrigin)
        : !isCurrentRead(model.deepSeekSearch, modelRef, modelOrigin);
      entry.value.target(modelOrigin == null || modelRef == null ? null : (modelOrigin, modelRef),
        needed: needed && !_bootstrapping.contains(entry.key));
      entry.value.visible(_visible);
    }
    final configStatus = config.projection.header?.source.status;
    _configurationSource.visible(false);
    _configurationSource.target(configOrigin == null || configStatus == null ? null : (configOrigin, configStatus),
      needed: !isCurrentRead(config.sourceStatus, configStatus, configOrigin) && !_bootstrapping.contains(GeneralReadField.configurationSource));
    _configurationSource.visible(_visible);
    final modelStatus = model.projection.header?.source.status;
    _modelSource.visible(false);
    _modelSource.target(modelOrigin == null || modelStatus == null ? null : (modelOrigin, modelStatus),
      needed: !isCurrentRead(model.sourceStatus, modelStatus, modelOrigin) && !_bootstrapping.contains(GeneralReadField.modelSource));
    _modelSource.visible(_visible);
  }

  void retry() {
    if (_disposed || !_visible) return;
    final config = configuration.state.value.projection;
    final model = models.state.value.projection;
    if (config.stamp == null || config.header?.reference == null) {
      _bootstrap(GeneralReadField.general, () async { await configuration.loadGeneralSettings(); });
      _bootstrap(GeneralReadField.webSearch, () async { await configuration.loadWebSearchSettings(); });
      _bootstrap(GeneralReadField.deepSeek, () async { await configuration.loadDeepSeekSettings(); });
    }
    if (model.stamp == null || model.header?.reference == null) {
      _bootstrap(GeneralReadField.webPolicy, () async { await models.loadWebSearch(); });
      _bootstrap(GeneralReadField.deepSeekPolicy, () async { await models.loadDeepSeekSearch(); });
    }
    if (config.stamp == null || config.header == null)
      _bootstrap(GeneralReadField.configurationSource, configuration.loadSourceStatus);
    if (model.stamp == null || model.header == null)
      _bootstrap(GeneralReadField.modelSource, models.loadSourceStatus);
    refresh();
    for (final job in _configuration.values) { job.retry(); }
    for (final job in _policies.values) { job.retry(); }
    _configurationSource.retry();
    _modelSource.retry();
  }

  void _bootstrap(GeneralReadField field, Future<void> Function() read) {
    if (!_bootstrapping.add(field)) return;
    _notify(field, null, true, true);
    // Reserve every missing field before the first read can synchronously
    // publish its newly opened source and reenter refresh().
    unawaited(Future<void>(() async {
      if (_disposed || !_visible) {
        _bootstrapping.remove(field);
        if (!_disposed) _notify(field, null, false, false);
        return;
      }
      await _finishBootstrap(field, read);
    }));
  }

  Future<void> _finishBootstrap(GeneralReadField field, Future<void> Function() read) async {
    StudioFailure? error;
    var hasResult = false;
    try { await read(); hasResult = true; }
    on StudioFailure catch (failure) { error = failure; hasResult = true; }
    finally {
      _bootstrapping.remove(field);
      if (!_disposed) {
        if (error != null) rememberInitialFailures();
        _notify(field, error, hasResult && (error == null ? _current(field) : !_current(field)), false);
        refresh();
      }
    }
  }

  bool _current(GeneralReadField field) {
    final config = configuration.state.value;
    final model = models.state.value;
    final origin = config.projection.stamp?.origin;
    final reference = config.projection.header?.reference;
    final modelOrigin = model.projection.stamp?.origin;
    final modelReference = model.projection.header?.reference;
    return switch (field) {
      GeneralReadField.general => isCurrentRead(config.general, reference, origin),
      GeneralReadField.webSearch => isCurrentRead(config.webSearch, reference, origin),
      GeneralReadField.deepSeek => isCurrentRead(config.deepSeekSearch, reference, origin),
      GeneralReadField.webPolicy => isCurrentRead(model.webSearch, modelReference, modelOrigin),
      GeneralReadField.deepSeekPolicy => isCurrentRead(model.deepSeekSearch, modelReference, modelOrigin),
      GeneralReadField.configurationSource => isCurrentRead(config.sourceStatus, config.projection.header?.source.status, origin),
      GeneralReadField.modelSource => isCurrentRead(model.sourceStatus, model.projection.header?.source.status, modelOrigin),
    };
  }

  void dispose() {
    _disposed = true;
    for (final job in _configuration.values) { job.dispose(); }
    for (final job in _policies.values) { job.dispose(); }
    _configurationSource.dispose();
    _modelSource.dispose();
  }
}
