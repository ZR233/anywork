import 'dart:async';

import 'package:anywork_client/configuration_ports.dart';
import 'package:anywork_client/models.dart';
import 'package:anywork_client/resources_ports.dart';

import 'configuration_fixture.dart';

const startCatalogOrigin = ProductReadOrigin(
  ownerEpoch: 'start-native-catalog',
  incarnation: 3,
);

/// Declared native credential. Read-ref revisions deliberately differ from the
/// two business clocks; Dart must not invent equality between those domains.
ConfigurationRoleReadTarget startSources({
  int pairRevision = 7,
  int catalogRevision = 40,
}) => ConfigurationRoleReadTarget(
  reference: ConfigurationRoleReadRef(entry: 50, revision: pairRevision),
  configuration: const ConfigurationReadTarget(
    origin: configurationFixtureOrigin,
    reference: ConfigurationReadRef(entry: 1, revision: 1),
  ),
  catalog: ModelCatalogReadTarget(
    origin: startCatalogOrigin,
    reference: ModelCatalogReadRef(entry: 8, revision: catalogRevision),
  ),
  stamp: ConfigProjectionStamp(
    settingsRevision: 1,
    modelCatalogRevision: catalogRevision + 100,
    closing: false,
  ),
);

final class ConfigurationStartFixture {
  ConfigurationStartFixture({ResourceBudget? budget})
    : owner = ConfigurationFixture(budget: budget) {
    owner.port.startOpen = (sources) {
      final call = ConfigurationStartOpen(opens.length, sources);
      opens.add(call);
      _openWaiters.remove(call.index)?.complete(call);
      return call.reply.future;
    };
  }

  final ConfigurationFixture owner;
  final opens = <ConfigurationStartOpen>[];
  final _openWaiters = <int, Completer<ConfigurationStartOpen>>{};
  ConfigurationRepository get repository => owner.repository;
  ResourceBudget get budget => owner.budget;

  Future<void> establish(ConfigurationRoleReadTarget sources) async {
    owner.port.snapshots[1] = AccountConfiguration(
      accountId: 'start-account',
      templateId: null,
      protocol: 'openai',
      name: 'Original account',
      baseUrl: 'https://start.invalid',
      hasBearerToken: true,
      billingKind: BillingKind.metered,
      bearerTokenEnv: null,
      billingKindOverride: null,
      disabledModels: const [],
      usageQueryRevision: 1,
      catalogId: 'original-catalog',
      customModels: const [],
      modelConnectionModes: const [],
      modelAutoCompactLimits: const [],
    );
    // Start needs the paired header, not an eagerly materialized account. Use
    // the public metadata demand to establish the real feed, then publish a new
    // metadata reference and really join the original immutable metadata pin.
    // This leaves only the feed in the shared budget before Start admission.
    final metadata = _StartSourceMetadata();
    owner.port.sourceStatusOpen = (reference, origin) async {
      if (reference != const ProductSourceStatusRef(entry: 9, revision: 1) ||
          origin != configurationFixtureOrigin)
        throw StateError('Unexpected Start bootstrap metadata target');
      return metadata;
    };
    final reading = repository.loadSourceStatus();
    final feed = await owner.port.opened(0);
    await feed.listened.future;
    owner.port.baseline(feed, 1, sources: sources);
    await reading;
    await feed.acknowledged(1);
    final released = Completer<void>();
    final releaseWatch = budget.watchAvailability(ResourceKind.readModel, () {
      if (!budget.usage.any(
            (item) => item.owner == 'configuration:source-status',
          ) &&
          !released.isCompleted)
        released.complete();
    });
    try {
      await owner.port.publishPair(sources, sourceStatusRevision: 2);
      await metadata.closed.future;
      if (!budget.usage.any(
            (item) => item.owner == 'configuration:source-status',
          ) &&
          !released.isCompleted)
        released.complete();
      await released.future;
    } finally {
      releaseWatch.cancel();
    }
  }

  Future<ConfigurationStartOpen> opened(int index) => index < opens.length
      ? Future.value(opens[index])
      : _openWaiters
            .putIfAbsent(index, Completer<ConfigurationStartOpen>.new)
            .future;
}

final class _StartSourceMetadata implements ProductSourceStatusReadConnection {
  final closed = Completer<void>();
  @override
  Future<ProductSourceStatusReadHeader> header() async =>
      const ProductSourceStatusReadHeader.ready(
        revision: 1,
        updatedAt: 1,
        lastCheckedAt: null,
      );
  @override
  Future<TextChunk> text(int fieldId, {int offset = 0, int maxBytes = 65536}) =>
      throw UnsupportedError('Ready metadata has no deferred text');
  @override
  void requestClose() {}
  @override
  Future<FeedCloseReport> close() async {
    if (!closed.isCompleted) closed.complete();
    return FeedCloseReport(
      feedId: 'start-source-metadata',
      outcome: const FeedCloseOutcome.clean(),
    );
  }

  @override
  Future<FeedCloseReport> retryClose() => close();
}

final class ConfigurationStartOpen {
  ConfigurationStartOpen(this.index, this.sources);
  final int index;
  final ConfigurationRoleReadTarget sources;
  final reply = Completer<ConfigurationStartReadConnection>();
  ConfigurationStartPin? native;

  ConfigurationStartPin accept({
    ConfigurationRoleReadTarget? header,
    Completer<FeedCloseReport>? closeReceipt,
  }) {
    final pin = ConfigurationStartPin('start-native-$index', header ?? sources);
    pin.closeReceipt = closeReceipt;
    native = pin;
    reply.complete(pin);
    return pin;
  }
}

final class ConfigurationStartResolve {
  ConfigurationStartResolve(this.query);
  final StartRouteQuery query;
  final reply = Completer<StartRouteRead>();
}

/// Only native frames/results and independent native-close receipts are
/// scripted here. No mode fallback, effort policy, query cache, CAS or retry
/// algorithm is implemented by this boundary. A Clean native receipt can be
/// returned while a Dart-admitted query is pending, so the real owner must join
/// that query itself rather than inheriting a fake's implementation of join.
final class ConfigurationStartPin implements ConfigurationStartReadConnection {
  ConfigurationStartPin(this.id, this.originalHeader);
  final String id;
  final ConfigurationRoleReadTarget originalHeader;
  final calls = <ConfigurationStartResolve>[];
  final _callWaiters = <int, Completer<ConfigurationStartResolve>>{};
  final headerEntered = Completer<void>();
  final closeStarted = Completer<void>();
  final retryStarted = Completer<void>();
  Completer<FeedCloseReport>? closeReceipt;
  FeedCloseOutcome outcome = const FeedCloseOutcome.clean();
  int requestCloseCalls = 0;
  int closeCalls = 0;
  int retryCloseCalls = 0;
  bool sealed = false;

  Future<ConfigurationStartResolve> called(int index) => index < calls.length
      ? Future.value(calls[index])
      : _callWaiters
            .putIfAbsent(index, Completer<ConfigurationStartResolve>.new)
            .future;

  void _admit() {
    if (sealed)
      throw const StudioFailure(
        code: StudioFailureCode.cancelled,
        message: 'The original native Start pin is sealed',
        retryable: false,
        correlationId: 'start-native-pin',
      );
  }

  @override
  Future<ConfigurationRoleReadTarget> header() async {
    _admit();
    if (!headerEntered.isCompleted) headerEntered.complete();
    return originalHeader;
  }

  @override
  Future<StartRouteRead> resolve(StartRouteQuery query) {
    _admit();
    final call = ConfigurationStartResolve(query);
    calls.add(call);
    _callWaiters.remove(calls.length - 1)?.complete(call);
    return call.reply.future;
  }

  @override
  void requestClose() {
    requestCloseCalls++;
    sealed = true;
  }

  @override
  Future<FeedCloseReport> close() {
    closeCalls++;
    requestClose();
    if (!closeStarted.isCompleted) closeStarted.complete();
    return closeReceipt?.future ??
        Future.value(FeedCloseReport(feedId: id, outcome: outcome));
  }

  @override
  Future<FeedCloseReport> retryClose() {
    retryCloseCalls++;
    requestClose();
    if (!retryStarted.isCompleted) retryStarted.complete();
    return closeReceipt?.future ??
        Future.value(FeedCloseReport(feedId: id, outcome: outcome));
  }
}
