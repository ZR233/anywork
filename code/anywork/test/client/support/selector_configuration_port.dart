import 'dart:async';

import 'package:anywork_client/configuration_ports.dart';
import 'package:anywork_client/models.dart';
import 'package:anywork_client/modes.dart';
import 'package:anywork_client/resources_ports.dart';

import '../../../../anywork_client/test/support/configuration_start_fixture.dart';
import '../../../../anywork_client/test/support/profile_configuration_port.dart';
import '../../../../anywork_client/test/support/profile_native_pin.dart';

const selectorOrigin = ProductReadOrigin(
  ownerEpoch: 'selector-native',
  incarnation: 1,
);
const selectorInitialRoute = ModelSelection(
  model: AccountModelKey(accountId: 'account-0', modelId: 'text'),
  effort: 'low',
);
const selectorDefaults = DelegationSettings(
  mode: DelegationMode.profile,
  preference: DelegationPreference.balanced,
);
const selectorPair = ConfigurationRoleReadTarget(
  reference: ConfigurationRoleReadRef(entry: 70, revision: 1),
  configuration: ConfigurationReadTarget(
    origin: selectorOrigin,
    reference: ConfigurationReadRef(entry: 1, revision: 1),
  ),
  catalog: ModelCatalogReadTarget(
    origin: selectorOrigin,
    reference: ModelCatalogReadRef(entry: 1, revision: 1),
  ),
  stamp: ConfigProjectionStamp(
    settingsRevision: 1,
    modelCatalogRevision: 1,
    closing: false,
  ),
);

/// Declared native configuration and Start query gates. In particular, there is
/// no Dart copy of native default-model or effort normalization policy here.
final class SelectorConfigurationPort implements ConfigurationPort {
  SelectorConfigurationPort() {
    base.declareRolePair(selectorPair, initial: true);
  }
  final base = ProfileConfigurationPort(
    origin: selectorOrigin,
    accounts: const ['account-0', 'account-1'],
  );
  final opens = <ConfigurationStartOpen>[];
  final firstStartOpen = Completer<ConfigurationStartOpen>();
  final routes = <int, ModelSelection>{1: selectorInitialRoute};
  // Script transport failure independently of the immutable scope material.
  // This also applies to a scope already pinned before a refresh is attempted.
  StudioFailure? configurationHeaderFailure;
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
  Future<ConfigurationReadConnection> openConfigurationRead(
    ConfigurationReadRef reference, {
    required ProductReadOrigin origin,
  }) async => _SelectorSettingsPin(
    await base.openConfigurationRead(reference, origin: origin),
    routes[reference.revision] ?? selectorInitialRoute,
    headerFailure: () => configurationHeaderFailure,
  );
  @override
  Future<ConfigurationStartReadConnection> openStartRead(
    ConfigurationRoleReadTarget sources,
  ) {
    final call = ConfigurationStartOpen(opens.length, sources);
    opens.add(call);
    if (!firstStartOpen.isCompleted) firstStartOpen.complete(call);
    return call.reply.future;
  }

  @override
  Future<ProductSourceStatusReadConnection> openSourceStatus(
    ProductSourceStatusRef reference, {
    required ProductReadOrigin origin,
  }) => base.openSourceStatus(reference, origin: origin);
  @override
  Never noSuchMethod(Invocation invocation) => throw UnsupportedError(
    'Unscripted selector configuration: ${invocation.memberName}',
  );
}

final class _SelectorSettingsPin extends ProfileNativePin
    implements ConfigurationReadConnection {
  _SelectorSettingsPin(this.base, this.route, {required this.headerFailure})
    : super('selector-settings-material');
  final ConfigurationReadConnection base;
  final ModelSelection route;
  final StudioFailure? Function() headerFailure;
  @override
  Future<ConfigurationReadHeader> header() async {
    final failure = headerFailure();
    if (failure != null) throw failure;
    return const ConfigurationReadHeader(
      defaultAccountId: ReadText.inline(text: 'account-0'),
      accounts: TypedListRef(listId: 1, total: 2),
      // 该环境没有 ACP 接入：固定空列表，不伪造目录读取结果。
      acpAccounts: TypedListRef(listId: 0, total: 0),
      modeModelRoutes: TypedListRef(listId: 50, total: 1),
      roles: TypedListRef(listId: 0, total: 0),
      permissionMode: ReadText.inline(text: 'default'),
      instructions: InstructionsSettingsRead(
        baseOverride: ReadText.inline(text: ''),
        developer: ReadText.inline(text: ''),
        user: ReadText.inline(text: ''),
        projectDocMaxBytes: 0,
        projectDocFallbackFilenames: TypedListRef(listId: 0, total: 0),
      ),
      skills: SkillsSettingsRead(
        enabled: false,
        autoLearn: false,
        systemEnabled: false,
        projectDir: ReadText.inline(text: ''),
        userDir: ReadText.inline(text: ''),
        externalDirs: TypedListRef(listId: 0, total: 0),
        disabled: TypedListRef(listId: 0, total: 0),
        autoLearnMinToolCalls: 0,
      ),
      mcpServers: TypedListRef(listId: 0, total: 0),
      general: GeneralSettingsRead(
        followActiveTurn: false,
        compactTimeline: false,
        sidebarWidth: 336,
        pinnedThreadIds: TypedListRef(listId: 0, total: 0),
        pinnedProjectIds: TypedListRef(listId: 0, total: 0),
      ),
      delegation: selectorDefaults,
      webSearch: WebSearchConfigurationRead(
        configuredMode: ReadText.inline(text: 'off'),
        contextSize: null,
        allowedDomains: TypedListRef(listId: 0, total: 0),
        country: null,
        region: null,
        city: null,
        timezone: null,
      ),
      deepseekWebSearch: DeepSeekSearchConfigurationRead(
        configuredEnabled: false,
        configuredFetchEnabled: false,
      ),
    );
  }

  /// 本环境的 header 声明 `acpAccounts.total == 0`：正确的读取方不会分页。
  /// 因此任何分页请求都是未脚本化的误用，显式失败而不是返回空成功。
  final acpPageRequests = <({int listId, int offset, int limit})>[];

  @override
  Future<AcpAccountConfigurationReadPage> acpAccounts(
    int listId, {
    int offset = 0,
    int limit = 32,
  }) {
    acpPageRequests.add((listId: listId, offset: offset, limit: limit));
    throw UnsupportedError(
      'Unscripted selector ACP account page read: listId=$listId '
      'offset=$offset limit=$limit',
    );
  }

  @override
  Future<ConfigurationEntryPage> entries({int offset = 0, int limit = 32}) =>
      base.entries(offset: offset, limit: limit);
  @override
  Future<ConfigurationEntityRead> entity(ProductEntityRef reference) =>
      base.entity(reference);
  @override
  Future<ProductEntityRef?> lookupAccount(String id) async =>
      const ['account-0', 'account-1'].contains(id)
      ? ProductEntityRef(entry: id == 'account-0' ? 100 : 101, revision: 1)
      : null;
  @override
  Future<ModeModelRouteReadPage> modeRoutes(
    int listId, {
    int offset = 0,
    int limit = 32,
  }) async => ModeModelRouteReadPage(
    listId: listId,
    offset: offset,
    total: 1,
    items: [
      ModeModelRouteRead(
        modeId: ReadText.inline(text: ThreadModeId.simple.id),
        accountId: ReadText.inline(text: route.model.accountId),
        modelId: ReadText.inline(text: route.model.modelId),
        effort: ReadText.inline(text: route.effort!),
      ),
    ],
    nextOffset: null,
  );
  @override
  void requestClose() {
    base.requestClose();
    super.requestClose();
  }

  @override
  Future<FeedCloseReport> close() => base.close();
  @override
  Future<FeedCloseReport> retryClose() => base.retryClose();
}
