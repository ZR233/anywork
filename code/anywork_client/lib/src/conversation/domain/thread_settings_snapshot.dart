import 'package:freezed_annotation/freezed_annotation.dart';

import '../../../configuration.dart';
import '../../../models.dart';

part 'thread_settings_snapshot.freezed.dart';

/// Direct command evidence. Config and catalog keep their independent clocks;
/// neither acquires a product origin or becomes a canonical Repository snapshot.
@Freezed(toStringOverride: false)
final class ThreadSettingsSnapshot with _$ThreadSettingsSnapshot {
  const ThreadSettingsSnapshot({required this.config, required this.catalog});
  final ThreadSettingsConfigSnapshot config;
  final ThreadSettingsCatalogSnapshot catalog;
}

@Freezed(toStringOverride: false)
final class ThreadSettingsConfigSnapshot with _$ThreadSettingsConfigSnapshot {
  const ThreadSettingsConfigSnapshot({
    required this.revision,
    required this.updatedAt,
    required this.settings,
  });
  final int revision;
  final int updatedAt;
  final ThreadSettingsValue settings;
}

@Freezed(toStringOverride: false)
final class ThreadSettingsValue with _$ThreadSettingsValue {
  ThreadSettingsValue({
    required this.defaultAccountId,
    required List<ThreadSettingsAccount> accounts,
    required List<ModeModelRoute> modeModelRoutes,
    required List<RoleModelRoute> roles,
    required this.permissionMode,
    required this.instructions,
    required this.skills,
    required List<McpConfiguration> mcpServers,
    required this.general,
    required this.delegation,
    required this.webSearch,
    required this.deepseekWebSearch,
  }) : accounts = List.unmodifiable(accounts),
       modeModelRoutes = List.unmodifiable(modeModelRoutes),
       roles = List.unmodifiable(roles),
       mcpServers = List.unmodifiable(mcpServers);
  final String? defaultAccountId;
  final List<ThreadSettingsAccount> accounts;
  final List<ModeModelRoute> modeModelRoutes;
  final List<RoleModelRoute> roles;
  final String permissionMode;
  final InstructionsSettings instructions;
  final SkillsSettings skills;
  final List<McpConfiguration> mcpServers;
  final GeneralSettings general;
  final DelegationSettings delegation;
  final ThreadWebSearchSettings webSearch;
  final ThreadDeepSeekSearchSettings deepseekWebSearch;
}

/// Reuses the desired account value and preserves the additional native
/// capability/default-model evidence absent from AccountConfiguration.
@Freezed(toStringOverride: false)
final class ThreadSettingsAccount with _$ThreadSettingsAccount {
  const ThreadSettingsAccount({
    required this.configuration,
    required this.credentialRequired,
    required this.capabilitySource,
    required this.hostedWebSearch,
    required this.hostedWebSearchDialect,
    required this.standaloneWebSearch,
    required this.promptCacheDialect,
    required this.responsesProgrammaticToolCalling,
    required this.defaultModelId,
  });
  final AccountConfiguration configuration;
  final bool credentialRequired;
  final String capabilitySource;
  final bool hostedWebSearch;
  final String hostedWebSearchDialect;
  final String? standaloneWebSearch;
  final String promptCacheDialect;
  final bool responsesProgrammaticToolCalling;
  final String defaultModelId;
}

@Freezed(toStringOverride: false)
final class ThreadWebSearchSettings with _$ThreadWebSearchSettings {
  const ThreadWebSearchSettings({
    required this.configuration,
    required this.effective,
  });
  final WebSearchConfiguration configuration;
  final EffectiveWebSearch effective;
}

@Freezed(toStringOverride: false)
final class ThreadDeepSeekSearchSettings with _$ThreadDeepSeekSearchSettings {
  const ThreadDeepSeekSearchSettings({
    required this.configuration,
    required this.effective,
  });
  final DeepSeekSearchConfiguration configuration;
  final EffectiveDeepSeekSearch effective;
}

@Freezed(toStringOverride: false)
final class ThreadSettingsCatalogSnapshot with _$ThreadSettingsCatalogSnapshot {
  ThreadSettingsCatalogSnapshot({
    required this.revision,
    required this.updatedAt,
    required List<ThreadSettingsCatalogAccount> accounts,
  }) : accounts = List.unmodifiable(accounts);
  final int revision;
  final int updatedAt;
  final List<ThreadSettingsCatalogAccount> accounts;
}

@Freezed(toStringOverride: false)
final class ThreadSettingsCatalogAccount with _$ThreadSettingsCatalogAccount {
  ThreadSettingsCatalogAccount({
    required this.accountId,
    required List<ModelDescriptor> effectiveModels,
    required this.modelCatalog,
  }) : effectiveModels = List.unmodifiable(effectiveModels);
  final String accountId;
  final List<ModelDescriptor> effectiveModels;
  final ModelCatalogStatus modelCatalog;
}
