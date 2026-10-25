import 'dart:async';

import 'package:anywork_client/account_usage_ports.dart';
import 'package:anywork_client/configuration_ports.dart';
import 'package:anywork_client/models_ports.dart';
import 'package:anywork_client/modes.dart';
import 'package:anywork_client/operations_ports.dart';
import 'package:anywork_client/resources_ports.dart';

import '../../../../anywork_client/test/support/account_usage_fixture.dart';
import '../../../../anywork_client/test/support/configuration_command_fixture.dart';
import '../../../../anywork_client/test/support/profile_configuration_port.dart';
import '../../../../anywork_client/test/support/profile_model_port.dart';
import '../../../../anywork_client/test/support/profile_native_pin.dart';
import '../../../../anywork_client/test/support/scripted_feed.dart';

/// Settings-only assembly. Existing native fixtures supply bounded pages and
/// explicit call gates; all state, scheduling and operation settlement stay in
/// the real repositories. No request is applied by this environment.
final class SettingsAccountsFixture {
  SettingsAccountsFixture({int accountCount = 2, AgentProfileSnapshot? profile}) {
    final ids = List.generate(accountCount, (index) => 'account-$index');
    configurationPort = SettingsConfigurationPort(ids, profile);
    modelPort = SettingsModelsPort(ids);
    operations = OperationRegistry(clientId: 'settings-accounts', budget: budget);
    final assembly = createModelsRepository(port: modelPort, budget: budget);
    models = assembly.repository;
    configuration = createConfigurationRepository(port: configurationPort,
      budget: budget, operations: operations, modelTargets: assembly.targets);
    usage = createAccountUsageRepository(port: usagePort, budget: budget,
      operations: operations, configuration: configuration);
  }

  static const origin = ProductReadOrigin(ownerEpoch: 'settings-native', incarnation: 1);
  final budget = ResourceBudget();
  final usagePort = ScriptedAccountUsagePort();
  late final SettingsConfigurationPort configurationPort;
  late final SettingsModelsPort modelPort;
  late final OperationRegistry operations;
  late final ConfigurationRepository configuration;
  late final ModelsRepository models;
  late final AccountUsageRepository usage;

  Future<void> establish() async {
    final reads = [configuration.loadAccountsPage(), configuration.loadProfilesPage(),
      models.loadAccountsPage(), models.loadTemplates(), usage.loadRecordsPage()];
    await Future.wait([configurationPort.base.feed.listened.future,
      configurationPort.base.profilesFeed.listened.future, modelPort.base.feed.listened.future,
      modelPort.templatesFeed.listened.future, usagePort.feed.listened.future]);
    configurationPort.base.baseline();
    modelPort.base.baseline();
    modelPort.templatesFeed.emit(AccountTemplatesFrame.data(deliverySequence: 1,
      event: AccountTemplatesEvent.baseline(
        identity: profileIdentity(modelPort.templatesFeed.feedId, origin, ProductResource.accountTemplates),
        stamp: profileStamp(origin, 1),
        value: AccountTemplatesBaseline(header: const AccountTemplatesHeader(
          schemaVersion: 1, reference: AccountTemplatesReadRef(entry: 1, revision: 1)),
          collection: const ProductCollectionRef(entry: 2, revision: 1, total: 1)))));
    usagePort.versions[0] = const {};
    usagePort.feed.emit(AccountUsageFrame.data(deliverySequence: 1,
      event: AccountUsageEvent.baseline(
        identity: profileIdentity(usagePort.feed.feedId, usageFixtureOrigin, ProductResource.accountUsage),
        stamp: profileStamp(usageFixtureOrigin, 0),
        value: AccountUsageBaseline(header: AccountUsageHeader(source: profileSource(0),
          reference: const AccountUsageReadRef(entry: 1, revision: 0)),
          collection: const ProductCollectionRef(entry: 2, revision: 0, total: 0)))));
    await Future.wait(reads);
    await Future.wait([configurationPort.base.feed.acknowledged(1),
      configurationPort.base.profilesFeed.acknowledged(1), modelPort.base.feed.acknowledged(1),
      modelPort.templatesFeed.acknowledged(1), usagePort.feed.acknowledged(1)]);
  }

  Future<CloseReport> close() async {
    const refused = CommandDispatchFailure.rejected(failure: StudioFailure(
      code: StudioFailureCode.cancelled, message: 'Settings environment closed', retryable: false,
      correlationId: 'settings-test-cleanup'));
    for (final call in [...configurationPort.saves, ...configurationPort.fields]) {
      if (!call.beginReply.isCompleted) call.beginReply.completeError(refused);
      for (var i = 0; i < call.native.resultCalls; i++) {
        final result = call.native.resultAt(i);
        if (!result.reply.isCompleted) result.reply.completeError(refused);
      }
      for (final close in call.native.closes) {
        if (!close.reply.isCompleted) {
          close.reply.complete(FeedCloseReport(
          feedId: call.native.callId, outcome: const FeedCloseOutcome.clean()));
        }
      }
    }
    for (final call in usagePort.calls) {
      if (!call.reply.isCompleted) call.reply.completeError(refused);
    }
    for (final call in modelPort.base.firstCalls) {
      if (!call.reply.isCompleted) call.reply.complete(null);
    }
    final reports = await Future.wait([usage.close(), configuration.close(), models.close()]);
    return CloseReport(unresolved: [for (final report in reports) ...report.unresolved]);
  }
}

final class SettingsConfigurationPort implements ConfigurationPort {
  SettingsConfigurationPort(List<String> ids, AgentProfileSnapshot? profile)
    : base = ProfileConfigurationPort(origin: SettingsAccountsFixture.origin, accounts: ids, profile: profile);
  final ProfileConfigurationPort base;
  final saves = <RecordedConfigurationCall<UpdateAccountRequest>>[];
  final fields = <RecordedConfigurationCall<UpdateSettingsFieldRequest>>[];
  final _saveWaiters = <int, Completer<RecordedConfigurationCall<UpdateAccountRequest>>>{};
  final _fieldWaiters = <int, Completer<RecordedConfigurationCall<UpdateSettingsFieldRequest>>>{};
  final followAt = <int, bool>{1: true};
  Future<RecordedConfigurationCall<UpdateAccountRequest>> saved(int index) => index < saves.length
    ? Future.value(saves[index]) : _saveWaiters.putIfAbsent(index, Completer<RecordedConfigurationCall<UpdateAccountRequest>>.new).future;
  Future<RecordedConfigurationCall<UpdateSettingsFieldRequest>> field(int index) => index < fields.length
    ? Future.value(fields[index]) : _fieldWaiters.putIfAbsent(index, Completer<RecordedConfigurationCall<UpdateSettingsFieldRequest>>.new).future;
  @override
  Future<ConfigurationCommandCall> saveAccount(UpdateAccountRequest request) {
    final call = RecordedConfigurationCall(request, ScriptedConfigurationCommandCall(
      callId: 'settings-save-${saves.length}', operationId: request.operationId));
    saves.add(call); _saveWaiters.remove(saves.length - 1)?.complete(call);
    return call.beginReply.future;
  }
  @override
  Future<ConfigurationCommandCall> applyField(UpdateSettingsFieldRequest request) {
    final call = RecordedConfigurationCall(request, ScriptedConfigurationCommandCall(
      callId: 'settings-field-${fields.length}', operationId: request.operationId));
    fields.add(call); _fieldWaiters.remove(fields.length - 1)?.complete(call);
    return call.beginReply.future;
  }
  @override
  Future<FeedConnection<ConfigurationFrame>> openConfiguration() => base.openConfiguration();
  @override
  Future<FeedConnection<AgentProfilesFrame>> openAgentProfiles() => base.openAgentProfiles();
  @override
  Future<AgentProfilesReadConnection> openAgentProfilesRead(AgentProfilesReadRef reference,
    {required ProductReadOrigin origin}) => base.openAgentProfilesRead(reference, origin: origin);
  @override
  Future<ProductSourceStatusReadConnection> openSourceStatus(ProductSourceStatusRef reference,
    {required ProductReadOrigin origin}) => base.openSourceStatus(reference, origin: origin);
  @override
  Future<ConfigurationReadConnection> openConfigurationRead(ConfigurationReadRef reference,
    {required ProductReadOrigin origin}) async => _SettingsPin(
      await base.openConfigurationRead(reference, origin: origin), base.accounts,
      followAt[reference.revision] ?? true);
  @override
  Never noSuchMethod(Invocation invocation) => throw UnsupportedError('Unscripted Settings capability: ${invocation.memberName}');
}

final class _SettingsPin implements ConfigurationReadConnection {
  _SettingsPin(this.base, this.ids, this.follow);
  final ConfigurationReadConnection base;
  final List<String> ids;
  final bool follow;
  @override
  Future<ConfigurationReadHeader> header() async => ConfigurationReadHeader(
    defaultAccountId: const ReadText.inline(text: 'account-0'),
    accounts: TypedListRef(listId: 1, total: ids.length),
    modeModelRoutes: const TypedListRef(listId: 0, total: 0), roles: const TypedListRef(listId: 0, total: 0),
    permissionMode: const ReadText.inline(text: 'default'),
    instructions: const InstructionsSettingsRead(baseOverride: ReadText.inline(text: ''),
      developer: ReadText.inline(text: ''), user: ReadText.inline(text: ''), projectDocMaxBytes: 0,
      projectDocFallbackFilenames: TypedListRef(listId: 0, total: 0)),
    skills: const SkillsSettingsRead(enabled: false, autoLearn: false, systemEnabled: false,
      projectDir: ReadText.inline(text: ''), userDir: ReadText.inline(text: ''),
      externalDirs: TypedListRef(listId: 0, total: 0), disabled: TypedListRef(listId: 0, total: 0), autoLearnMinToolCalls: 0),
    mcpServers: const TypedListRef(listId: 0, total: 0),
    general: GeneralSettingsRead(followActiveTurn: follow, compactTimeline: false, sidebarWidth: null,
      pinnedThreadIds: const TypedListRef(listId: 0, total: 0), pinnedProjectIds: const TypedListRef(listId: 0, total: 0)),
    delegation: const DelegationSettings(mode: DelegationMode.profile, preference: DelegationPreference.balanced),
    webSearch: const WebSearchConfigurationRead(configuredMode: ReadText.inline(text: 'off'), contextSize: null,
      allowedDomains: TypedListRef(listId: 0, total: 0), country: null, region: null, city: null, timezone: null),
    deepseekWebSearch: const DeepSeekSearchConfigurationRead(configuredEnabled: false, configuredFetchEnabled: false));
  @override
  Future<ProductEntityRef?> lookupAccount(String id) async => ids.contains(id)
    ? ProductEntityRef(entry: 100 + ids.indexOf(id), revision: 1) : null;
  @override
  Future<ConfigurationEntryPage> entries({int offset = 0, int limit = 32}) => base.entries(offset: offset, limit: limit);
  @override
  Future<ConfigurationEntityRead> entity(ProductEntityRef reference) => base.entity(reference);
  @override
  void requestClose() => base.requestClose();
  @override
  Future<FeedCloseReport> close() => base.close();
  @override
  Future<FeedCloseReport> retryClose() => base.retryClose();
  @override
  Never noSuchMethod(Invocation invocation) => throw UnsupportedError('Unscripted Settings field: ${invocation.memberName}');
}

final class SettingsModelsPort implements ModelsPort {
  SettingsModelsPort(List<String> ids) : base = ProfileModelsPort(
    origin: SettingsAccountsFixture.origin, accounts: ids, textEligibleAccounts: ids.toSet());
  final ProfileModelsPort base;
  bool duplicateModels = false;
  final templatesFeed = ScriptedFeed<AccountTemplatesFrame>(feedId: 'settings-templates',
    sequenceOf: (frame) => frame is AccountTemplatesData ? frame.deliverySequence : null,
    isTerminal: (frame) => frame is! AccountTemplatesData);
  Future<void> invalidateTextModels() async {
    base.declaredCatalogs.add(2);
    base.feed.emit(ModelCatalogFrame.data(deliverySequence: 2,
      event: ModelCatalogEvent.change(stamp: profileStamp(SettingsAccountsFixture.origin, 2),
        baseRevision: 1, value: ModelCatalogChange(header: ModelCatalogHeader(
          source: profileSource(2), catalogRevision: 2, updatedAt: 2,
          reference: const ModelCatalogReadRef(entry: 1, revision: 2)),
          baseCollectionRevision: 1, collection: profileCollection(2, base.accounts.length),
          upserted: [for (var index = 0; index < base.accounts.length; index++)
            ProductEntityRef(entry: 100 + index, revision: 2)], removedEntries: const []))));
    await base.feed.acknowledged(2);
  }
  @override
  Future<FeedConnection<ModelCatalogFrame>> openModelCatalog() => base.openModelCatalog();
  @override
  Future<ModelCatalogReadConnection> openModelCatalogRead(ModelCatalogReadRef reference,
    {required ProductReadOrigin origin}) async => _SettingsCatalogPin(
      await base.openModelCatalogRead(reference, origin: origin), reference.revision, duplicateModels);
  @override
  Future<ProductSourceStatusReadConnection> openSourceStatus(ProductSourceStatusRef reference,
    {required ProductReadOrigin origin}) => base.openSourceStatus(reference, origin: origin);
  @override
  Future<FeedConnection<AccountTemplatesFrame>> openAccountTemplates() async => templatesFeed;
  @override
  Future<AccountTemplatesReadConnection> openAccountTemplatesRead(AccountTemplatesReadRef reference,
    {required ProductReadOrigin origin}) async => _TemplatesPin();
  @override
  Never noSuchMethod(Invocation invocation) => throw UnsupportedError('Unscripted Settings model capability: ${invocation.memberName}');
}

final class _SettingsCatalogPin implements ModelCatalogReadConnection {
  _SettingsCatalogPin(this.base, this.revision, this.duplicateModels);
  final ModelCatalogReadConnection base;
  final int revision;
  final bool duplicateModels;
  @override
  Future<ModelCatalogReadHeader> header() => base.header();
  @override
  Future<ModelSelection?> firstTextModel() => base.firstTextModel();
  @override
  Future<String?> effortAfterModelSelection(String accountId, String modelId, {required String? candidate}) =>
    base.effortAfterModelSelection(accountId, modelId, candidate: candidate);
  @override
  Future<ModelCatalogEntryPage> entries({int offset = 0, int limit = 32}) async {
    final page = await base.entries(offset: offset, limit: limit);
    return ModelCatalogEntryPage(collection: page.collection, offset: page.offset,
      items: [for (final ref in page.items) ref.copyWith(revision: revision)], nextOffset: page.nextOffset);
  }
  @override
  Future<ProductEntityRef?> lookupAccount(String accountId) async =>
    (await base.lookupAccount(accountId))?.copyWith(revision: revision);
  @override
  Future<ModelCatalogEntityRead> entity(ProductEntityRef reference) async {
    final entity = await base.entity(reference.copyWith(revision: 1));
    return entity.copyWith(reference: reference, value: duplicateModels
      ? entity.value.copyWith(effectiveModels: entity.value.effectiveModels.copyWith(total: 3)) : entity.value);
  }
  @override
  Future<ModelDescriptorReadPage> models(int listId, {int offset = 0, int limit = 32}) async {
    final page = await base.models(listId, offset: offset, limit: limit);
    if (!duplicateModels) return page;
    final model = page.items.single;
    return ModelDescriptorReadPage(listId: listId, offset: offset, total: 3, items: [model, model,
      model.copyWith(modelId: const ReadText.inline(text: 'image-generator'),
        typeSupport: const TypedListRef(listId: 21, total: 1))], nextOffset: null);
  }
  @override
  Future<ModelTypeSupportReadPage> typeSupport(int listId, {int offset = 0, int limit = 32}) async {
    final page = await base.typeSupport(listId, offset: offset, limit: limit);
    return revision == 1 ? page : page.copyWith(items: [ModelTypeSupportRead(
      modelType: ModelType.text, exclusions: const TypedListRef(listId: 22, total: 1))]);
  }
  @override
  Future<ModelTypeExclusionReadPage> typeExclusions(int listId, {int offset = 0, int limit = 32}) async =>
    ModelTypeExclusionReadPage(listId: listId, offset: offset, total: 1,
      items: const [ModelTypeExclusionReadItem(value: ModelTypeExclusion.contextWindowUnknown)], nextOffset: null);
  @override
  Future<TextReadPage> strings(int listId, {int offset = 0, int limit = 32}) => base.strings(listId, offset: offset, limit: limit);
  @override
  void requestClose() => base.requestClose();
  @override
  Future<FeedCloseReport> close() => base.close();
  @override
  Future<FeedCloseReport> retryClose() => base.retryClose();
  @override
  Never noSuchMethod(Invocation invocation) => throw UnsupportedError('Unscripted catalog field: ${invocation.memberName}');
}

final class _TemplatesPin extends ProfileNativePin implements AccountTemplatesReadConnection {
  _TemplatesPin() : super('settings-templates-pin');
  @override
  Future<AccountTemplatesReadHeader> header() async => const AccountTemplatesReadHeader(
    schemaVersion: 1, revision: ReadText.inline(text: 'settings-template'),
    templates: TypedListRef(listId: 1, total: 1), modelCatalogs: TypedListRef(listId: 0, total: 0));
  @override
  Future<AccountTemplatesEntryPage> entries({int offset = 0, int limit = 32}) async => AccountTemplatesEntryPage(
    collection: ProductCollectionRef(entry: 2, revision: 1, total: 1), offset: 0,
    items: const [ProductEntityRef(entry: 10, revision: 1)], nextOffset: null);
  @override
  Future<AccountTemplatesEntityRead> entity(ProductEntityRef reference) async => AccountTemplatesEntityRead(
    reference: reference, value: const AccountTemplateRead(pricingEnabled: false,
      id: ReadText.inline(text: 'template'), displayName: ReadText.inline(text: 'Template'), description: null,
      baseUrl: ReadText.inline(text: 'https://settings.invalid'),
      credential: CredentialDescriptorRead(label: ReadText.inline(text: 'Key'), envVar: null),
      modelCatalogId: ReadText.inline(text: 'catalog'), protocol: ReadText.inline(text: 'openai'),
      suggestedModelId: ReadText.inline(text: 'text'), iconKey: null,
      serviceCapabilities: AccountServiceCapabilitiesRead(webSearch: WebSearchServiceCapabilitiesRead(
        hostedResponses: false, hostedDialect: ReadText.inline(text: 'none'), standalone: null),
        promptCacheDialect: ReadText.inline(text: 'none'), responsesProgrammaticToolCalling: false)));
}
