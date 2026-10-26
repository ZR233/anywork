import 'dart:async';

import '../../../models.dart' show ModelSelection;
import '../../../resources_ports.dart';
import '../domain/configuration_state.dart';
import '../domain/start_route_values.dart';
import 'configuration_port.dart';
import 'configuration_read_fields.dart';

typedef _StartQueryKey = ({
  ConfigurationRoleReadTarget sources,
  StartRouteQuery query,
});

/// Start's named paired reads share the actual Configuration lifetime/budget.
/// This owner holds only in-flight query joins and original immutable pins, not
/// a second route/defaults catalog or a cache of failed/completed result futures.
final class ConfigurationStartReads {
  ConfigurationStartReads(this.port, this.lifetime);
  final ConfigurationPort port;
  final ResourceLifetime lifetime;
  final Map<
    ConfigurationRoleReadTarget,
    PinnedReadOwner<ConfigurationStartReadConnection>
  >
  _pins = {};
  final Map<_StartQueryKey, Future<StartRouteRead>> _queries = {};
  ConfigurationRoleReadTarget? _currentSources;

  /// Called at the original Configuration publication boundary. Retiring old
  /// pins lets admitted original-version reads finish, then really closes them.
  void retainOnly(ConfigurationRoleReadTarget? sources) {
    _currentSources = sources;
    for (final entry in List.of(_pins.entries)) {
      if (entry.key != sources) _retire(entry.key, entry.value);
    }
  }

  PinnedReadOwner<ConfigurationStartReadConnection> _pin(
    ConfigurationRoleReadTarget sources,
  ) {
    final previous = _pins[sources];
    if (previous != null && previous.accepting) return previous;
    final registered = Completer<void>();
    final pin = PinnedReadOwner<ConfigurationStartReadConnection>(
      lifetime: lifetime,
      owner: 'configuration:start-read',
      open: () async {
        await registered.future;
        return await port.openStartRead(sources);
      },
      request: (scope) => scope.requestClose(),
      closeNative: (scope) => scope.close(),
      retryNative: (scope) => scope.retryClose(),
    );
    // The cache entry precedes any external port call/reentrant query.
    _pins[sources] = pin;
    registered.complete();
    return pin;
  }

  void _retire(
    ConfigurationRoleReadTarget sources,
    PinnedReadOwner<ConfigurationStartReadConnection> pin,
  ) {
    pin.retire();
    if (identical(_pins[sources], pin)) _pins.remove(sources);
    // Unresolved pins/late opens stay registered in the same lifetime until
    // their native close and actual admitted calls join, including retryClose.
  }

  Future<StartRouteRead> read({
    required ConfigurationRoleReadTarget sources,
    required StartRouteQuery query,
  }) {
    lifetime.admit();
    final key = (sources: sources, query: query);
    _validateSources(key.sources);
    final pending = _queries[key];
    if (pending != null) return pending;
    final done = Completer<StartRouteRead>();
    _queries[key] = done.future;
    void forget() {
      if (identical(_queries[key], done.future))
        unawaited(_queries.remove(key));
    }

    unawaited(
      Future<StartRouteRead>.sync(
        () => lifetime.run('configuration:start-route', () async {
          final pin = _pin(key.sources);
          var completed = false;
          try {
            final value = await pin.use((scope) async {
              final header = await scope.header();
              if (header != key.sources)
                throw configurationProtocol(
                  'The Start scope returned another original configuration/catalog pair.',
                );
              if (lifetime.sealed) throw resourceCancelled;
              final result = await scope.resolve(key.query);
              if (lifetime.sealed) throw resourceCancelled;
              _validateResult(key, result);
              return result;
            });
            if (lifetime.sealed) throw resourceCancelled;
            completed = true;
            return value;
          } finally {
            if (!completed || !pin.accepting || _currentSources != key.sources)
              _retire(key.sources, pin);
          }
        }),
      ).then(
        (value) {
          forget();
          done.complete(value);
        },
        onError: (Object error, StackTrace stack) {
          lifetime.lastCause = error;
          lifetime.lastStack = stack;
          // Native/source failures remain failures with their original identity and
          // stack. Only the existing local permit error maps to its typed limit.
          forget();
          done.completeError(
            error is ResourceBudgetExceeded ? error.failure : error,
            stack,
          );
        },
      ),
    );
    return done.future;
  }
}

void _validateSources(ConfigurationRoleReadTarget sources) {
  final configuration = sources.configuration;
  final catalog = sources.catalog;
  if (sources.reference.entry < 0 ||
      sources.reference.revision < 0 ||
      configuration.origin.ownerEpoch.isEmpty ||
      configuration.origin.incarnation < 0 ||
      configuration.reference.entry < 0 ||
      configuration.reference.revision < 0 ||
      catalog.origin.ownerEpoch.isEmpty ||
      catalog.origin.incarnation < 0 ||
      catalog.reference.entry < 0 ||
      catalog.reference.revision < 0 ||
      sources.stamp.settingsRevision < 0 ||
      sources.stamp.modelCatalogRevision < 0) {
    throw configurationProtocol(
      'The Start pairing credential has invalid origins, refs or source clocks.',
    );
  }
  if (sources.stamp.closing) throw resourceCancelled;
  // Ref revisions and the two business clocks are independent. Only native's
  // lookup of sources.reference can prove their compatible original capture.
}

void _validateResult(_StartQueryKey key, StartRouteRead value) {
  if (value.sources != key.sources || value.query != key.query) {
    throw configurationProtocol(
      'The Start result changed its original pair, source clocks or query.',
    );
  }
  switch (key.query) {
    case ResolveStartRouteQuery(:final intent):
      if (value.intent != intent)
        throw configurationProtocol(
          'Start resolve changed its original editing intent.',
        );
    case SelectModelStartRouteQuery(:final intent, :final selected):
      if (value.intent.mode != intent.mode || value.intent.model != selected) {
        throw configurationProtocol(
          'The Start model suggestion belongs to another mode or selected model.',
        );
      }
    // Effort may be normalized/cleared by this original native suggestion.
    // Do not compare it to the input or reproduce default/selection policy.
  }
  final ModelSelection? selection = switch (value) {
    ReadyStartRouteRead(:final route) => route,
    UnavailableStartRouteRead(:final desired) => desired,
  };
  final explicitModel = value.intent.model;
  if (explicitModel != null &&
      selection != null &&
      selection.model != explicitModel) {
    throw configurationProtocol(
      'The Start route does not belong to its explicit model intent.',
    );
  }
}
