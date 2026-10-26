import 'dart:async';

import 'package:anywork_client/configuration_ports.dart';
import 'package:anywork_client/models_ports.dart';
import 'package:anywork_client/operations_ports.dart';
import 'package:anywork_client/resources_ports.dart';

import 'configuration_command_fixture.dart';
import 'scripted_feed.dart';

const configurationFixtureOrigin = ProductReadOrigin(
  ownerEpoch: 'configuration-fixture',
  incarnation: 1,
);

AccountEdit accountEdit({
  bool rebuild = false,
  FieldEdit<String?> templateId = const FieldEdit.keep(),
  List<CustomModelChange> models = const [],
  List<ModelConnectionChange> connections = const [],
  List<ModelLimitChange> limits = const [],
}) => AccountEdit(
  accountId: 'fixture',
  create: false,
  rebuildModelConfiguration: rebuild,
  templateId: templateId,
  protocol: const FieldEdit.keep(),
  name: const FieldEdit.keep(),
  baseUrl: const FieldEdit.keep(),
  secret: const AccountSecretUpdate.preserve(),
  // 编辑既有账号不得携带初始计费类别：类别只由 setAccountBillingKind 改写。
  initialBillingKind: null,
  customModels: models,
  connections: connections,
  autoCompactLimits: limits,
);

CustomModelConfiguration customModel(
  String id, {
  String wireApi = 'chat',
  int? contextWindow,
  int? maxOutputTokens,
}) => CustomModelConfiguration(
  modelId: id,
  displayName: id,
  wireApi: wireApi,
  contextWindow: contextWindow,
  maxOutputTokens: maxOutputTokens,
  inputCapabilities: const [],
  reasoningEfforts: const [],
  baseInstructions: '',
  supportedConnectionModes: const [],
  defaultConnectionMode: 'auto',
);

AccountModelUpdate modelUpdate(
  String id, {
  String wireApi = 'chat',
  String? name,
  int? contextWindow,
  int? maxOutputTokens,
}) => AccountModelUpdate(
  modelId: id,
  displayName: name ?? id,
  wireApi: wireApi,
  contextWindow: contextWindow,
  maxOutputTokens: maxOutputTokens,
);

final class ConfigurationFixture {
  ConfigurationFixture({ResourceBudget? budget, ModelsPort? modelsPort})
    : budget = budget ?? ResourceBudget() {
    operations = OperationRegistry(
      clientId: 'configuration-test',
      budget: this.budget,
    );
    final assembly = createModelsRepository(
      port: modelsPort ?? _UnusedModelsPort(),
      budget: this.budget,
    );
    models = assembly.repository;
    repository = createConfigurationRepository(
      port: port,
      budget: this.budget,
      operations: operations,
      modelTargets: assembly.targets,
    );
  }
  final ResourceBudget budget;
  final port = FixtureConfigurationPort();
  late final OperationRegistry operations;
  late final ConfigurationRepository repository;
  late final ModelsRepository models;

  Future<void> establish(
    AccountConfiguration account, {
    int revision = 1,
    ConfigurationRoleReadTarget? sources,
  }) async {
    port.snapshots[revision] = account;
    final reading = repository.loadAccount(account.accountId);
    final feed = await port.opened(0);
    await feed.listened.future;
    port.baseline(feed, revision, sources: sources);
    await reading;
    await feed.acknowledged(1);
  }
}

/// This environment declares native account versions and records requests.
/// It never applies an AccountEdit, merges overrides, retries CAS or writes a
/// Repository mirror. Prepared-edit tests explicitly reject; successful command
/// tests independently declare both the native reply and its feed publication.
final class FixtureConfigurationPort implements ConfigurationPort {
  Future<ProductSourceStatusReadConnection> Function(
    ProductSourceStatusRef,
    ProductReadOrigin,
  )?
  sourceStatusOpen;
  @override
  Future<ProductSourceStatusReadConnection> openSourceStatus(
    ProductSourceStatusRef reference, {
    required ProductReadOrigin origin,
  }) {
    final open = sourceStatusOpen;
    if (open == null)
      throw UnsupportedError('Unscripted configuration source metadata read');
    return open(reference, origin);
  }

  @override
  Future<ConfigurationRoleReadConnection> openRoleRead(
    ConfigurationRoleReadTarget target,
  ) => throw UnsupportedError(
    'This account fixture has no scripted configuration/catalog role pair',
  );
  Future<ConfigurationStartReadConnection> Function(
    ConfigurationRoleReadTarget,
  )?
  startOpen;
  @override
  Future<ConfigurationStartReadConnection> openStartRead(
    ConfigurationRoleReadTarget sources,
  ) {
    final open = startOpen;
    if (open == null)
      throw UnsupportedError('This account fixture has no scripted Start read');
    return open(sources);
  }

  final snapshots = <int, AccountConfiguration>{};
  final feeds = <ScriptedFeed<ConfigurationFrame>>[];
  final _feedWaiters = <int, Completer<ScriptedFeed<ConfigurationFrame>>>{};
  final saves = <RecordedConfigurationCall<UpdateAccountRequest>>[];
  final _saveWaiters =
      <int, Completer<RecordedConfigurationCall<UpdateAccountRequest>>>{};
  final enabledChanges =
      <RecordedConfigurationCall<SetAccountModelEnabledRequest>>[];
  final _enabledWaiters =
      <
        int,
        Completer<RecordedConfigurationCall<SetAccountModelEnabledRequest>>
      >{};
  final billingChanges =
      <RecordedConfigurationCall<SetAccountBillingKindRequest>>[];
  final _billingWaiters =
      <
        int,
        Completer<RecordedConfigurationCall<SetAccountBillingKindRequest>>
      >{};
  final removals = <RecordedConfigurationCall<RemoveAccountModelRequest>>[];
  final _removalWaiters =
      <int, Completer<RecordedConfigurationCall<RemoveAccountModelRequest>>>{};
  final lookups = <RecordedConfigurationLookup>[];
  final _lookupWaiters = <int, Completer<RecordedConfigurationLookup>>{};
  bool holdCommandBegins = false;
  int _callSequence = 0;
  final readRevisions = <int>[];
  int readCloses = 0;
  int _projectionRevision = 0;
  int _configurationRevision = 0;
  int? _sourceStatusRevision;
  int _deliverySequence = 0;
  ConfigurationRoleReadTarget? _sources;

  Future<ScriptedFeed<ConfigurationFrame>> opened(int index) =>
      index < feeds.length
      ? Future.value(feeds[index])
      : _feedWaiters
            .putIfAbsent(index, Completer<ScriptedFeed<ConfigurationFrame>>.new)
            .future;
  Future<RecordedConfigurationCall<UpdateAccountRequest>> saved(int index) =>
      _called(saves, _saveWaiters, index);
  Future<RecordedConfigurationCall<SetAccountModelEnabledRequest>>
  enabledChanged(int index) => _called(enabledChanges, _enabledWaiters, index);
  Future<RecordedConfigurationCall<SetAccountBillingKindRequest>>
  billingChanged(int index) => _called(billingChanges, _billingWaiters, index);
  Future<RecordedConfigurationCall<RemoveAccountModelRequest>> removed(
    int index,
  ) => _called(removals, _removalWaiters, index);
  Future<RecordedConfigurationLookup> lookedUp(int index) =>
      index < lookups.length
      ? Future.value(lookups[index])
      : _lookupWaiters
            .putIfAbsent(index, Completer<RecordedConfigurationLookup>.new)
            .future;

  Future<RecordedConfigurationCall<T>> _called<T>(
    List<RecordedConfigurationCall<T>> calls,
    Map<int, Completer<RecordedConfigurationCall<T>>> waiters,
    int index,
  ) => index < calls.length
      ? Future.value(calls[index])
      : waiters
            .putIfAbsent(index, Completer<RecordedConfigurationCall<T>>.new)
            .future;

  Future<ConfigurationCommandCall> _record<T>(
    T request,
    OperationId operationId,
    List<RecordedConfigurationCall<T>> calls,
    Map<int, Completer<RecordedConfigurationCall<T>>> waiters,
  ) {
    final call = RecordedConfigurationCall<T>(
      request,
      ScriptedConfigurationCommandCall(
        callId: 'configuration-native-call-${++_callSequence}',
        operationId: operationId,
      ),
    );
    calls.add(call);
    waiters.remove(calls.length - 1)?.complete(call);
    if (!holdCommandBegins) call.accept();
    return call.beginReply.future;
  }

  @override
  Future<FeedConnection<ConfigurationFrame>> openConfiguration() async {
    final index = feeds.length;
    final feed = ScriptedFeed<ConfigurationFrame>(
      feedId: 'configuration-$index',
      sequenceOf: (frame) =>
          frame is ConfigurationData ? frame.deliverySequence : null,
      isTerminal: (frame) => frame is! ConfigurationData,
    );
    feeds.add(feed);
    _feedWaiters.remove(index)?.complete(feed);
    return feed;
  }

  @override
  Future<ConfigurationReadConnection> openConfigurationRead(
    ConfigurationReadRef reference, {
    required ProductReadOrigin origin,
  }) async {
    final snapshot = snapshots[reference.revision];
    if (origin != configurationFixtureOrigin || snapshot == null)
      throw const StudioFailure(
        code: StudioFailureCode.superseded,
        message: 'Unscripted native configuration pin',
        retryable: false,
        correlationId: 'configuration-fixture',
      );
    readRevisions.add(reference.revision);
    return _AccountPin(
      'account-read-${readRevisions.length}',
      reference.revision,
      snapshot,
      () => readCloses++,
    );
  }

  @override
  Future<ConfigurationCommandCall> saveAccount(UpdateAccountRequest request) =>
      _record(request, request.operationId, saves, _saveWaiters);
  @override
  Future<ConfigurationCommandCall> setAccountModelEnabled(
    SetAccountModelEnabledRequest request,
  ) => _record(request, request.operationId, enabledChanges, _enabledWaiters);
  @override
  Future<ConfigurationCommandCall> setAccountBillingKind(
    SetAccountBillingKindRequest request,
  ) => _record(request, request.operationId, billingChanges, _billingWaiters);
  @override
  Future<ConfigurationCommandCall> removeAccountModel(
    RemoveAccountModelRequest request,
  ) => _record(request, request.operationId, removals, _removalWaiters);
  @override
  Future<ConfigurationCommandCall> setDefaultAccount(
    SetDefaultAccountRequest request,
  ) => rejectUnscriptedConfigurationBegin('Unscripted default-account begin');
  @override
  Future<ConfigurationCommandCall> removeAccount(
    RemoveAccountRequest request,
  ) => rejectUnscriptedConfigurationBegin('Unscripted account-removal begin');
  @override
  Future<ConfigurationCommandCall> applyField(
    UpdateSettingsFieldRequest request,
  ) => rejectUnscriptedConfigurationBegin('Unscripted settings-field begin');
  @override
  Future<ConfigurationCommandCall> setPermission(
    UpdatePermissionSettingsRequest request,
  ) => rejectUnscriptedConfigurationBegin('Unscripted permission begin');
  @override
  Future<ConfigurationCommandCall?> findConfigurationCommand(
    OperationId operationId,
  ) {
    final call = RecordedConfigurationLookup(operationId);
    lookups.add(call);
    _lookupWaiters.remove(lookups.length - 1)?.complete(call);
    return call.reply.future;
  }

  ConfigurationHeader _header() => ConfigurationHeader(
    source: ObservedHeader(
      brief: ObservedBrief.ready(
        revision: _configurationRevision,
        updatedAt: 1,
        lastCheckedAt: null,
      ),
      status: ProductSourceStatusRef(
        entry: 9,
        revision: _sourceStatusRevision ?? _configurationRevision,
      ),
    ),
    configurationRevision: _configurationRevision,
    updatedAt: 1,
    reference: ConfigurationReadRef(entry: 1, revision: _configurationRevision),
    roleRead: _sources,
  );

  void baseline(
    ScriptedFeed<ConfigurationFrame> feed,
    int revision, {
    ConfigurationRoleReadTarget? sources,
  }) {
    _projectionRevision = _configurationRevision = revision;
    _deliverySequence = 1;
    _sources = sources;
    feed.emit(
      ConfigurationFrame.data(
        deliverySequence: 1,
        event: ConfigurationEvent.baseline(
          identity: ProductFeedIdentity(
            feedId: feed.feedId,
            ownerEpoch: configurationFixtureOrigin.ownerEpoch,
            incarnation: configurationFixtureOrigin.incarnation,
            resource: ProductResource.configuration,
          ),
          stamp: ProductProjectionStamp(
            ownerEpoch: configurationFixtureOrigin.ownerEpoch,
            incarnation: configurationFixtureOrigin.incarnation,
            revision: revision,
          ),
          value: ConfigurationBaseline(
            header: _header(),
            collection: ProductCollectionRef(
              entry: 2,
              revision: revision,
              total: 1,
            ),
          ),
        ),
      ),
    );
  }

  /// Publishes a test-declared native version, never applies the request above.
  Future<void> publishAccount(
    int revision,
    AccountConfiguration account,
  ) async {
    final base = _configurationRevision;
    snapshots[revision] = account;
    _configurationRevision = revision;
    _sources = null;
    await _change(base, [ProductEntityRef(entry: 5, revision: revision)]);
  }

  /// Pair-only metadata changes keep the account/configuration CAS base fixed.
  Future<void> publishPair(
    ConfigurationRoleReadTarget sources, {
    int? sourceStatusRevision,
  }) async {
    _sources = sources;
    if (sourceStatusRevision != null)
      _sourceStatusRevision = sourceStatusRevision;
    await _change(_configurationRevision, const []);
  }

  Future<void> _change(
    int baseCollection,
    List<ProductEntityRef> upserted,
  ) async {
    final previous = _projectionRevision++;
    final sequence = ++_deliverySequence;
    final feed = feeds.last;
    feed.emit(
      ConfigurationFrame.data(
        deliverySequence: sequence,
        event: ConfigurationEvent.change(
          stamp: ProductProjectionStamp(
            ownerEpoch: configurationFixtureOrigin.ownerEpoch,
            incarnation: configurationFixtureOrigin.incarnation,
            revision: _projectionRevision,
          ),
          baseRevision: previous,
          value: ConfigurationChange(
            header: _header(),
            baseCollectionRevision: baseCollection,
            collection: ProductCollectionRef(
              entry: 2,
              revision: _configurationRevision,
              total: 1,
            ),
            upserted: upserted,
            removedEntries: const [],
          ),
        ),
      ),
    );
    await feed.acknowledged(sequence);
  }

  @override
  Never noSuchMethod(Invocation invocation) => throw UnsupportedError(
    'Unscripted configuration capability: ${invocation.memberName}',
  );
}

final class _UnusedModelsPort implements ModelsPort {
  @override
  Never noSuchMethod(Invocation invocation) => throw UnsupportedError(
    'Rejected preparation must not demand model data: ${invocation.memberName}',
  );
}

final class _AccountPin implements ConfigurationReadConnection {
  _AccountPin(this.id, this.revision, this.account, this.onClose);
  final String id;
  final int revision;
  final AccountConfiguration account;
  final void Function() onClose;
  bool _sealed = false;
  bool _closed = false;
  void _admit() {
    if (_sealed)
      throw const StudioFailure(
        code: StudioFailureCode.cancelled,
        message: 'Original account pin is sealed',
        retryable: false,
        correlationId: 'configuration-pin',
      );
  }

  @override
  Future<ProductEntityRef?> lookupAccount(String accountId) async {
    _admit();
    return accountId == account.accountId
        ? ProductEntityRef(entry: 5, revision: revision)
        : null;
  }

  @override
  Future<ConfigurationEntityRead> entity(ProductEntityRef reference) async {
    _admit();
    return ConfigurationEntityRead(
      reference: reference,
      value: AccountConfigurationRead(
        billingKind: account.billingKind,
        billingKindOverride: account.billingKindOverride,
        disabledModels: TypedListRef(
          listId: 13,
          total: account.disabledModels.length,
        ),
        accountId: ReadText.inline(text: account.accountId),
        templateId: account.templateId == null
            ? null
            : ReadText.inline(text: account.templateId!),
        protocol: ReadText.inline(text: account.protocol),
        name: ReadText.inline(text: account.name),
        baseUrl: ReadText.inline(text: account.baseUrl),
        hasBearerToken: account.hasBearerToken,
        bearerTokenEnv: null,
        usageQueryRevision: account.usageQueryRevision,
        customModels: TypedListRef(
          listId: 10,
          total: account.customModels.length,
        ),
        modelConnectionModes: TypedListRef(
          listId: 11,
          total: account.modelConnectionModes.length,
        ),
        modelAutoCompactLimits: TypedListRef(
          listId: 12,
          total: account.modelAutoCompactLimits.length,
        ),
        catalogId: account.catalogId == null
            ? null
            : ReadText.inline(text: account.catalogId!),
      ),
    );
  }

  @override
  Future<CustomModelConfigurationReadPage> customModels(
    int listId, {
    int offset = 0,
    int limit = 32,
  }) async {
    _admit();
    final end = (offset + limit).clamp(0, account.customModels.length);
    return CustomModelConfigurationReadPage(
      listId: listId,
      offset: offset,
      total: account.customModels.length,
      nextOffset: end == account.customModels.length ? null : end,
      items: [
        for (final model in account.customModels.sublist(offset, end))
          CustomModelConfigurationRead(
            inputCapabilities: const TypedListRef(listId: 20, total: 0),
            contextWindow: model.contextWindow,
            maxOutputTokens: model.maxOutputTokens,
            modelId: ReadText.inline(text: model.modelId),
            displayName: ReadText.inline(text: model.displayName),
            reasoningEfforts: const TypedListRef(listId: 21, total: 0),
            baseInstructions: ReadText.inline(text: model.baseInstructions),
            wireApi: ReadText.inline(text: model.wireApi),
            supportedConnectionModes: const TypedListRef(listId: 22, total: 0),
            defaultConnectionMode: ReadText.inline(
              text: model.defaultConnectionMode,
            ),
          ),
      ],
    );
  }

  @override
  Future<ModelConnectionReadPage> modelConnections(
    int listId, {
    int offset = 0,
    int limit = 32,
  }) async {
    _admit();
    final end = (offset + limit).clamp(0, account.modelConnectionModes.length);
    return ModelConnectionReadPage(
      listId: listId,
      offset: offset,
      total: account.modelConnectionModes.length,
      nextOffset: end == account.modelConnectionModes.length ? null : end,
      items: [
        for (final item in account.modelConnectionModes.sublist(offset, end))
          ModelConnectionRead(
            modelId: ReadText.inline(text: item.modelId),
            connectionMode: ReadText.inline(text: item.connectionMode),
          ),
      ],
    );
  }

  @override
  Future<ModelAutoCompactReadPage> autoCompactOverrides(
    int listId, {
    int offset = 0,
    int limit = 32,
  }) async {
    _admit();
    final end = (offset + limit).clamp(
      0,
      account.modelAutoCompactLimits.length,
    );
    return ModelAutoCompactReadPage(
      listId: listId,
      offset: offset,
      total: account.modelAutoCompactLimits.length,
      nextOffset: end == account.modelAutoCompactLimits.length ? null : end,
      items: [
        for (final item in account.modelAutoCompactLimits.sublist(offset, end))
          ModelAutoCompactRead(
            modelId: ReadText.inline(text: item.modelId),
            overrideLimit: item.overrideLimit,
          ),
      ],
    );
  }

  @override
  Future<TextReadPage> strings(
    int listId, {
    int offset = 0,
    int limit = 32,
  }) async {
    _admit();
    if (listId != 13) throw StateError('Unscripted account string list');
    final end = (offset + limit).clamp(0, account.disabledModels.length);
    return TextReadPage(
      listId: listId,
      offset: offset,
      total: account.disabledModels.length,
      nextOffset: end == account.disabledModels.length ? null : end,
      items: [
        for (final id in account.disabledModels.sublist(offset, end))
          TextReadItem(value: ReadText.inline(text: id)),
      ],
    );
  }

  @override
  void requestClose() => _sealed = true;
  @override
  Future<FeedCloseReport> close() async {
    requestClose();
    if (!_closed) {
      _closed = true;
      onClose();
    }
    return FeedCloseReport(feedId: id, outcome: const FeedCloseOutcome.clean());
  }

  @override
  Future<FeedCloseReport> retryClose() => close();
  @override
  Never noSuchMethod(Invocation invocation) => throw UnsupportedError(
    'Unscripted account field: ${invocation.memberName}',
  );
}
