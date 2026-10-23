import 'dart:async';

import 'package:anywork_client/configuration_ports.dart';
import 'package:anywork_client/models_ports.dart';
import 'package:anywork_client/operations_ports.dart';
import 'package:anywork_client/resources_ports.dart';

import 'scripted_feed.dart';

const configurationFixtureOrigin = ProductReadOrigin(ownerEpoch: 'configuration-fixture', incarnation: 1);

AccountEdit accountEdit({bool rebuild = false,
  FieldEdit<String?> templateId = const FieldEdit.keep(),
  List<CustomModelChange> models = const [],
  List<ModelConnectionChange> connections = const [],
  List<ModelLimitChange> limits = const [],
}) => AccountEdit(accountId: 'fixture', create: false,
  rebuildModelConfiguration: rebuild,
  templateId: templateId, protocol: const FieldEdit.keep(),
  name: const FieldEdit.keep(), baseUrl: const FieldEdit.keep(),
  secret: const AccountSecretUpdate.preserve(), pricingEnabled: const FieldEdit.keep(),
  customModels: models, connections: connections, autoCompactLimits: limits);

CustomModelConfiguration customModel(String id, {String wireApi = 'chat',
  int? contextWindow, int? maxOutputTokens,
}) => CustomModelConfiguration(modelId: id, displayName: id, wireApi: wireApi,
  contextWindow: contextWindow, maxOutputTokens: maxOutputTokens,
  inputCapabilities: const [], reasoningEfforts: const [], baseInstructions: '',
  supportedConnectionModes: const [], defaultConnectionMode: 'auto');

AccountModelUpdate modelUpdate(String id, {String wireApi = 'chat',
  String? name, int? contextWindow, int? maxOutputTokens,
}) => AccountModelUpdate(modelId: id, displayName: name ?? id, wireApi: wireApi,
  contextWindow: contextWindow, maxOutputTokens: maxOutputTokens);

final class ConfigurationFixture {
  ConfigurationFixture() {
    operations = OperationRegistry(clientId: 'configuration-test', budget: budget);
    final assembly = createModelsRepository(port: _UnusedModelsPort(), budget: budget);
    models = assembly.repository;
    repository = createConfigurationRepository(port: port, budget: budget,
      operations: operations, modelTargets: assembly.targets);
  }
  final budget = ResourceBudget();
  final port = FixtureConfigurationPort();
  late final OperationRegistry operations;
  late final ConfigurationRepository repository;
  late final ModelsRepository models;

  Future<void> establish(AccountConfiguration account, {int revision = 1}) async {
    port.snapshots[revision] = account;
    final reading = repository.loadAccount(account.accountId);
    final feed = await port.opened(0);
    await feed.listened.future;
    port.baseline(feed, revision);
    await reading;
    await feed.acknowledged(1);
  }
}

final class AccountSaveCall {
  AccountSaveCall(this.request);
  final UpdateAccountRequest request;
  final reply = Completer<ConfigurationCommandReply>();
}

/// This environment declares native account versions and records requests.
/// It never applies an AccountEdit, merges overrides, retries CAS or writes a
/// Repository mirror. Test replies explicitly reject after inspecting the real
/// prepared request, so no model-policy source is demanded in these cases.
final class FixtureConfigurationPort implements ConfigurationPort {
  @override
  Future<ConfigurationRoleReadConnection> openRoleRead(ConfigurationRoleReadTarget target) =>
      throw UnsupportedError('This account fixture has no scripted configuration/catalog role pair');

  final snapshots = <int, AccountConfiguration>{};
  final feeds = <ScriptedFeed<ConfigurationFrame>>[];
  final _feedWaiters = <int, Completer<ScriptedFeed<ConfigurationFrame>>>{};
  final saves = <AccountSaveCall>[];
  final _saveWaiters = <int, Completer<AccountSaveCall>>{};
  final readRevisions = <int>[];
  int readCloses = 0;

  Future<ScriptedFeed<ConfigurationFrame>> opened(int index) => index < feeds.length
      ? Future.value(feeds[index])
      : _feedWaiters.putIfAbsent(index, Completer<ScriptedFeed<ConfigurationFrame>>.new).future;
  Future<AccountSaveCall> saved(int index) => index < saves.length
      ? Future.value(saves[index])
      : _saveWaiters.putIfAbsent(index, Completer<AccountSaveCall>.new).future;

  @override
  Future<FeedConnection<ConfigurationFrame>> openConfiguration() async {
    final index = feeds.length;
    final feed = ScriptedFeed<ConfigurationFrame>(feedId: 'configuration-$index',
      sequenceOf: (frame) => frame is ConfigurationData ? frame.deliverySequence : null,
      isTerminal: (frame) => frame is! ConfigurationData);
    feeds.add(feed);
    _feedWaiters.remove(index)?.complete(feed);
    return feed;
  }
  @override
  Future<ConfigurationReadConnection> openConfigurationRead(ConfigurationReadRef reference,
    {required ProductReadOrigin origin}) async {
    final snapshot = snapshots[reference.revision];
    if (origin != configurationFixtureOrigin || snapshot == null) throw const StudioFailure(
      code: StudioFailureCode.superseded, message: 'Unscripted native configuration pin',
      retryable: false, correlationId: 'configuration-fixture');
    readRevisions.add(reference.revision);
    return _AccountPin('account-read-${readRevisions.length}', reference.revision,
      snapshot, () => readCloses++);
  }
  @override
  Future<ConfigurationCommandReply> saveAccount(UpdateAccountRequest request) {
    final index = saves.length;
    final call = AccountSaveCall(request);
    saves.add(call);
    _saveWaiters.remove(index)?.complete(call);
    return call.reply.future;
  }

  void baseline(ScriptedFeed<ConfigurationFrame> feed, int revision) => feed.emit(
    ConfigurationFrame.data(deliverySequence: 1, event: ConfigurationEvent.baseline(
      identity: ProductFeedIdentity(feedId: feed.feedId,
        ownerEpoch: configurationFixtureOrigin.ownerEpoch,
        incarnation: configurationFixtureOrigin.incarnation,
        resource: ProductResource.configuration),
      stamp: ProductProjectionStamp(ownerEpoch: configurationFixtureOrigin.ownerEpoch,
        incarnation: configurationFixtureOrigin.incarnation, revision: revision),
      value: ConfigurationBaseline(
        header: ConfigurationHeader(source: ObservedHeader(
          brief: ObservedBrief.ready(revision: revision, updatedAt: 1, lastCheckedAt: null),
          status: ProductSourceStatusRef(entry: 9, revision: revision)),
          configurationRevision: revision, updatedAt: 1,
          reference: ConfigurationReadRef(entry: 1, revision: revision), roleRead: null),
        collection: ProductCollectionRef(entry: 2, revision: revision, total: 1)),
    )));

  @override
  Never noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('Unscripted configuration capability: ${invocation.memberName}');
}

final class _UnusedModelsPort implements ModelsPort {
  @override
  Never noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('Rejected preparation must not demand model data: ${invocation.memberName}');
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
    if (_sealed) throw const StudioFailure(code: StudioFailureCode.cancelled,
      message: 'Original account pin is sealed', retryable: false,
      correlationId: 'configuration-pin');
  }
  @override
  Future<ProductEntityRef?> lookupAccount(String accountId) async {
    _admit();
    return accountId == account.accountId ? ProductEntityRef(entry: 5, revision: revision) : null;
  }
  @override
  Future<ConfigurationEntityRead> entity(ProductEntityRef reference) async {
    _admit();
    return ConfigurationEntityRead(reference: reference,
      value: AccountConfigurationRead(pricingEnabled: account.pricingEnabled,
        accountId: ReadText.inline(text: account.accountId),
        templateId: account.templateId == null ? null : ReadText.inline(text: account.templateId!),
        protocol: ReadText.inline(text: account.protocol), name: ReadText.inline(text: account.name),
        baseUrl: ReadText.inline(text: account.baseUrl), hasBearerToken: account.hasBearerToken,
        usageQueryRevision: account.usageQueryRevision,
        customModels: TypedListRef(listId: 10, total: account.customModels.length),
        modelConnectionModes: TypedListRef(listId: 11, total: account.modelConnectionModes.length),
        modelAutoCompactLimits: TypedListRef(listId: 12, total: account.modelAutoCompactLimits.length),
        catalogId: account.catalogId == null ? null : ReadText.inline(text: account.catalogId!)));
  }
  @override
  Future<CustomModelConfigurationReadPage> customModels(int listId, {int offset = 0, int limit = 32}) async {
    _admit();
    final end = (offset + limit).clamp(0, account.customModels.length);
    return CustomModelConfigurationReadPage(listId: listId, offset: offset,
      total: account.customModels.length, nextOffset: end == account.customModels.length ? null : end,
      items: [for (final model in account.customModels.sublist(offset, end))
        CustomModelConfigurationRead(inputCapabilities: const TypedListRef(listId: 20, total: 0),
          contextWindow: model.contextWindow, maxOutputTokens: model.maxOutputTokens,
          modelId: ReadText.inline(text: model.modelId), displayName: ReadText.inline(text: model.displayName),
          reasoningEfforts: const TypedListRef(listId: 21, total: 0),
          baseInstructions: ReadText.inline(text: model.baseInstructions), wireApi: ReadText.inline(text: model.wireApi),
          supportedConnectionModes: const TypedListRef(listId: 22, total: 0),
          defaultConnectionMode: ReadText.inline(text: model.defaultConnectionMode))]);
  }
  @override
  Future<ModelConnectionReadPage> modelConnections(int listId, {int offset = 0, int limit = 32}) async {
    _admit();
    final end = (offset + limit).clamp(0, account.modelConnectionModes.length);
    return ModelConnectionReadPage(listId: listId, offset: offset,
      total: account.modelConnectionModes.length,
      nextOffset: end == account.modelConnectionModes.length ? null : end,
      items: [for (final item in account.modelConnectionModes.sublist(offset, end))
        ModelConnectionRead(modelId: ReadText.inline(text: item.modelId),
          connectionMode: ReadText.inline(text: item.connectionMode))]);
  }
  @override
  Future<ModelAutoCompactReadPage> autoCompactOverrides(int listId, {int offset = 0, int limit = 32}) async {
    _admit();
    final end = (offset + limit).clamp(0, account.modelAutoCompactLimits.length);
    return ModelAutoCompactReadPage(listId: listId, offset: offset,
      total: account.modelAutoCompactLimits.length,
      nextOffset: end == account.modelAutoCompactLimits.length ? null : end,
      items: [for (final item in account.modelAutoCompactLimits.sublist(offset, end))
        ModelAutoCompactRead(modelId: ReadText.inline(text: item.modelId), overrideLimit: item.overrideLimit)]);
  }
  @override
  void requestClose() => _sealed = true;
  @override
  Future<FeedCloseReport> close() async {
    requestClose();
    if (!_closed) { _closed = true; onClose(); }
    return FeedCloseReport(feedId: id, outcome: const FeedCloseOutcome.clean());
  }
  @override
  Future<FeedCloseReport> retryClose() => close();
  @override
  Never noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('Unscripted account field: ${invocation.memberName}');
}
