import 'studio_enums.dart';

class RoleSettingsView {
  const RoleSettingsView({
    required this.key,
    required this.accountId,
    required this.modelId,
    required this.effort,
  });

  final String key;
  final String accountId;
  final String modelId;
  final String effort;
}

class ModeModelRouteView {
  const ModeModelRouteView({
    required this.modeId,
    required this.accountId,
    required this.modelId,
    required this.effort,
  });

  final ThreadModeId modeId;
  final String accountId;
  final String modelId;
  final String effort;
}

sealed class McpScope {
  const McpScope();
  const factory McpScope.host() = HostMcpScope;
  const factory McpScope.ssh({required String sshAlias}) = SshMcpScope;

  String get key => switch (this) {
    HostMcpScope() => 'host',
    SshMcpScope(:final sshAlias) => 'ssh:$sshAlias',
  };
}

final class HostMcpScope extends McpScope {
  const HostMcpScope();

  @override
  bool operator ==(Object other) => other is HostMcpScope;

  @override
  int get hashCode => 0x4d435001;
}

final class SshMcpScope extends McpScope {
  const SshMcpScope({required this.sshAlias});
  final String sshAlias;

  @override
  bool operator ==(Object other) =>
      other is SshMcpScope && sshAlias == other.sshAlias;

  @override
  int get hashCode => Object.hash(0x4d435002, sshAlias);
}

class McpDocumentRef {
  const McpDocumentRef({required this.scope, required this.relativePath});

  final McpScope scope;
  final String relativePath;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is McpDocumentRef &&
          scope == other.scope &&
          relativePath == other.relativePath;

  @override
  int get hashCode => Object.hash(scope, relativePath);
}

enum McpConfigStatusKind {
  enabled,
  disabled,
  shadowedDisable,
  missingPrereq,
  invalidDocument,
}

enum McpEffectiveSource {
  hostServer,
  hostBuiltin,
  inheritedHostServer,
  inheritedHostBuiltin,
  sshOverrideServer,
  sshOverrideBuiltin,
  sshDisabledTombstone,
  invalidFile,
}

sealed class McpExecutionLocation {
  const McpExecutionLocation();
  const factory McpExecutionLocation.hostLocal() =
      HostLocalMcpExecutionLocation;
  const factory McpExecutionLocation.hostRemoteStreamableHttp() =
      HostRemoteStreamableHttpMcpExecutionLocation;
  const factory McpExecutionLocation.sshRemote({required String sshAlias}) =
      SshRemoteMcpExecutionLocation;
  const factory McpExecutionLocation.sshRemoteStreamableHttp({
    required String sshAlias,
  }) = SshRemoteStreamableHttpMcpExecutionLocation;
}

final class HostLocalMcpExecutionLocation extends McpExecutionLocation {
  const HostLocalMcpExecutionLocation();

  @override
  bool operator ==(Object other) => other is HostLocalMcpExecutionLocation;

  @override
  int get hashCode => 0x4d435011;
}

final class HostRemoteStreamableHttpMcpExecutionLocation
    extends McpExecutionLocation {
  const HostRemoteStreamableHttpMcpExecutionLocation();

  @override
  bool operator ==(Object other) =>
      other is HostRemoteStreamableHttpMcpExecutionLocation;

  @override
  int get hashCode => 0x4d435012;
}

final class SshRemoteMcpExecutionLocation extends McpExecutionLocation {
  const SshRemoteMcpExecutionLocation({required this.sshAlias});
  final String sshAlias;

  @override
  bool operator ==(Object other) =>
      other is SshRemoteMcpExecutionLocation && sshAlias == other.sshAlias;

  @override
  int get hashCode => Object.hash(0x4d435013, sshAlias);
}

final class SshRemoteStreamableHttpMcpExecutionLocation
    extends McpExecutionLocation {
  const SshRemoteStreamableHttpMcpExecutionLocation({required this.sshAlias});
  final String sshAlias;

  @override
  bool operator ==(Object other) =>
      other is SshRemoteStreamableHttpMcpExecutionLocation &&
      sshAlias == other.sshAlias;

  @override
  int get hashCode => Object.hash(0x4d435014, sshAlias);
}

class McpCatalogEntry {
  const McpCatalogEntry({
    required this.id,
    this.document,
    required this.configStatus,
    required this.effectiveSource,
    this.executionLocation,
    this.transport,
    this.endpointSummary,
    this.builtIn = false,
    this.inheritedFromHost = false,
    this.overriddenInScope = false,
    this.canOverrideInSsh = false,
    this.canDisableInSsh = false,
    this.canRestoreInheritance = false,
    this.message,
  });

  final String id;
  final McpDocumentRef? document;
  final McpConfigStatusKind configStatus;
  final McpEffectiveSource effectiveSource;
  final McpExecutionLocation? executionLocation;
  final String? transport;
  final String? endpointSummary;
  final bool builtIn;
  final bool inheritedFromHost;
  final bool overriddenInScope;
  final bool canOverrideInSsh;
  final bool canDisableInSsh;
  final bool canRestoreInheritance;
  final String? message;

  bool get enabled => configStatus == McpConfigStatusKind.enabled;
}

class McpDocumentDiagnostic {
  const McpDocumentDiagnostic({
    required this.document,
    this.id,
    required this.code,
    required this.message,
  });

  final McpDocumentRef document;
  final String? id;
  final String code;
  final String message;
}

class McpCatalogSnapshot {
  const McpCatalogSnapshot({
    this.scope = const McpScope.host(),
    this.revision = 0,
    this.entries = const [],
    this.diagnostics = const [],
  });

  final McpScope scope;
  final int revision;
  final List<McpCatalogEntry> entries;
  final List<McpDocumentDiagnostic> diagnostics;
}

class McpDocumentContent {
  const McpDocumentContent({
    required this.document,
    this.id,
    required this.revision,
    required this.rawToml,
    this.diagnostic,
  });

  final McpDocumentRef document;
  final String? id;
  final int revision;
  final String rawToml;
  final McpDocumentDiagnostic? diagnostic;
}

class McpDocumentCommitReceipt {
  const McpDocumentCommitReceipt({
    this.document,
    required this.revision,
    required this.snapshot,
  });

  final McpDocumentRef? document;
  final int revision;
  final McpCatalogSnapshot snapshot;
}

enum ThreadMcpLifecycleKind {
  connecting,
  available,
  unavailable,
  unsupported,
  shuttingDown,
}

class ThreadMcpServerState {
  const ThreadMcpServerState({
    required this.id,
    required this.effectiveSource,
    required this.executionLocation,
    required this.transport,
    required this.endpointSummary,
    this.builtIn = false,
    required this.lifecycle,
    this.toolCount,
    this.message,
    this.lastCheckedAt,
  });

  final String id;
  final McpEffectiveSource effectiveSource;
  final McpExecutionLocation executionLocation;
  final String transport;
  final String endpointSummary;
  final bool builtIn;
  final ThreadMcpLifecycleKind lifecycle;
  final int? toolCount;
  final String? message;
  final int? lastCheckedAt;
}

class ThreadMcpStateSnapshot {
  const ThreadMcpStateSnapshot({
    required this.threadId,
    this.scope = const McpScope.host(),
    this.generation = 0,
    this.servers = const [],
  });

  final String threadId;
  final McpScope scope;
  final int generation;
  final List<ThreadMcpServerState> servers;
}

class InstructionsSettingsView {
  const InstructionsSettingsView({
    this.baseOverride = '',
    this.developer = '',
    this.user = '',
    this.projectDocMaxBytes = 65536,
    this.projectDocFallbackFilenames = const [],
  });

  final String baseOverride;
  final String developer;
  final String user;
  final int projectDocMaxBytes;
  final List<String> projectDocFallbackFilenames;

  InstructionsSettingsView copyWith({
    String? baseOverride,
    String? developer,
    String? user,
    int? projectDocMaxBytes,
    List<String>? projectDocFallbackFilenames,
  }) {
    return InstructionsSettingsView(
      baseOverride: baseOverride ?? this.baseOverride,
      developer: developer ?? this.developer,
      user: user ?? this.user,
      projectDocMaxBytes: projectDocMaxBytes ?? this.projectDocMaxBytes,
      projectDocFallbackFilenames:
          projectDocFallbackFilenames ?? this.projectDocFallbackFilenames,
    );
  }
}

class SkillsSettingsView {
  const SkillsSettingsView({
    this.enabled = true,
    this.autoLearn = true,
    this.systemEnabled = true,
    this.projectDir = '.agents/skills',
    this.externalDirs = const [],
    this.disabled = const [],
    this.autoLearnMinToolCalls = 5,
  });

  final bool enabled;
  final bool autoLearn;
  final bool systemEnabled;
  final String projectDir;
  final List<String> externalDirs;
  final List<String> disabled;
  final int autoLearnMinToolCalls;

  SkillsSettingsView copyWith({
    bool? enabled,
    bool? autoLearn,
    bool? systemEnabled,
    String? projectDir,
    List<String>? externalDirs,
    List<String>? disabled,
    int? autoLearnMinToolCalls,
  }) {
    return SkillsSettingsView(
      enabled: enabled ?? this.enabled,
      autoLearn: autoLearn ?? this.autoLearn,
      systemEnabled: systemEnabled ?? this.systemEnabled,
      projectDir: projectDir ?? this.projectDir,
      externalDirs: externalDirs ?? this.externalDirs,
      disabled: disabled ?? this.disabled,
      autoLearnMinToolCalls:
          autoLearnMinToolCalls ?? this.autoLearnMinToolCalls,
    );
  }
}

enum UiLanguage { system, zh, en }

class GeneralSettingsView {
  const GeneralSettingsView({
    this.language = UiLanguage.system,
    this.followActiveTurn = true,
    this.compactTimeline = false,
    this.sidebarWidth = 336,
    this.pinnedThreadIds = const [],
    this.pinnedProjectIds = const [],
  });

  final UiLanguage language;
  final bool followActiveTurn;
  final bool compactTimeline;
  final int sidebarWidth;
  final List<String> pinnedThreadIds;
  final List<String> pinnedProjectIds;

  GeneralSettingsView copyWith({
    UiLanguage? language,
    bool? followActiveTurn,
    bool? compactTimeline,
    int? sidebarWidth,
    List<String>? pinnedThreadIds,
    List<String>? pinnedProjectIds,
  }) {
    return GeneralSettingsView(
      language: language ?? this.language,
      followActiveTurn: followActiveTurn ?? this.followActiveTurn,
      compactTimeline: compactTimeline ?? this.compactTimeline,
      sidebarWidth: sidebarWidth ?? this.sidebarWidth,
      pinnedThreadIds: pinnedThreadIds ?? this.pinnedThreadIds,
      pinnedProjectIds: pinnedProjectIds ?? this.pinnedProjectIds,
    );
  }
}

class WebSearchSettingsView {
  const WebSearchSettingsView({
    this.configuredMode = 'cached',
    this.effectiveMode = 'disabled',
    this.availability = 'missingCredential',
    this.contextSize,
    this.allowedDomains = const [],
    this.country,
    this.region,
    this.city,
    this.timezone,
    this.accountId,
    this.modelId,
  });

  final String configuredMode;
  final String effectiveMode;
  final String availability;
  final String? contextSize;
  final List<String> allowedDomains;
  final String? country;
  final String? region;
  final String? city;
  final String? timezone;
  final String? accountId;
  final String? modelId;

  bool get isAvailable => availability == 'available';

  WebSearchSettingsView withConfiguredValues({
    required String configuredMode,
    String? contextSize,
    List<String> allowedDomains = const [],
    String? country,
    String? region,
    String? city,
    String? timezone,
  }) {
    return WebSearchSettingsView(
      configuredMode: configuredMode,
      effectiveMode: effectiveMode,
      availability: availability,
      contextSize: contextSize,
      allowedDomains: allowedDomains,
      country: country,
      region: region,
      city: city,
      timezone: timezone,
      accountId: accountId,
      modelId: modelId,
    );
  }
}

class DeepSeekWebSearchSettingsView {
  const DeepSeekWebSearchSettingsView({
    this.configuredEnabled = true,
    this.effectiveEnabled = false,
    this.configuredFetchEnabled = true,
    this.effectiveFetchEnabled = false,
    this.availability = 'accountUnsupported',
    this.accountId,
  });

  final bool configuredEnabled;
  final bool effectiveEnabled;
  final bool configuredFetchEnabled;
  final bool effectiveFetchEnabled;
  final String availability;
  final String? accountId;

  bool get isAvailable => availability == 'available';

  DeepSeekWebSearchSettingsView withConfiguredEnabled(bool enabled) {
    final nextAvailability = enabled && availability == 'disabled'
        ? 'available'
        : enabled
        ? availability
        : 'disabled';
    return DeepSeekWebSearchSettingsView(
      configuredEnabled: enabled,
      effectiveEnabled: enabled && nextAvailability == 'available',
      configuredFetchEnabled: configuredFetchEnabled,
      effectiveFetchEnabled:
          configuredFetchEnabled && nextAvailability == 'available',
      availability: nextAvailability,
      accountId: accountId,
    );
  }

  DeepSeekWebSearchSettingsView withConfiguredFetchEnabled(bool enabled) {
    return DeepSeekWebSearchSettingsView(
      configuredEnabled: configuredEnabled,
      effectiveEnabled: effectiveEnabled,
      configuredFetchEnabled: enabled,
      effectiveFetchEnabled: enabled && availability == 'available',
      availability: availability,
      accountId: accountId,
    );
  }
}
