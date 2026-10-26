import 'package:anywork_client/account_usage.dart';
import 'package:anywork_client/configuration.dart';
import 'package:anywork_client/models.dart';
import 'package:anywork_client/resources.dart';

import '../../view_models/collection_values.dart';
import '../../view_models/read_values.dart';
import '../../view_models/visible_read_demand.dart';
import '../state/accounts_state.dart';

/// The Accounts VM's finite set of visible reads, not a mirror or command owner.
final class AccountsVisibleReads {
  AccountsVisibleReads(
    this.configuration,
    this.models,
    this.usage,
    this.changed,
    this.templatesChanged,
  ) {
    _accounts = VisibleReadDemand(
      read: (key) async {
        if (_configurationKey == key) await configuration.loadAccountsPage();
      },
      changed: (key, error, current) => changed(
        AccountsReadField.accounts,
        error,
        current,
        _accounts.reading,
      ),
    );
    _default = VisibleReadDemand(
      read: (key) async {
        if (_configurationKey == key) {
          await configuration.loadDefaultAccountId();
        }
      },
      changed: (key, error, current) => changed(
        AccountsReadField.defaultAccount,
        error,
        current,
        _default.reading,
      ),
    );
    _models = VisibleReadDemand(
      read: (key) async {
        if (_modelKey == key) await models.loadAccountsPage();
      },
      changed: (key, error, current) =>
          changed(AccountsReadField.models, error, current, _models.reading),
    );
    _usage = VisibleReadDemand(
      read: (key) async {
        if (_usageKey == key) await usage.loadRecordsPage();
      },
      changed: (key, error, current) =>
          changed(AccountsReadField.usage, error, current, _usage.reading),
    );
    _templates = VisibleReadDemand(
      read: (key) async {
        if (_templateKey != key) return;
        final result = await models.loadTemplates();
        if (_templateKey == key) templatesChanged(result);
      },
      changed: (key, error, current) => changed(
        AccountsReadField.templates,
        error,
        current,
        _templates.reading,
      ),
    );
    for (final field in [
      AccountsReadField.configurationSource,
      AccountsReadField.modelSource,
      AccountsReadField.usageSource,
    ]) {
      _sources[field] = VisibleReadDemand(
        read: (key) async {
          if (_sourceKey(field) != key) return;
          switch (field) {
            case AccountsReadField.configurationSource:
              await configuration.loadSourceStatus();
            case AccountsReadField.modelSource:
              await models.loadSourceStatus();
            case AccountsReadField.usageSource:
              await usage.loadSourceStatus();
            default:
              throw StateError('Not an Accounts source field');
          }
        },
        changed: (key, error, current) =>
            changed(field, error, current, _sources[field]!.reading),
      );
    }
  }

  final ConfigurationRepository configuration;
  final ModelsRepository models;
  final AccountUsageRepository usage;
  final void Function(AccountsReadField, StudioFailure?, bool, bool) changed;
  final void Function(AccountTemplatesValue) templatesChanged;
  late final VisibleReadDemand<(ProductReadOrigin, ConfigurationReadRef)>
  _accounts;
  late final VisibleReadDemand<(ProductReadOrigin, ConfigurationReadRef)>
  _default;
  late final VisibleReadDemand<(ProductReadOrigin, ModelCatalogReadRef)>
  _models;
  late final VisibleReadDemand<(ProductReadOrigin, AccountUsageReadRef)> _usage;
  late final VisibleReadDemand<(ProductReadOrigin, AccountTemplatesReadRef)>
  _templates;
  final _sources =
      <
        AccountsReadField,
        VisibleReadDemand<(ProductReadOrigin, ProductSourceStatusRef)>
      >{};
  bool _visible = false;

  (ProductReadOrigin, ConfigurationReadRef)? get _configurationKey {
    final value = configuration.state.value.projection;
    final origin = value.stamp?.origin;
    final reference = value.header?.reference;
    return origin == null || reference == null ? null : (origin, reference);
  }

  (ProductReadOrigin, ModelCatalogReadRef)? get _modelKey {
    final value = models.state.value.projection;
    final origin = value.stamp?.origin;
    final reference = value.header?.reference;
    return origin == null || reference == null ? null : (origin, reference);
  }

  (ProductReadOrigin, AccountUsageReadRef)? get _usageKey {
    final value = usage.state.value.projection;
    final origin = value.stamp?.origin;
    final reference = value.header?.reference;
    return origin == null || reference == null ? null : (origin, reference);
  }

  (ProductReadOrigin, AccountTemplatesReadRef)? get _templateKey {
    final value = models.templates.value.projection;
    final origin = value.stamp?.origin;
    final reference = value.header?.reference;
    return origin == null || reference == null ? null : (origin, reference);
  }

  (ProductReadOrigin, ProductSourceStatusRef)? _sourceKey(
    AccountsReadField field,
  ) {
    final (origin, reference) = switch (field) {
      AccountsReadField.configurationSource => (
        configuration.state.value.projection.stamp?.origin,
        configuration.state.value.projection.header?.source.status,
      ),
      AccountsReadField.modelSource => (
        models.state.value.projection.stamp?.origin,
        models.state.value.projection.header?.source.status,
      ),
      AccountsReadField.usageSource => (
        usage.state.value.projection.stamp?.origin,
        usage.state.value.projection.header?.source.status,
      ),
      _ => (null, null),
    };
    return origin == null || reference == null ? null : (origin, reference);
  }

  void visible(bool visible) {
    _visible = visible;
    refresh();
  }

  void refresh() {
    final config = configuration.state.value;
    final model = models.state.value;
    final usageValue = usage.state.value;
    _target(
      _accounts,
      _configurationKey,
      !_hasPage(config.accounts, config.projection.stamp?.origin),
    );
    _target(
      _default,
      _configurationKey,
      !isCurrentRead(
        config.defaultAccountId,
        config.projection.header?.reference,
        config.projection.stamp?.origin,
      ),
    );
    _target(
      _models,
      _modelKey,
      !_hasPage(model.accounts, model.projection.stamp?.origin),
    );
    _target(
      _usage,
      _usageKey,
      !_hasPage(usageValue.usages, usageValue.projection.stamp?.origin),
    );
    _target(
      _templates,
      _templateKey,
      !isCurrentRead(
        models.templates.value.catalogs,
        models.templates.value.projection.header?.reference,
        models.templates.value.projection.stamp?.origin,
      ),
    );
    for (final entry in _sources.entries) {
      final key = _sourceKey(entry.key);
      final current = switch (entry.key) {
        AccountsReadField.configurationSource => isCurrentRead(
          config.sourceStatus,
          key?.$2,
          key?.$1,
        ),
        AccountsReadField.modelSource => isCurrentRead(
          model.sourceStatus,
          key?.$2,
          key?.$1,
        ),
        AccountsReadField.usageSource => isCurrentRead(
          usageValue.sourceStatus,
          key?.$2,
          key?.$1,
        ),
        _ => false,
      };
      _target(entry.value, key, !current);
    }
  }

  void _target<K extends Object>(
    VisibleReadDemand<K> demand,
    K? key,
    bool needed,
  ) {
    demand.visible(false);
    demand.target(key, needed: needed);
    demand.visible(_visible);
  }

  static bool _hasPage<T>(
    CollectionMirror<T> mirror,
    ProductReadOrigin? origin,
  ) =>
      mirror is CurrentCollectionMirror<T> &&
      mirror.window.origin == origin &&
      (displayCollectionRows(mirror).isNotEmpty || mirror.window.complete);

  void rememberInitialFailures() {
    // A successful old read must not mark a newer root as already attempted.
    // Only typed failure slots from the current source suppress an auto retry.
    final config = configuration.state.value;
    final model = models.state.value;
    final usageValue = usage.state.value;
    final templates = models.templates.value;
    if (_configurationKey case final key?) {
      if (_failedPage(config.accounts, key.$1)) _accounts.remember(key);
      if (failedReadIdentity(config.defaultAccountId) == key) {
        _default.remember(key);
      }
    }
    if (_modelKey case final key?) {
      if (_failedPage(model.accounts, key.$1)) _models.remember(key);
    }
    if (_usageKey case final key?) {
      if (_failedPage(usageValue.usages, key.$1)) _usage.remember(key);
    }
    if (_templateKey case final key?) {
      if (_failedPage(templates.templates, key.$1) ||
          failedReadIdentity(templates.catalogs) == key ||
          failedReadIdentity(templates.catalogRevision) == key) {
        _templates.remember(key);
      }
    }
    for (final entry in _sources.entries) {
      final failed = switch (entry.key) {
        AccountsReadField.configurationSource => failedReadIdentity(
          config.sourceStatus,
        ),
        AccountsReadField.modelSource => failedReadIdentity(model.sourceStatus),
        AccountsReadField.usageSource => failedReadIdentity(
          usageValue.sourceStatus,
        ),
        _ => null,
      };
      if (failed != null && failed == _sourceKey(entry.key)) {
        entry.value.remember(failed);
      }
    }
  }

  static bool _failedPage<T>(
    CollectionMirror<T> value,
    ProductReadOrigin origin,
  ) =>
      value is CurrentCollectionMirror<T> &&
      value.window.origin == origin &&
      value.window.error != null;

  void retry() {
    refresh();
    _accounts.retry();
    _default.retry();
    _models.retry();
    _usage.retry();
    _templates.retry();
    for (final value in _sources.values) {
      value.retry();
    }
  }

  void dispose() {
    _accounts.dispose();
    _default.dispose();
    _models.dispose();
    _usage.dispose();
    _templates.dispose();
    for (final value in _sources.values) {
      value.dispose();
    }
  }
}
