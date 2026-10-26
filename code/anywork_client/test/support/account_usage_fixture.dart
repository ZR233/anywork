import 'dart:async';

import 'package:anywork_client/account_usage_ports.dart';
import 'package:anywork_client/configuration_ports.dart';
import 'package:anywork_client/models_ports.dart';
import 'package:anywork_client/operations_ports.dart';
import 'package:anywork_client/resources_ports.dart';

import 'configuration_command_fixture.dart';
import 'scripted_feed.dart';

const usageFixtureOrigin = ProductReadOrigin(
  ownerEpoch: 'usage-fixture-runtime',
  incarnation: 1,
);
const _entries = {'a': 10, 'b': 20};

AccountUsageRecord usageRecord(String id, int revision) => AccountUsageRecord(
  accountId: id,
  revision: revision,
  updatedAt: revision,
  lastOperationId: 'native-$id-$revision',
  state: const AccountUsageResult.unsupported(),
);

/// Real Configuration + Models targets + Usage owners. The ports below only
/// expose explicitly declared immutable native versions and controlled replies.
final class AccountUsageFixture {
  AccountUsageFixture({String clientId = 'usage-test'}) {
    operations = OperationRegistry(clientId: clientId, budget: budget);
    final assembly = createModelsRepository(
      port: _UnusedModels(),
      budget: budget,
    );
    models = assembly.repository;
    configuration = createConfigurationRepository(
      port: configPort,
      budget: budget,
      operations: operations,
      modelTargets: assembly.targets,
    );
    usage = createAccountUsageRepository(
      port: usagePort,
      budget: budget,
      operations: operations,
      configuration: configuration,
    );
  }
  final budget = ResourceBudget();
  final configPort = UsageConfigurationPort();
  final usagePort = ScriptedAccountUsagePort();
  late final OperationRegistry operations;
  late final ModelsRepository models;
  late final ConfigurationRepository configuration;
  late final AccountUsageRepository usage;
  int _configRevision = 0;
  int _usageRevision = 0;

  Future<void> establish(Map<String, int> accounts) async {
    configPort.versions[1] = Map.unmodifiable(accounts);
    final configRead = configuration.loadAccountsPage();
    await configPort.feed.listened.future;
    configPort.feed.emit(
      ConfigurationFrame.data(
        deliverySequence: 1,
        event: ConfigurationEvent.baseline(
          identity: _identity(
            configPort.feed.feedId,
            ProductResource.configuration,
          ),
          stamp: _stamp(1),
          value: ConfigurationBaseline(
            header: _configHeader(1),
            collection: _collection(1, accounts.length),
          ),
        ),
      ),
    );
    await configRead;
    await configPort.feed.acknowledged(1);
    _configRevision = 1;
    final usageRead = usage.loadRecordsPage();
    await usagePort.feed.listened.future;
    usagePort.versions[0] = const {};
    usagePort.feed.emit(
      AccountUsageFrame.data(
        deliverySequence: 1,
        event: AccountUsageEvent.baseline(
          identity: _identity(
            usagePort.feed.feedId,
            ProductResource.accountUsage,
          ),
          stamp: _stamp(0),
          value: AccountUsageBaseline(
            header: _usageHeader(0),
            collection: _collection(0, 0),
          ),
        ),
      ),
    );
    await usageRead;
    await usagePort.feed.acknowledged(1);
  }

  Future<void> configurationChanged(Map<String, int> accounts) async {
    final previous = _configRevision;
    final revision = ++_configRevision;
    final old = configPort.versions[previous]!;
    configPort.versions[revision] = Map.unmodifiable(accounts);
    configPort.feed.emit(
      ConfigurationFrame.data(
        deliverySequence: revision,
        event: ConfigurationEvent.change(
          stamp: _stamp(revision),
          baseRevision: previous,
          value: ConfigurationChange(
            header: _configHeader(revision),
            baseCollectionRevision: previous,
            collection: _collection(revision, accounts.length),
            upserted: [for (final id in accounts.keys) _entity(id, revision)],
            removedEntries: [
              for (final id in old.keys)
                if (!accounts.containsKey(id)) _entries[id]!,
            ],
          ),
        ),
      ),
    );
    await configPort.feed.acknowledged(revision);
    await configuration.loadAccountsPage();
  }

  void declareUsage(int revision, Map<String, AccountUsageRecord> records) =>
      usagePort.versions[revision] = Map.unmodifiable(records);

  Future<void> publishUsage(int revision) async {
    final previous = _usageRevision;
    final records = usagePort.versions[revision]!;
    final old = usagePort.versions[previous]!;
    usagePort.feed.emit(
      AccountUsageFrame.data(
        deliverySequence: revision + 1,
        event: AccountUsageEvent.change(
          stamp: _stamp(revision),
          baseRevision: previous,
          value: AccountUsageChange(
            header: _usageHeader(revision),
            baseCollectionRevision: previous,
            collection: _collection(revision, records.length),
            upserted: [
              for (final item in records.entries)
                _entity(item.key, item.value.revision),
            ],
            removedEntries: [
              for (final id in old.keys)
                if (!records.containsKey(id)) _entries[id]!,
            ],
          ),
        ),
      ),
    );
    await usagePort.feed.acknowledged(revision + 1);
    _usageRevision = revision;
  }

  Future<CloseReport> close({DateTime? deadline}) async {
    final report = await usage.close(deadline: deadline);
    final others = await Future.wait([
      configuration.close(deadline: deadline),
      models.close(deadline: deadline),
    ]);
    return CloseReport(
      unresolved: [
        ...report.unresolved,
        for (final value in others) ...value.unresolved,
      ],
    );
  }
}

ProductProjectionStamp _stamp(int revision) => ProductProjectionStamp(
  ownerEpoch: usageFixtureOrigin.ownerEpoch,
  incarnation: usageFixtureOrigin.incarnation,
  revision: revision,
);
ProductFeedIdentity _identity(String feedId, ProductResource resource) =>
    ProductFeedIdentity(
      feedId: feedId,
      ownerEpoch: usageFixtureOrigin.ownerEpoch,
      incarnation: usageFixtureOrigin.incarnation,
      resource: resource,
    );
ProductCollectionRef _collection(int revision, int total) =>
    ProductCollectionRef(entry: 2, revision: revision, total: total);
ProductEntityRef _entity(String id, int revision) =>
    ProductEntityRef(entry: _entries[id]!, revision: revision);
ObservedHeader _source(int revision) => ObservedHeader(
  brief: ObservedBrief.ready(
    revision: revision,
    updatedAt: revision,
    lastCheckedAt: null,
  ),
  status: ProductSourceStatusRef(entry: 3, revision: revision),
);
ConfigurationHeader _configHeader(int revision) => ConfigurationHeader(
  source: _source(revision),
  configurationRevision: revision,
  updatedAt: revision,
  reference: ConfigurationReadRef(entry: 1, revision: revision),
  roleRead: null,
);
AccountUsageHeader _usageHeader(int revision) => AccountUsageHeader(
  source: _source(revision),
  reference: AccountUsageReadRef(entry: 1, revision: revision),
);

final class UsageCheckCall {
  UsageCheckCall(this.accountId, this.expectedUsageQueryRevision);
  final String accountId;
  final int expectedUsageQueryRevision;
  final reply = Completer<AccountUsageCheckResult>();
  void succeed(int revision) => reply.complete(
    AccountUsageCheckResult(
      target: AccountUsageReadTarget(
        origin: usageFixtureOrigin,
        reference: AccountUsageReadRef(entry: 1, revision: revision),
      ),
      accountId: accountId,
      usageQueryRevision: expectedUsageQueryRevision,
    ),
  );
}

final class ScriptedAccountUsagePort implements AccountUsagePort {
  final versions = <int, Map<String, AccountUsageRecord>>{};
  final calls = <UsageCheckCall>[];
  final _calls = <int, Completer<UsageCheckCall>>{};
  final _headers = <int, Completer<void>>{};
  void Function(UsageCheckCall)? onCheck;
  final feed = ScriptedFeed<AccountUsageFrame>(
    feedId: 'usage-feed',
    sequenceOf: (frame) =>
        frame is AccountUsageDataFrame ? frame.deliverySequence : null,
    isTerminal: (frame) => frame is! AccountUsageDataFrame,
  );
  Future<UsageCheckCall> called(int index) => index < calls.length
      ? Future.value(calls[index])
      : _calls.putIfAbsent(index, Completer<UsageCheckCall>.new).future;
  Future<void> headerRead(int revision) =>
      _headers.putIfAbsent(revision, Completer<void>.new).future;
  @override
  Future<FeedConnection<AccountUsageFrame>> openAccountUsage() async => feed;
  @override
  Future<AccountUsageCheckResult> check(
    String accountId, {
    required int expectedUsageQueryRevision,
  }) {
    final call = UsageCheckCall(accountId, expectedUsageQueryRevision);
    calls.add(call);
    _calls.remove(calls.length - 1)?.complete(call);
    onCheck?.call(call);
    return call.reply.future;
  }

  @override
  Future<AccountUsageReadConnection> openAccountUsageRead(
    AccountUsageReadRef reference, {
    required ProductReadOrigin origin,
  }) async {
    if (origin != usageFixtureOrigin ||
        reference.entry != 1 ||
        !versions.containsKey(reference.revision)) {
      throw StateError('Unscripted usage pin');
    }
    return _UsagePin(reference.revision, versions[reference.revision]!, () {
      final receipt = _headers.putIfAbsent(
        reference.revision,
        Completer<void>.new,
      );
      if (!receipt.isCompleted) receipt.complete();
    });
  }

  @override
  Never noSuchMethod(Invocation invocation) => throw UnsupportedError(
    'Unscripted usage capability: ${invocation.memberName}',
  );
}

final class UsageConfigurationPort implements ConfigurationPort {
  @override
  Future<ConfigurationCommandCall> saveAccount(UpdateAccountRequest request) =>
      rejectUnscriptedConfigurationBegin(
        'This Usage fixture has no scripted account begin',
      );
  @override
  Future<ConfigurationCommandCall> setDefaultAccount(
    SetDefaultAccountRequest request,
  ) => rejectUnscriptedConfigurationBegin(
    'This Usage fixture has no scripted default-account begin',
  );
  @override
  Future<ConfigurationCommandCall> removeAccount(
    RemoveAccountRequest request,
  ) => rejectUnscriptedConfigurationBegin(
    'This Usage fixture has no scripted account-removal begin',
  );
  @override
  Future<ConfigurationCommandCall> removeAccountModel(
    RemoveAccountModelRequest request,
  ) => rejectUnscriptedConfigurationBegin(
    'This Usage fixture has no scripted model-removal begin',
  );
  @override
  Future<ConfigurationCommandCall> setAccountModelEnabled(
    SetAccountModelEnabledRequest request,
  ) => rejectUnscriptedConfigurationBegin(
    'This Usage fixture has no scripted model-enabled begin',
  );
  @override
  Future<ConfigurationCommandCall> setAccountBillingKind(
    SetAccountBillingKindRequest request,
  ) => rejectUnscriptedConfigurationBegin(
    'This Usage fixture has no scripted billing begin',
  );
  @override
  Future<ConfigurationCommandCall> applyField(
    UpdateSettingsFieldRequest request,
  ) => rejectUnscriptedConfigurationBegin(
    'This Usage fixture has no scripted settings-field begin',
  );
  @override
  Future<ConfigurationCommandCall> setPermission(
    UpdatePermissionSettingsRequest request,
  ) => rejectUnscriptedConfigurationBegin(
    'This Usage fixture has no scripted permission begin',
  );
  @override
  Future<ConfigurationCommandCall?> findConfigurationCommand(
    OperationId operationId,
  ) => throw UnsupportedError(
    'This Usage fixture has no scripted Configuration command lookup',
  );
  @override
  Future<ConfigurationStartReadConnection> openStartRead(
    ConfigurationRoleReadTarget sources,
  ) => throw UnsupportedError('This Usage fixture has no scripted Start read');
  @override
  Future<ConfigurationRoleReadConnection> openRoleRead(
    ConfigurationRoleReadTarget target,
  ) => throw UnsupportedError(
    'This Usage fixture has no scripted configuration/catalog role pair',
  );

  final versions = <int, Map<String, int>>{};
  final feed = ScriptedFeed<ConfigurationFrame>(
    feedId: 'usage-configuration-feed',
    sequenceOf: (frame) =>
        frame is ConfigurationData ? frame.deliverySequence : null,
    isTerminal: (frame) => frame is! ConfigurationData,
  );
  @override
  Future<FeedConnection<ConfigurationFrame>> openConfiguration() async => feed;
  @override
  Future<ConfigurationReadConnection> openConfigurationRead(
    ConfigurationReadRef reference, {
    required ProductReadOrigin origin,
  }) async {
    if (origin != usageFixtureOrigin ||
        reference.entry != 1 ||
        !versions.containsKey(reference.revision)) {
      throw StateError('Unscripted configuration pin');
    }
    return _ConfigurationPin(reference.revision, versions[reference.revision]!);
  }

  @override
  Never noSuchMethod(Invocation invocation) => throw UnsupportedError(
    'Unscripted configuration capability: ${invocation.memberName}',
  );
}

/// Mechanical native pin lifetime only; no Repository state or retry policy.
abstract class _NativePin {
  _NativePin(this.id);
  final String id;
  bool sealed = false;
  void admit() {
    if (sealed)
      throw const StudioFailure(
        code: StudioFailureCode.cancelled,
        message: 'The original scripted pin is sealed',
        retryable: false,
        correlationId: 'usage-fixture-pin',
      );
  }

  void requestClose() => sealed = true;
  Future<FeedCloseReport> close() async {
    requestClose();
    return FeedCloseReport(feedId: id, outcome: const FeedCloseOutcome.clean());
  }

  Future<FeedCloseReport> retryClose() => close();
}

final class _ConfigurationPin extends _NativePin
    implements ConfigurationReadConnection {
  _ConfigurationPin(this.revision, this.accountRevisions)
    : super('configuration-$revision');
  final int revision;
  final Map<String, int> accountRevisions;
  @override
  Future<ProductEntityRef?> lookupAccount(String id) async {
    admit();
    return accountRevisions.containsKey(id) ? _entity(id, revision) : null;
  }

  @override
  Future<ConfigurationEntryPage> entries({
    int offset = 0,
    int limit = 32,
  }) async {
    admit();
    final values = [
      for (final id in accountRevisions.keys) _entity(id, revision),
    ];
    final end = (offset + limit).clamp(0, values.length);
    return ConfigurationEntryPage(
      collection: _collection(revision, values.length),
      offset: offset,
      items: values.sublist(offset, end),
      nextOffset: end == values.length ? null : end,
    );
  }

  @override
  Future<ConfigurationEntityRead> entity(ProductEntityRef reference) async {
    admit();
    final id = accountRevisions.keys.singleWhere(
      (id) => _entity(id, revision) == reference,
    );
    return ConfigurationEntityRead(
      reference: reference,
      value: AccountConfigurationRead(
        accountId: ReadText.inline(text: id),
        templateId: null,
        protocol: const ReadText.inline(text: 'openai'),
        name: ReadText.inline(text: '$id version $revision'),
        baseUrl: const ReadText.inline(text: 'https://usage.invalid'),
        hasBearerToken: false,
        usageQueryRevision: accountRevisions[id]!,
        catalogId: null,
        bearerTokenEnv: null,
        billingKind: BillingKind.unknown,
        billingKindOverride: null,
        disabledModels: const TypedListRef(listId: 4, total: 0),
        customModels: const TypedListRef(listId: 1, total: 0),
        modelConnectionModes: const TypedListRef(listId: 2, total: 0),
        modelAutoCompactLimits: const TypedListRef(listId: 3, total: 0),
      ),
    );
  }

  @override
  Never noSuchMethod(Invocation invocation) => throw UnsupportedError(
    'Unscripted account field: ${invocation.memberName}',
  );
}

final class _UsagePin extends _NativePin implements AccountUsageReadConnection {
  _UsagePin(this.revision, this.records, this.onHeader)
    : super('usage-$revision');
  final int revision;
  final Map<String, AccountUsageRecord> records;
  final void Function() onHeader;
  @override
  Future<AccountUsageReadHeader> header() async {
    admit();
    onHeader();
    return AccountUsageReadHeader(
      configFingerprint: const ReadText.inline(text: 'native-fingerprint'),
      usages: TypedListRef(listId: 1, total: records.length),
    );
  }

  @override
  Future<ProductEntityRef?> lookupAccount(String id) async {
    admit();
    final record = records[id];
    return record == null ? null : _entity(id, record.revision);
  }

  @override
  Future<AccountUsageEntryPage> entries({
    int offset = 0,
    int limit = 32,
  }) async {
    admit();
    final values = [
      for (final item in records.entries)
        _entity(item.key, item.value.revision),
    ];
    final end = (offset + limit).clamp(0, values.length);
    return AccountUsageEntryPage(
      collection: _collection(revision, values.length),
      offset: offset,
      items: values.sublist(offset, end),
      nextOffset: end == values.length ? null : end,
    );
  }

  @override
  Future<AccountUsageEntityRead> entity(ProductEntityRef reference) async {
    admit();
    final record = records.values.singleWhere(
      (value) => _entity(value.accountId, value.revision) == reference,
    );
    if (record.state is! UsageUnsupported)
      throw StateError('Script this native usage result explicitly');
    return AccountUsageEntityRead(
      reference: reference,
      value: AccountUsageRead(
        accountId: ReadText.inline(text: record.accountId),
        revision: record.revision,
        updatedAt: record.updatedAt,
        lastOperationId: ReadText.inline(text: record.lastOperationId),
        state: const AccountUsageResultRead.unsupported(),
      ),
    );
  }

  @override
  Never noSuchMethod(Invocation invocation) => throw UnsupportedError(
    'Unscripted usage field: ${invocation.memberName}',
  );
}

final class _UnusedModels implements ModelsPort {
  @override
  Never noSuchMethod(Invocation invocation) => throw UnsupportedError(
    'Usage must not demand model policy: ${invocation.memberName}',
  );
}
