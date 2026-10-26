import '../../../models.dart' show ModelInputCapability;
import '../../../models_ports.dart'
    show ModelInputCapabilityRead, ModelInputSourceReadItem;
import '../../../resources.dart';
import '../../acp/domain/acp_values.dart';
import '../domain/configuration_values.dart';
import 'configuration_port.dart';
import 'configuration_read_fields.dart';
import 'configuration_reads.dart';

final class ConfigurationReader {
  const ConfigurationReader(this.scope);
  final ConfigurationReadConnection scope;

  Future<String> text(ReadText value) =>
      readConfigurationText(value, scope.text);
  Future<String?> optional(ReadText? value) async =>
      value == null ? null : await text(value);

  Future<List<String>> strings(TypedListRef reference) async {
    final items = await readConfigurationList<TextReadItem>(reference, (
      offset,
    ) async {
      final page = await scope.strings(
        reference.listId,
        offset: offset,
        limit: 32,
      );
      return (
        listId: page.listId,
        offset: page.offset,
        total: page.total,
        items: page.items,
        nextOffset: page.nextOffset,
      );
    });
    return List.unmodifiable([
      for (final item in items) await text(item.value),
    ]);
  }

  /// 有界读取 ACP 接入目录：ID/名称沿连续 UTF8 文本读取，供应商与连接代次按原值。
  ///
  /// 页身份、偏移、总量、进展与续页由 [readConfigurationList] 校验；重复身份由
  /// 目录级校验统一判定，不在这里另造第二套规则，也不重新推导连接代次。
  Future<List<AcpAccountSettings>> acpAccounts(TypedListRef reference) async {
    final rows = await readConfigurationList<AcpAccountConfigurationRead>(
      reference,
      (offset) async {
        final page = await scope.acpAccounts(
          reference.listId,
          offset: offset,
          limit: 32,
        );
        return (
          listId: page.listId,
          offset: page.offset,
          total: page.total,
          items: page.items,
          nextOffset: page.nextOffset,
        );
      },
    );
    return List.unmodifiable([
      for (final row in rows)
        AcpAccountSettings(
          accountId: await text(row.accountId),
          name: await text(row.name),
          provider: row.provider,
          connectionRevision: row.connectionRevision,
        ),
    ]);
  }

  Future<ModelInputCapability> inputCapability(
    ModelInputCapabilityRead value,
  ) async {
    final items = await readConfigurationList<ModelInputSourceReadItem>(
      value.sources,
      (offset) async {
        final page = await scope.inputSources(
          value.sources.listId,
          offset: offset,
          limit: 32,
        );
        return (
          listId: page.listId,
          offset: page.offset,
          total: page.total,
          items: page.items,
          nextOffset: page.nextOffset,
        );
      },
    );
    return ModelInputCapability(
      modality: value.modality,
      sources: List.unmodifiable([for (final item in items) item.value]),
      maxCount: value.maxCount,
      maxBytes: value.maxBytes,
      maxTotalBytes: value.maxTotalBytes,
      maxWidth: value.maxWidth,
      maxHeight: value.maxHeight,
      mediaTypes: await strings(value.mediaTypes),
    );
  }

  Future<CustomModelConfiguration> customModel(
    CustomModelConfigurationRead value,
  ) async {
    final capabilities = await readConfigurationList<ModelInputCapabilityRead>(
      value.inputCapabilities,
      (offset) async {
        final page = await scope.inputCapabilities(
          value.inputCapabilities.listId,
          offset: offset,
          limit: 32,
        );
        return (
          listId: page.listId,
          offset: page.offset,
          total: page.total,
          items: page.items,
          nextOffset: page.nextOffset,
        );
      },
    );
    return CustomModelConfiguration(
      inputCapabilities: List.unmodifiable([
        for (final item in capabilities) await inputCapability(item),
      ]),
      contextWindow: value.contextWindow,
      maxOutputTokens: value.maxOutputTokens,
      modelId: await text(value.modelId),
      displayName: await text(value.displayName),
      reasoningEfforts: await strings(value.reasoningEfforts),
      baseInstructions: await text(value.baseInstructions),
      wireApi: await text(value.wireApi),
      supportedConnectionModes: await strings(value.supportedConnectionModes),
      defaultConnectionMode: await text(value.defaultConnectionMode),
    );
  }

  Future<AccountConfiguration> account(AccountConfigurationRead value) async {
    final custom = await readConfigurationList<CustomModelConfigurationRead>(
      value.customModels,
      (offset) async {
        final page = await scope.customModels(
          value.customModels.listId,
          offset: offset,
          limit: 32,
        );
        return (
          listId: page.listId,
          offset: page.offset,
          total: page.total,
          items: page.items,
          nextOffset: page.nextOffset,
        );
      },
    );
    final connections = await readConfigurationList<ModelConnectionRead>(
      value.modelConnectionModes,
      (offset) async {
        final page = await scope.modelConnections(
          value.modelConnectionModes.listId,
          offset: offset,
          limit: 32,
        );
        return (
          listId: page.listId,
          offset: page.offset,
          total: page.total,
          items: page.items,
          nextOffset: page.nextOffset,
        );
      },
    );
    final limits = await readConfigurationList<ModelAutoCompactRead>(
      value.modelAutoCompactLimits,
      (offset) async {
        final page = await scope.autoCompactOverrides(
          value.modelAutoCompactLimits.listId,
          offset: offset,
          limit: 32,
        );
        return (
          listId: page.listId,
          offset: page.offset,
          total: page.total,
          items: page.items,
          nextOffset: page.nextOffset,
        );
      },
    );
    return AccountConfiguration(
      billingKind: value.billingKind,
      billingKindOverride: value.billingKindOverride,
      disabledModels: await strings(value.disabledModels),
      accountId: await text(value.accountId),
      templateId: await optional(value.templateId),
      protocol: await text(value.protocol),
      name: await text(value.name),
      baseUrl: await text(value.baseUrl),
      hasBearerToken: value.hasBearerToken,
      usageQueryRevision: value.usageQueryRevision,
      bearerTokenEnv: await optional(value.bearerTokenEnv),
      customModels: List.unmodifiable([
        for (final item in custom) await customModel(item),
      ]),
      modelConnectionModes: List.unmodifiable([
        for (final item in connections)
          ModelConnection(
            modelId: await text(item.modelId),
            connectionMode: await text(item.connectionMode),
          ),
      ]),
      modelAutoCompactLimits: List.unmodifiable([
        for (final item in limits)
          ModelAutoCompact(
            modelId: await text(item.modelId),
            overrideLimit: item.overrideLimit,
          ),
      ]),
      catalogId: await optional(value.catalogId),
    );
  }

  Future<InstructionsSettings> instructions(
    InstructionsSettingsRead value,
  ) async => InstructionsSettings(
    baseOverride: await text(value.baseOverride),
    developer: await text(value.developer),
    user: await text(value.user),
    projectDocMaxBytes: value.projectDocMaxBytes,
    projectDocFallbackFilenames: await strings(
      value.projectDocFallbackFilenames,
    ),
  );

  Future<SkillsSettings> skills(SkillsSettingsRead value) async =>
      SkillsSettings(
        enabled: value.enabled,
        autoLearn: value.autoLearn,
        systemEnabled: value.systemEnabled,
        projectDir: await text(value.projectDir),
        userDir: await text(value.userDir),
        externalDirs: await strings(value.externalDirs),
        disabled: await strings(value.disabled),
        autoLearnMinToolCalls: value.autoLearnMinToolCalls,
      );

  Future<GeneralSettings> general(GeneralSettingsRead value) async =>
      GeneralSettings(
        followActiveTurn: value.followActiveTurn,
        compactTimeline: value.compactTimeline,
        sidebarWidth: value.sidebarWidth,
        pinnedThreadIds: await strings(value.pinnedThreadIds),
        pinnedProjectIds: await strings(value.pinnedProjectIds),
      );

  Future<WebSearchConfiguration> webSearch(
    WebSearchConfigurationRead value,
  ) async => WebSearchConfiguration(
    configuredMode: await text(value.configuredMode),
    contextSize: await optional(value.contextSize),
    allowedDomains: await strings(value.allowedDomains),
    country: await optional(value.country),
    region: await optional(value.region),
    city: await optional(value.city),
    timezone: await optional(value.timezone),
  );

  DeepSeekSearchConfiguration deepSeekSearch(
    DeepSeekSearchConfigurationRead value,
  ) => DeepSeekSearchConfiguration(
    configuredEnabled: value.configuredEnabled,
    configuredFetchEnabled: value.configuredFetchEnabled,
  );

  Future<List<ModeModelRoute>> modeRoutes(TypedListRef reference) async {
    final items = await readConfigurationList<ModeModelRouteRead>(reference, (
      offset,
    ) async {
      final page = await scope.modeRoutes(
        reference.listId,
        offset: offset,
        limit: 32,
      );
      return (
        listId: page.listId,
        offset: page.offset,
        total: page.total,
        items: page.items,
        nextOffset: page.nextOffset,
      );
    });
    return List.unmodifiable([
      for (final item in items)
        ModeModelRoute(
          modeId: await text(item.modeId),
          accountId: await text(item.accountId),
          modelId: await text(item.modelId),
          effort: await text(item.effort),
        ),
    ]);
  }

  Future<List<RoleModelRoute>> roleRoutes(TypedListRef reference) async {
    final items = await readConfigurationList<RoleModelRouteRead>(reference, (
      offset,
    ) async {
      final page = await scope.roleRoutes(
        reference.listId,
        offset: offset,
        limit: 32,
      );
      return (
        listId: page.listId,
        offset: page.offset,
        total: page.total,
        items: page.items,
        nextOffset: page.nextOffset,
      );
    });
    return List.unmodifiable([
      for (final item in items)
        RoleModelRoute(
          key: await text(item.key),
          accountId: await text(item.accountId),
          modelId: await text(item.modelId),
          effort: await text(item.effort),
        ),
    ]);
  }

  Future<List<McpConfiguration>> mcp(TypedListRef reference) async {
    final items = await readConfigurationList<McpConfigurationRead>(reference, (
      offset,
    ) async {
      final page = await scope.mcpConfigs(
        reference.listId,
        offset: offset,
        limit: 32,
      );
      return (
        listId: page.listId,
        offset: page.offset,
        total: page.total,
        items: page.items,
        nextOffset: page.nextOffset,
      );
    });
    return List.unmodifiable([
      for (final item in items)
        McpConfiguration(
          id: await text(item.id),
          transport: await text(item.transport),
          endpoint: await text(item.endpoint),
          configuration: item.configuration,
          sourceKind: await text(item.sourceKind),
          mutationPolicy: await text(item.mutationPolicy),
        ),
    ]);
  }
}
