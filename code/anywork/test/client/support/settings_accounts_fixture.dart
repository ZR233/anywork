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
  SettingsAccountsFixture({
    int accountCount = 2,
    AgentProfileSnapshot? profile,
  }) {
    final ids = List.generate(accountCount, (index) => 'account-$index');
    configurationPort = SettingsConfigurationPort(ids, profile);
    modelPort = SettingsModelsPort(ids);
    operations = OperationRegistry(
      clientId: 'settings-accounts',
      budget: budget,
    );
    final assembly = createModelsRepository(port: modelPort, budget: budget);
    models = assembly.repository;
    configuration = createConfigurationRepository(
      port: configurationPort,
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

  static const origin = ProductReadOrigin(
    ownerEpoch: 'settings-native',
    incarnation: 1,
  );
  final budget = ResourceBudget();
  final usagePort = ScriptedAccountUsagePort();
  late final SettingsConfigurationPort configurationPort;
  late final SettingsModelsPort modelPort;
  late final OperationRegistry operations;
  late final ConfigurationRepository configuration;
  late final ModelsRepository models;
  late final AccountUsageRepository usage;

  Future<void> establish() async {
    final reads = [
      configuration.loadAccountsPage(),
      configuration.loadProfilesPage(),
      models.loadAccountsPage(),
      models.loadTemplates(),
      usage.loadRecordsPage(),
    ];
    await Future.wait([
      configurationPort.base.feed.listened.future,
      configurationPort.base.profilesFeed.listened.future,
      modelPort.base.feed.listened.future,
      modelPort.templatesFeed.listened.future,
      usagePort.feed.listened.future,
    ]);
    configurationPort.base.baseline();
    modelPort.base.baseline();
    modelPort.templatesFeed.emit(
      AccountTemplatesFrame.data(
        deliverySequence: 1,
        event: AccountTemplatesEvent.baseline(
          identity: profileIdentity(
            modelPort.templatesFeed.feedId,
            origin,
            ProductResource.accountTemplates,
          ),
          stamp: profileStamp(origin, 1),
          value: AccountTemplatesBaseline(
            header: const AccountTemplatesHeader(
              schemaVersion: 1,
              reference: AccountTemplatesReadRef(entry: 1, revision: 1),
            ),
            collection: const ProductCollectionRef(
              entry: 2,
              revision: 1,
              total: 1,
            ),
          ),
        ),
      ),
    );
    usagePort.versions[0] = const {};
    usagePort.feed.emit(
      AccountUsageFrame.data(
        deliverySequence: 1,
        event: AccountUsageEvent.baseline(
          identity: profileIdentity(
            usagePort.feed.feedId,
            usageFixtureOrigin,
            ProductResource.accountUsage,
          ),
          stamp: profileStamp(usageFixtureOrigin, 0),
          value: AccountUsageBaseline(
            header: AccountUsageHeader(
              source: profileSource(0),
              reference: const AccountUsageReadRef(entry: 1, revision: 0),
            ),
            collection: const ProductCollectionRef(
              entry: 2,
              revision: 0,
              total: 0,
            ),
          ),
        ),
      ),
    );
    await Future.wait(reads);
    await Future.wait([
      configurationPort.base.feed.acknowledged(1),
      configurationPort.base.profilesFeed.acknowledged(1),
      modelPort.base.feed.acknowledged(1),
      modelPort.templatesFeed.acknowledged(1),
      usagePort.feed.acknowledged(1),
    ]);
  }

  Future<CloseReport> close() async {
    const refused = CommandDispatchFailure.rejected(
      failure: StudioFailure(
        code: StudioFailureCode.cancelled,
        message: 'Settings environment closed',
        retryable: false,
        correlationId: 'settings-test-cleanup',
      ),
    );
    for (final call in [
      ...configurationPort.saves,
      ...configurationPort.fields,
    ]) {
      if (!call.beginReply.isCompleted) call.beginReply.completeError(refused);
      for (var i = 0; i < call.native.resultCalls; i++) {
        final result = call.native.resultAt(i);
        if (!result.reply.isCompleted) result.reply.completeError(refused);
      }
      for (final close in call.native.closes) {
        if (!close.reply.isCompleted) {
          close.reply.complete(
            FeedCloseReport(
              feedId: call.native.callId,
              outcome: const FeedCloseOutcome.clean(),
            ),
          );
        }
      }
    }
    // ACP 账号写入与 Native 账号共用同一 Settings 通道；未应答的受管调用与分页
    // 读取在这里以同一条 cancellation 证据收束，避免关闭时留下未结算的写入。
    for (final call in [
      ...configurationPort.acpSaves,
      ...configurationPort.acpRemovals,
    ]) {
      if (!call.native.resultCompleter.isCompleted) {
        call.native.resultCompleter.completeError(refused);
      }
    }
    for (final find in configurationPort.acpFinds) {
      if (!find.reply.isCompleted) find.reply.complete(null);
    }
    for (final page in configurationPort.acpPageCalls) {
      if (!page.reply.isCompleted) page.reply.completeError(refused);
    }
    for (final call in usagePort.calls) {
      if (!call.reply.isCompleted) call.reply.completeError(refused);
    }
    for (final call in modelPort.base.firstCalls) {
      if (!call.reply.isCompleted) call.reply.complete(null);
    }
    final reports = await Future.wait([
      usage.close(),
      configuration.close(),
      models.close(),
    ]);
    return CloseReport(
      unresolved: [for (final report in reports) ...report.unresolved],
    );
  }
}

final class SettingsConfigurationPort implements ConfigurationPort {
  SettingsConfigurationPort(List<String> ids, AgentProfileSnapshot? profile)
    : base = ProfileConfigurationPort(
        origin: SettingsAccountsFixture.origin,
        accounts: ids,
        profile: profile,
      );
  final ProfileConfigurationPort base;
  final saves = <RecordedConfigurationCall<UpdateAccountRequest>>[];
  final fields = <RecordedConfigurationCall<UpdateSettingsFieldRequest>>[];

  /// ACP 目录材料按**完整读取目标**声明且每次声明不可替换：pin 冻结声明时的
  /// 行集与总量，分页门只决定“何时交付/是否失败”，不能把行集换成别的版本。
  ///
  /// 声明同时表达该目标是否需要 base 的原生账号读取能力（[delegateBase]）：
  /// ACP-only 目标直接使用该材料 scope，不去问 base；需要委托的目标显式调用
  /// base，任何失败原样暴露。
  final acpMaterials = <ConfigurationReadTarget, AcpMaterialVersion>{};

  /// 每次真实 `header()` 读取的目标身份（按读取顺序，逐目标证明用）。
  final acpHeaderTargets = <ConfigurationReadTarget>[];
  final acpPageCalls = <RecordedAcpPageCall>[];
  final _acpPageWaiters = <int, Completer<void>>{};
  final acpSaves = <RecordedAcpCall<UpdateAcpAccountRequest>>[];
  final acpRemovals = <RecordedAcpCall<RemoveAcpAccountRequest>>[];
  final acpFinds = <RecordedAcpFindCall>[];
  final _saveWaiters =
      <int, Completer<RecordedConfigurationCall<UpdateAccountRequest>>>{};
  final _fieldWaiters =
      <int, Completer<RecordedConfigurationCall<UpdateSettingsFieldRequest>>>{};
  final _acpSaveWaiters =
      <int, Completer<RecordedAcpCall<UpdateAcpAccountRequest>>>{};
  final _acpRemovalWaiters =
      <int, Completer<RecordedAcpCall<RemoveAcpAccountRequest>>>{};
  final _acpFindWaiters = <int, Completer<RecordedAcpFindCall>>{};
  final followAt = <int, bool>{1: true};
  int _acpCallSequence = 0;
  Future<RecordedConfigurationCall<UpdateAccountRequest>> saved(int index) =>
      index < saves.length
      ? Future.value(saves[index])
      : _saveWaiters
            .putIfAbsent(
              index,
              Completer<RecordedConfigurationCall<UpdateAccountRequest>>.new,
            )
            .future;
  Future<RecordedConfigurationCall<UpdateSettingsFieldRequest>> field(
    int index,
  ) => index < fields.length
      ? Future.value(fields[index])
      : _fieldWaiters
            .putIfAbsent(
              index,
              Completer<RecordedConfigurationCall<UpdateSettingsFieldRequest>>
                  .new,
            )
            .future;

  /// Declares one immutable ACP material version and returns its read target.
  ///
  /// 同一 target 不能重复声明：已捕获版本不可替换，测试要换事实必须声明新的
  /// revision（新的原准入），而不是改写已 open 的 pin。
  ///
  /// 材料只声明该目标**自己的** ACP 列表。原生账号能力（账号数、ID、条目与
  /// 实体读取）不属于材料：只有显式 `delegateBase: true` 的 pin 才会向 base 取
  /// 一次冻结的原生账号能力；ACP-only 目标既不继承共享 base 的账号数/ID，也不
  /// 能 `lookupAccount`。
  ConfigurationReadTarget declareAcpMaterial({
    int entry = 1,
    int revision = 1,
    List<AcpAccountConfigurationRead> rows = const [],
    bool delegateBase = false,
  }) {
    final target = ConfigurationReadTarget(
      origin: SettingsAccountsFixture.origin,
      reference: ConfigurationReadRef(entry: entry, revision: revision),
    );
    if (acpMaterials.containsKey(target)) {
      throw StateError(
        'ACP material entry=${target.reference.entry} '
        'revision=${target.reference.revision} is already declared',
      );
    }
    acpMaterials[target] = AcpMaterialVersion(
      target: target,
      rows: rows,
      delegateBase: delegateBase,
    );
    return target;
  }

  /// Awaits the [index]-th scripted `acpAccounts` page read.
  Future<RecordedAcpPageCall> acpPage(int index) async {
    while (acpPageCalls.length <= index) {
      await _acpPageWaiters.putIfAbsent(index, Completer<void>.new).future;
    }
    return acpPageCalls[index];
  }

  Future<RecordedAcpCall<UpdateAcpAccountRequest>> acpSaved(int index) =>
      index < acpSaves.length
      ? Future.value(acpSaves[index])
      : _acpSaveWaiters
            .putIfAbsent(
              index,
              Completer<RecordedAcpCall<UpdateAcpAccountRequest>>.new,
            )
            .future;
  Future<RecordedAcpCall<RemoveAcpAccountRequest>> acpRemoved(int index) =>
      index < acpRemovals.length
      ? Future.value(acpRemovals[index])
      : _acpRemovalWaiters
            .putIfAbsent(
              index,
              Completer<RecordedAcpCall<RemoveAcpAccountRequest>>.new,
            )
            .future;
  Future<RecordedAcpFindCall> acpFound(int index) => index < acpFinds.length
      ? Future.value(acpFinds[index])
      : _acpFindWaiters
            .putIfAbsent(index, Completer<RecordedAcpFindCall>.new)
            .future;
  RecordedAcpCall<T> _recordAcp<T>(
    T request,
    OperationId operationId,
    List<RecordedAcpCall<T>> calls,
    Map<int, Completer<RecordedAcpCall<T>>> waiters,
  ) {
    final call = RecordedAcpCall<T>(
      request,
      ScriptedAcpAccountCall(
        callId: 'settings-acp-${++_acpCallSequence}',
        operationId: operationId,
      ),
    );
    calls.add(call);
    waiters.remove(calls.length - 1)?.complete(call);
    return call;
  }

  @override
  Future<AcpAccountCommandCall> saveAcpAccount(
    UpdateAcpAccountRequest request,
  ) async => _recordAcp(
    request,
    request.operationId,
    acpSaves,
    _acpSaveWaiters,
  ).native;
  @override
  Future<AcpAccountCommandCall> removeAcpAccount(
    RemoveAcpAccountRequest request,
  ) async => _recordAcp(
    request,
    request.operationId,
    acpRemovals,
    _acpRemovalWaiters,
  ).native;
  @override
  Future<AcpAccountCommandCall?> findAcpAccountCommand(
    OperationId operationId,
  ) {
    final call = RecordedAcpFindCall(operationId);
    acpFinds.add(call);
    _acpFindWaiters.remove(acpFinds.length - 1)?.complete(call);
    return call.reply.future;
  }

  @override
  Future<ConfigurationCommandCall> saveAccount(UpdateAccountRequest request) {
    final call = RecordedConfigurationCall(
      request,
      ScriptedConfigurationCommandCall(
        callId: 'settings-save-${saves.length}',
        operationId: request.operationId,
      ),
    );
    saves.add(call);
    _saveWaiters.remove(saves.length - 1)?.complete(call);
    return call.beginReply.future;
  }

  @override
  Future<ConfigurationCommandCall> applyField(
    UpdateSettingsFieldRequest request,
  ) {
    final call = RecordedConfigurationCall(
      request,
      ScriptedConfigurationCommandCall(
        callId: 'settings-field-${fields.length}',
        operationId: request.operationId,
      ),
    );
    fields.add(call);
    _fieldWaiters.remove(fields.length - 1)?.complete(call);
    return call.beginReply.future;
  }

  @override
  Future<FeedConnection<ConfigurationFrame>> openConfiguration() =>
      base.openConfiguration();
  @override
  Future<FeedConnection<AgentProfilesFrame>> openAgentProfiles() =>
      base.openAgentProfiles();
  @override
  Future<AgentProfilesReadConnection> openAgentProfilesRead(
    AgentProfilesReadRef reference, {
    required ProductReadOrigin origin,
  }) => base.openAgentProfilesRead(reference, origin: origin);
  @override
  Future<ProductSourceStatusReadConnection> openSourceStatus(
    ProductSourceStatusRef reference, {
    required ProductReadOrigin origin,
  }) => base.openSourceStatus(reference, origin: origin);
  @override
  Future<ConfigurationReadConnection> openConfigurationRead(
    ConfigurationReadRef reference, {
    required ProductReadOrigin origin,
  }) async {
    final target = ConfigurationReadTarget(
      origin: origin,
      reference: reference,
    );
    final material = acpMaterials[target];
    // 只有显式 `delegateBase` 的材料才向 base 取原生账号/实体能力；未声明的目标
    // 不是“ACP 空目录”，不在这里打开 base 冒充成功（失败原样暴露）。
    final delegate = material != null && material.delegateBase
        ? await base.openConfigurationRead(reference, origin: origin)
        : null;
    return _SettingsPin(
      target,
      delegate,
      material,
      // 被冻结的原生账号 ID 是**委托时**取得的：ACP-only 目标不继承共享 base 的
      // 账号数/ID，避免 header/lookup 泄露别人脚本里的原生账号事实。
      delegate == null ? null : List<String>.unmodifiable(base.accounts),
      followAt[reference.revision] ?? true,
      this,
    );
  }

  @override
  Never noSuchMethod(Invocation invocation) => throw UnsupportedError(
    'Unscripted Settings capability: ${invocation.memberName}',
  );
}

final class _SettingsPin implements ConfigurationReadConnection {
  _SettingsPin(
    this.target,
    this.base,
    this.material,
    this.ids,
    this.follow,
    this.fixture,
  );

  /// 本次读取的完整目标：header 只能在真实成功时按该原 target 登记。
  final ConfigurationReadTarget target;
  final ConfigurationReadConnection? base;

  /// 冻结的材料版本：pin 只读这一份行集/总量/目标。
  final AcpMaterialVersion? material;

  /// 只有 `delegateBase` 成功时被冻结的原生账号 ID；`null` 表示该目标没有声明
  /// 原生账号能力（ACP-only 材料），此时不做任何原生账号事实推断。
  final List<String>? ids;
  final bool follow;
  final SettingsConfigurationPort fixture;

  /// ACP 材料是 header 与分页读取的唯一事实源。
  ///
  /// 未声明目标不是“空目录”：本装配无法证明该目标有 ACP 目录，必须明确失败，
  /// 而不是把 base 的成功或 `0` 当成目录事实。已知为空只能声明 `rows: []`。
  AcpMaterialVersion _materialOrThrow(String what) {
    final material = this.material;
    if (material != null) return material;
    throw UnsupportedError(
      'Unscripted ACP material for Settings read '
      'entry=${target.reference.entry} revision=${target.reference.revision} '
      '($what): declare rows (an empty list is a real empty directory) or '
      'delegateBase for a non-ACP consumer',
    );
  }

  /// 原生账号能力只来自显式委托：没有委托就没有账号数/ID/实体事实可用。
  List<String> _nativeAccountsOrThrow(String what) {
    final native = ids;
    if (native != null) return native;
    throw UnsupportedError(
      'Native account capability is not delegated for Settings read '
      'entry=${target.reference.entry} revision=${target.reference.revision} '
      '($what): declare delegateBase to use the base native accounts',
    );
  }

  @override
  Future<ConfigurationReadHeader> header() async {
    final material = _materialOrThrow('header');
    final native = ids;
    // ACP-only 材料只声明 ACP 列表：这里的原生账号数是该目标自有的 0 条，
    // 不从 base 或任何最新快照取数。
    final nativeTotal = native == null ? 0 : native.length;
    fixture.acpHeaderTargets.add(target);
    return ConfigurationReadHeader(
      defaultAccountId: const ReadText.inline(text: 'account-0'),
      accounts: TypedListRef(listId: 1, total: nativeTotal),
      // 固定 scope 的 ACP 行集：`total` 只来自声明的冻结材料。
      acpAccounts: TypedListRef(listId: 40, total: material.total),
      modeModelRoutes: const TypedListRef(listId: 0, total: 0),
      roles: const TypedListRef(listId: 0, total: 0),
      permissionMode: const ReadText.inline(text: 'default'),
      instructions: const InstructionsSettingsRead(
        baseOverride: ReadText.inline(text: ''),
        developer: ReadText.inline(text: ''),
        user: ReadText.inline(text: ''),
        projectDocMaxBytes: 0,
        projectDocFallbackFilenames: TypedListRef(listId: 0, total: 0),
      ),
      skills: const SkillsSettingsRead(
        enabled: false,
        autoLearn: false,
        systemEnabled: false,
        projectDir: ReadText.inline(text: ''),
        userDir: ReadText.inline(text: ''),
        externalDirs: TypedListRef(listId: 0, total: 0),
        disabled: TypedListRef(listId: 0, total: 0),
        autoLearnMinToolCalls: 0,
      ),
      mcpServers: const TypedListRef(listId: 0, total: 0),
      general: GeneralSettingsRead(
        followActiveTurn: follow,
        compactTimeline: false,
        sidebarWidth: null,
        pinnedThreadIds: const TypedListRef(listId: 0, total: 0),
        pinnedProjectIds: const TypedListRef(listId: 0, total: 0),
      ),
      delegation: const DelegationSettings(
        mode: DelegationMode.profile,
        preference: DelegationPreference.balanced,
      ),
      webSearch: const WebSearchConfigurationRead(
        configuredMode: ReadText.inline(text: 'off'),
        contextSize: null,
        allowedDomains: TypedListRef(listId: 0, total: 0),
        country: null,
        region: null,
        city: null,
        timezone: null,
      ),
      deepseekWebSearch: const DeepSeekSearchConfigurationRead(
        configuredEnabled: false,
        configuredFetchEnabled: false,
      ),
    );
  }

  /// 固定页读取：每次调用登记一个可控点，由测试显式应答（行集/错误）或保持挂起。
  @override
  Future<AcpAccountConfigurationReadPage> acpAccounts(
    int listId, {
    int offset = 0,
    int limit = 32,
  }) {
    final material = _materialOrThrow(
      'acpAccounts listId=$listId offset=$offset',
    );
    final end = offset + limit < material.total
        ? offset + limit
        : material.total;
    final rows = offset >= material.total
        ? const <AcpAccountConfigurationRead>[]
        : material.rows.sublist(offset, end);
    final call = RecordedAcpPageCall(
      listId: listId,
      offset: offset,
      total: material.total,
      rows: rows,
    );
    fixture.acpPageCalls.add(call);
    fixture._acpPageWaiters.remove(fixture.acpPageCalls.length - 1)?.complete();
    return call.reply.future;
  }

  @override
  Future<ProductEntityRef?> lookupAccount(String id) async {
    final native = _nativeAccountsOrThrow('lookupAccount($id)');
    return native.contains(id)
        ? ProductEntityRef(entry: 100 + native.indexOf(id), revision: 1)
        : null;
  }

  @override
  Future<ConfigurationEntryPage> entries({int offset = 0, int limit = 32}) =>
      _delegate.entries(offset: offset, limit: limit);
  @override
  Future<ConfigurationEntityRead> entity(ProductEntityRef reference) =>
      _delegate.entity(reference);
  ConfigurationReadConnection get _delegate =>
      base ??
      (throw UnsupportedError(
        'Native account reads are not delegated for Settings read '
        'entry=${target.reference.entry} revision=${target.reference.revision}: '
        'declare delegateBase',
      ));
  @override
  void requestClose() => base?.requestClose();
  @override
  Future<FeedCloseReport> close() async =>
      base?.close() ??
      FeedCloseReport(
        feedId: 'settings-acp-pin',
        outcome: const FeedCloseOutcome.clean(),
      );
  @override
  Future<FeedCloseReport> retryClose() async =>
      base?.retryClose() ??
      FeedCloseReport(
        feedId: 'settings-acp-pin',
        outcome: const FeedCloseOutcome.clean(),
      );
  @override
  Never noSuchMethod(Invocation invocation) => throw UnsupportedError(
    'Unscripted Settings field: ${invocation.memberName}',
  );
}

final class SettingsModelsPort implements ModelsPort {
  SettingsModelsPort(List<String> ids)
    : base = ProfileModelsPort(
        origin: SettingsAccountsFixture.origin,
        accounts: ids,
        textEligibleAccounts: ids.toSet(),
      );
  final ProfileModelsPort base;
  bool duplicateModels = false;
  final templatesFeed = ScriptedFeed<AccountTemplatesFrame>(
    feedId: 'settings-templates',
    sequenceOf: (frame) =>
        frame is AccountTemplatesData ? frame.deliverySequence : null,
    isTerminal: (frame) => frame is! AccountTemplatesData,
  );
  Future<void> invalidateTextModels() async {
    base.declaredCatalogs.add(2);
    base.feed.emit(
      ModelCatalogFrame.data(
        deliverySequence: 2,
        event: ModelCatalogEvent.change(
          stamp: profileStamp(SettingsAccountsFixture.origin, 2),
          baseRevision: 1,
          value: ModelCatalogChange(
            header: ModelCatalogHeader(
              source: profileSource(2),
              catalogRevision: 2,
              updatedAt: 2,
              reference: const ModelCatalogReadRef(entry: 1, revision: 2),
            ),
            baseCollectionRevision: 1,
            collection: profileCollection(2, base.accounts.length),
            upserted: [
              for (var index = 0; index < base.accounts.length; index++)
                ProductEntityRef(entry: 100 + index, revision: 2),
            ],
            removedEntries: const [],
          ),
        ),
      ),
    );
    await base.feed.acknowledged(2);
  }

  @override
  Future<FeedConnection<ModelCatalogFrame>> openModelCatalog() =>
      base.openModelCatalog();
  @override
  Future<ModelCatalogReadConnection> openModelCatalogRead(
    ModelCatalogReadRef reference, {
    required ProductReadOrigin origin,
  }) async => _SettingsCatalogPin(
    await base.openModelCatalogRead(reference, origin: origin),
    reference.revision,
    duplicateModels,
  );
  @override
  Future<ProductSourceStatusReadConnection> openSourceStatus(
    ProductSourceStatusRef reference, {
    required ProductReadOrigin origin,
  }) => base.openSourceStatus(reference, origin: origin);
  @override
  Future<FeedConnection<AccountTemplatesFrame>> openAccountTemplates() async =>
      templatesFeed;
  @override
  Future<AccountTemplatesReadConnection> openAccountTemplatesRead(
    AccountTemplatesReadRef reference, {
    required ProductReadOrigin origin,
  }) async => _TemplatesPin();
  @override
  Never noSuchMethod(Invocation invocation) => throw UnsupportedError(
    'Unscripted Settings model capability: ${invocation.memberName}',
  );
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
  Future<String?> effortAfterModelSelection(
    String accountId,
    String modelId, {
    required String? candidate,
  }) =>
      base.effortAfterModelSelection(accountId, modelId, candidate: candidate);
  @override
  Future<ModelCatalogEntryPage> entries({
    int offset = 0,
    int limit = 32,
  }) async {
    final page = await base.entries(offset: offset, limit: limit);
    return ModelCatalogEntryPage(
      collection: page.collection,
      offset: page.offset,
      items: [for (final ref in page.items) ref.copyWith(revision: revision)],
      nextOffset: page.nextOffset,
    );
  }

  @override
  Future<ProductEntityRef?> lookupAccount(String accountId) async =>
      (await base.lookupAccount(accountId))?.copyWith(revision: revision);
  @override
  Future<ModelCatalogEntityRead> entity(ProductEntityRef reference) async {
    final entity = await base.entity(reference.copyWith(revision: 1));
    return entity.copyWith(
      reference: reference,
      value: duplicateModels
          ? entity.value.copyWith(
              effectiveModels: entity.value.effectiveModels.copyWith(total: 3),
            )
          : entity.value,
    );
  }

  @override
  Future<ModelDescriptorReadPage> models(
    int listId, {
    int offset = 0,
    int limit = 32,
  }) async {
    final page = await base.models(listId, offset: offset, limit: limit);
    if (!duplicateModels) return page;
    final model = page.items.single;
    return ModelDescriptorReadPage(
      listId: listId,
      offset: offset,
      total: 3,
      items: [
        model,
        model,
        model.copyWith(
          modelId: const ReadText.inline(text: 'image-generator'),
          typeSupport: const TypedListRef(listId: 21, total: 1),
        ),
      ],
      nextOffset: null,
    );
  }

  @override
  Future<ModelTypeSupportReadPage> typeSupport(
    int listId, {
    int offset = 0,
    int limit = 32,
  }) async {
    final page = await base.typeSupport(listId, offset: offset, limit: limit);
    return revision == 1
        ? page
        : page.copyWith(
            items: [
              ModelTypeSupportRead(
                modelType: ModelType.text,
                exclusions: const TypedListRef(listId: 22, total: 1),
              ),
            ],
          );
  }

  @override
  Future<ModelTypeExclusionReadPage> typeExclusions(
    int listId, {
    int offset = 0,
    int limit = 32,
  }) async => ModelTypeExclusionReadPage(
    listId: listId,
    offset: offset,
    total: 1,
    items: const [
      ModelTypeExclusionReadItem(
        value: ModelTypeExclusion.contextWindowUnknown,
      ),
    ],
    nextOffset: null,
  );
  @override
  Future<TextReadPage> strings(int listId, {int offset = 0, int limit = 32}) =>
      base.strings(listId, offset: offset, limit: limit);
  @override
  void requestClose() => base.requestClose();
  @override
  Future<FeedCloseReport> close() => base.close();
  @override
  Future<FeedCloseReport> retryClose() => base.retryClose();
  @override
  Never noSuchMethod(Invocation invocation) => throw UnsupportedError(
    'Unscripted catalog field: ${invocation.memberName}',
  );
}

final class _TemplatesPin extends ProfileNativePin
    implements AccountTemplatesReadConnection {
  _TemplatesPin() : super('settings-templates-pin');
  @override
  Future<AccountTemplatesReadHeader> header() async =>
      const AccountTemplatesReadHeader(
        schemaVersion: 1,
        revision: ReadText.inline(text: 'settings-template'),
        templates: TypedListRef(listId: 1, total: 1),
        modelCatalogs: TypedListRef(listId: 0, total: 0),
      );
  @override
  Future<AccountTemplatesEntryPage> entries({
    int offset = 0,
    int limit = 32,
  }) async => AccountTemplatesEntryPage(
    collection: ProductCollectionRef(entry: 2, revision: 1, total: 1),
    offset: 0,
    items: const [ProductEntityRef(entry: 10, revision: 1)],
    nextOffset: null,
  );
  @override
  Future<AccountTemplatesEntityRead> entity(ProductEntityRef reference) async =>
      AccountTemplatesEntityRead(
        reference: reference,
        value: const AccountTemplateRead(
          id: ReadText.inline(text: 'template'),
          displayName: ReadText.inline(text: 'Template'),
          description: null,
          baseUrl: ReadText.inline(text: 'https://settings.invalid'),
          credential: CredentialDescriptorRead(
            label: ReadText.inline(text: 'Key'),
            envVar: null,
          ),
          modelCatalogId: ReadText.inline(text: 'catalog'),
          protocol: ReadText.inline(text: 'openai'),
          suggestedModelId: ReadText.inline(text: 'text'),
          iconKey: null,
          serviceCapabilities: AccountServiceCapabilitiesRead(
            webSearch: WebSearchServiceCapabilitiesRead(
              hostedResponses: false,
              hostedDialect: ReadText.inline(text: 'none'),
              standalone: null,
            ),
            promptCacheDialect: ReadText.inline(text: 'none'),
            responsesProgrammaticToolCalling: false,
          ),
        ),
      );
}

/// One recorded ACP account write intent plus its retained native call.
final class RecordedAcpCall<T> {
  RecordedAcpCall(this.request, this.native);
  final T request;
  final ScriptedAcpAccountCall native;
}

/// 一个不可变 ACP 材料版本：完整读取目标 + 冻结 ACP 行集 + 是否委托 base。
///
/// 材料只表达该目标自己的 ACP 目录；原生账号数/ID/条目/实体不属于材料，
/// 只能由 `delegateBase: true` 的 pin 从 base 冻结一次后使用。
final class AcpMaterialVersion {
  AcpMaterialVersion({
    required this.target,
    required List<AcpAccountConfigurationRead> rows,
    required this.delegateBase,
  }) : rows = List.unmodifiable(rows);
  final ConfigurationReadTarget target;
  final List<AcpAccountConfigurationRead> rows;
  final bool delegateBase;
  int get total => rows.length;
}

/// One bounded `acpAccounts` page read over a **frozen** material slice.
///
/// 门只决定交付时机或失败：[complete] 交付该冻结切片，[fail] 暴露真实读取失败；
/// 二者都不能把 total/rows 换成另一个材料版本。
final class RecordedAcpPageCall {
  RecordedAcpPageCall({
    required this.listId,
    required this.offset,
    required this.total,
    required List<AcpAccountConfigurationRead> rows,
  }) : rows = List.unmodifiable(rows);
  final int listId;
  final int offset;

  /// The header `TypedListRef.total` this page must match.
  final int total;
  final List<AcpAccountConfigurationRead> rows;
  final reply = Completer<AcpAccountConfigurationReadPage>();

  /// Delivers the frozen slice declared by the pinned material.
  void complete() {
    final end = offset + rows.length;
    reply.complete(
      AcpAccountConfigurationReadPage(
        listId: listId,
        offset: offset,
        total: total,
        items: rows,
        nextOffset: end == total ? null : end,
      ),
    );
  }

  /// A real read failure: the caller sees the original typed cause.
  void fail(Object error) => reply.completeError(error);
}

/// One scripted `findAcpAccountCommand` lookup: joining the original call only.
final class RecordedAcpFindCall {
  RecordedAcpFindCall(this.operationId);
  final OperationId operationId;
  final reply = Completer<AcpAccountCommandCall?>();
  void notFound() => reply.complete(null);
  void joins(AcpAccountCommandCall call) => reply.complete(call);
  void fail(Object error) => reply.completeError(error);
}

/// A scripted retained ACP account call: real identity fields, one terminal
/// result, and honest close reports. It never applies or retries a write.
final class ScriptedAcpAccountCall implements AcpAccountCommandCall {
  ScriptedAcpAccountCall({required this.callId, required this.operationId});

  @override
  final String callId;
  @override
  final OperationId operationId;
  final resultCompleter = Completer<AcpAccountCommandReply>();
  int resultCalls = 0;
  int requestCloseCalls = 0;
  int closeCalls = 0;
  int retryCloseCalls = 0;

  /// The real Settings receipt plus the configuration target captured by the
  /// write; the Repository consumes that target itself.
  void accept(AcpAccountCommandReply reply) => resultCompleter.complete(reply);
  void reject(CommandDispatchFailure failure) =>
      resultCompleter.completeError(failure);
  void fail(StudioFailure failure) => resultCompleter.completeError(failure);

  @override
  Future<AcpAccountCommandReply> result() {
    resultCalls++;
    return resultCompleter.future;
  }

  @override
  void requestClose() => requestCloseCalls++;

  @override
  Future<FeedCloseReport> close() {
    closeCalls++;
    return Future.value(
      FeedCloseReport(feedId: callId, outcome: const FeedCloseOutcome.clean()),
    );
  }

  @override
  Future<FeedCloseReport> retryClose() {
    retryCloseCalls++;
    return Future.value(
      FeedCloseReport(feedId: callId, outcome: const FeedCloseOutcome.clean()),
    );
  }
}
