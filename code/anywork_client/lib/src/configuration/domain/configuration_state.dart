import 'package:freezed_annotation/freezed_annotation.dart';

import '../../../resources.dart';
import '../../models/domain/model_values.dart';
import '../../models/domain/models_state.dart';
import 'config_projection_stamp.dart';
import 'configuration_values.dart';
import 'profile_values.dart';

part 'configuration_state.freezed.dart';

@freezed
abstract class ConfigurationReadRef with _$ConfigurationReadRef {
  const factory ConfigurationReadRef({
    required int entry,
    required int revision,
  }) = _ConfigurationReadRef;
}

@freezed
abstract class ConfigurationReadTarget with _$ConfigurationReadTarget {
  const factory ConfigurationReadTarget({
    required ProductReadOrigin origin,
    required ConfigurationReadRef reference,
  }) = _ConfigurationReadTarget;
}

@freezed
abstract class ConfigurationRoleReadRef with _$ConfigurationRoleReadRef {
  const factory ConfigurationRoleReadRef({
    required int entry,
    required int revision,
  }) = _ConfigurationRoleReadRef;
}

/// Rust-issued identity for one compatible configuration/catalog capture.
/// The pair belongs to configuration.origin; catalog keeps its own origin.
@freezed
abstract class ConfigurationRoleReadTarget with _$ConfigurationRoleReadTarget {
  const factory ConfigurationRoleReadTarget({
    required ConfigurationRoleReadRef reference,
    required ConfigurationReadTarget configuration,
    required ModelCatalogReadTarget catalog,
    required ConfigProjectionStamp stamp,
  }) = _ConfigurationRoleReadTarget;
}

@Freezed(toStringOverride: false)
sealed class RoleRouteRead with _$RoleRouteRead {
  const factory RoleRouteRead.configured({required RoleModelRoute route}) =
      ConfiguredRoleRouteRead;
  const factory RoleRouteRead.missing({required ModelSelection? suggestion}) =
      MissingRoleRouteRead;
}

@freezed
abstract class AgentProfilesReadRef with _$AgentProfilesReadRef {
  const factory AgentProfilesReadRef({
    required int entry,
    required int revision,
  }) = _AgentProfilesReadRef;
}

@freezed
abstract class AgentProfilesReadTarget with _$AgentProfilesReadTarget {
  const factory AgentProfilesReadTarget({
    required ProductReadOrigin origin,
    required AgentProfilesReadRef reference,
  }) = _AgentProfilesReadTarget;
}

@freezed
abstract class ConfigurationHeader with _$ConfigurationHeader {
  const factory ConfigurationHeader({
    required ObservedHeader source,
    required int? configurationRevision,
    required int? updatedAt,
    required ConfigurationReadRef? reference,
    required ConfigurationRoleReadTarget? roleRead,
  }) = _ConfigurationHeader;
}

@freezed
abstract class AgentProfilesHeader with _$AgentProfilesHeader {
  const factory AgentProfilesHeader({
    required ObservedHeader source,
    required int? profilesRevision,
    required AgentProfilesReadRef? reference,
  }) = _AgentProfilesHeader;
}

@Freezed(toStringOverride: false)
final class ConfigurationState with _$ConfigurationState {
  ConfigurationState({
    required this.projection,
    required this.sourceStatus,
    required this.accounts,
    required this.defaultAccountId,
    required ReadValue<List<ModeModelRoute>, ConfigurationReadRef>? modeRoutes,
    required ReadValue<List<RoleModelRoute>, ConfigurationReadRef>? roles,
    required this.permissionMode,
    required this.instructions,
    required this.skillsSettings,
    required ReadValue<List<McpConfiguration>, ConfigurationReadRef>?
    mcpConfigurations,
    required this.general,
    required this.delegation,
    required this.webSearch,
    required this.deepSeekSearch,
  }) : modeRoutes = _snapshotConfigurationList(modeRoutes),
       roles = _snapshotConfigurationList(roles),
       mcpConfigurations = _snapshotConfigurationList(mcpConfigurations);

  final ProductProjection<ConfigurationHeader> projection;
  final ReadValue<ProductSourceStatus, ProductSourceStatusRef>? sourceStatus;
  final CollectionMirror<AccountConfiguration> accounts;
  final ReadValue<String?, ConfigurationReadRef>? defaultAccountId;
  final ReadValue<List<ModeModelRoute>, ConfigurationReadRef>? modeRoutes;
  final ReadValue<List<RoleModelRoute>, ConfigurationReadRef>? roles;
  final ReadValue<String, ConfigurationReadRef>? permissionMode;
  final ReadValue<InstructionsSettings, ConfigurationReadRef>? instructions;
  final ReadValue<SkillsSettings, ConfigurationReadRef>? skillsSettings;
  final ReadValue<List<McpConfiguration>, ConfigurationReadRef>?
  mcpConfigurations;
  final ReadValue<GeneralSettings, ConfigurationReadRef>? general;
  final ReadValue<DelegationSettings, ConfigurationReadRef>? delegation;
  final ReadValue<WebSearchConfiguration, ConfigurationReadRef>? webSearch;
  final ReadValue<DeepSeekSearchConfiguration, ConfigurationReadRef>?
  deepSeekSearch;
}

@Freezed(toStringOverride: false)
final class ProfilesState with _$ProfilesState {
  ProfilesState({
    required this.projection,
    required this.sourceStatus,
    required this.profiles,
    required Map<int, ReadValue<AgentProfileSnapshot, ProductEntityRef>>
    details,
    required ReadValue<List<ProfileDiagnostic>, AgentProfilesReadRef>?
    diagnostics,
  }) : details = Map.unmodifiable(details),
       diagnostics = _snapshotConfigurationList(diagnostics);

  final ProductProjection<AgentProfilesHeader> projection;
  final ReadValue<ProductSourceStatus, ProductSourceStatusRef>? sourceStatus;
  final CollectionMirror<AgentProfileSummary> profiles;
  final Map<int, ReadValue<AgentProfileSnapshot, ProductEntityRef>> details;
  final ReadValue<List<ProfileDiagnostic>, AgentProfilesReadRef>? diagnostics;
}

/// Collection payloads belong to this domain, including last-known material.
ReadValue<List<T>, R>? _snapshotConfigurationList<T, R>(
  ReadValue<List<T>, R>? value,
) {
  Materialized<List<T>, R>? snapshot(Materialized<List<T>, R>? material) =>
      material == null
      ? null
      : material.copyWith(value: List<T>.unmodifiable(material.value));
  return switch (value) {
    null => null,
    UnloadedReadValue<List<T>, R>() => value,
    LoadingReadValue<List<T>, R>(
      :final origin,
      :final reference,
      :final previous,
    ) =>
      ReadValue.loading(
        origin: origin,
        reference: reference,
        previous: snapshot(previous),
      ),
    ReadyReadValue<List<T>, R>(:final current) => ReadValue.ready(
      current: snapshot(current)!,
    ),
    FailedReadValue<List<T>, R>(
      :final origin,
      :final reference,
      :final error,
      :final previous,
    ) =>
      ReadValue.failed(
        origin: origin,
        reference: reference,
        error: error,
        previous: snapshot(previous),
      ),
  };
}
