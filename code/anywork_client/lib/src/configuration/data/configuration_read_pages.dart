import 'package:freezed_annotation/freezed_annotation.dart';

import '../../../resources.dart';
import 'configuration_reads.dart';
import 'profile_reads.dart';

part 'configuration_read_pages.freezed.dart';

@freezed
final class ConfigurationEntryPage with _$ConfigurationEntryPage {
  ConfigurationEntryPage({required this.collection, required this.offset, required List<ProductEntityRef> items, required this.nextOffset}) : items = List.unmodifiable(items);
  final ProductCollectionRef collection;
  final int offset;
  final List<ProductEntityRef> items;
  final int? nextOffset;
}

@Freezed(toStringOverride: false)
abstract class ConfigurationEntityRead with _$ConfigurationEntityRead {
  const factory ConfigurationEntityRead({required ProductEntityRef reference, required AccountConfigurationRead value}) = _ConfigurationEntityRead;
}

@freezed
final class AgentProfilesEntryPage with _$AgentProfilesEntryPage {
  AgentProfilesEntryPage({required this.collection, required this.offset, required List<ProductEntityRef> items, required this.nextOffset}) : items = List.unmodifiable(items);
  final ProductCollectionRef collection;
  final int offset;
  final List<ProductEntityRef> items;
  final int? nextOffset;
}

@Freezed(toStringOverride: false)
abstract class AgentProfilesEntityRead with _$AgentProfilesEntityRead {
  const factory AgentProfilesEntityRead({required ProductEntityRef reference, required AgentProfileRead value}) = _AgentProfilesEntityRead;
}

@Freezed(toStringOverride: false)
final class AccountConfigurationReadPage with _$AccountConfigurationReadPage {
  AccountConfigurationReadPage({required this.listId, required this.offset, required this.total, required List<AccountConfigurationRead> items, required this.nextOffset}) : items = List.unmodifiable(items);
  final int listId;
  final int offset;
  final int total;
  final List<AccountConfigurationRead> items;
  final int? nextOffset;
}

@Freezed(toStringOverride: false)
final class CustomModelConfigurationReadPage with _$CustomModelConfigurationReadPage {
  CustomModelConfigurationReadPage({required this.listId, required this.offset, required this.total, required List<CustomModelConfigurationRead> items, required this.nextOffset}) : items = List.unmodifiable(items);
  final int listId;
  final int offset;
  final int total;
  final List<CustomModelConfigurationRead> items;
  final int? nextOffset;
}

@Freezed(toStringOverride: false)
final class ModelConnectionReadPage with _$ModelConnectionReadPage {
  ModelConnectionReadPage({required this.listId, required this.offset, required this.total, required List<ModelConnectionRead> items, required this.nextOffset}) : items = List.unmodifiable(items);
  final int listId;
  final int offset;
  final int total;
  final List<ModelConnectionRead> items;
  final int? nextOffset;
}

@Freezed(toStringOverride: false)
final class ModelAutoCompactReadPage with _$ModelAutoCompactReadPage {
  ModelAutoCompactReadPage({required this.listId, required this.offset, required this.total, required List<ModelAutoCompactRead> items, required this.nextOffset}) : items = List.unmodifiable(items);
  final int listId;
  final int offset;
  final int total;
  final List<ModelAutoCompactRead> items;
  final int? nextOffset;
}

@Freezed(toStringOverride: false)
final class ModeModelRouteReadPage with _$ModeModelRouteReadPage {
  ModeModelRouteReadPage({required this.listId, required this.offset, required this.total, required List<ModeModelRouteRead> items, required this.nextOffset}) : items = List.unmodifiable(items);
  final int listId;
  final int offset;
  final int total;
  final List<ModeModelRouteRead> items;
  final int? nextOffset;
}

@Freezed(toStringOverride: false)
final class RoleModelRouteReadPage with _$RoleModelRouteReadPage {
  RoleModelRouteReadPage({required this.listId, required this.offset, required this.total, required List<RoleModelRouteRead> items, required this.nextOffset}) : items = List.unmodifiable(items);
  final int listId;
  final int offset;
  final int total;
  final List<RoleModelRouteRead> items;
  final int? nextOffset;
}

@Freezed(toStringOverride: false)
final class McpConfigurationReadPage with _$McpConfigurationReadPage {
  McpConfigurationReadPage({required this.listId, required this.offset, required this.total, required List<McpConfigurationRead> items, required this.nextOffset}) : items = List.unmodifiable(items);
  final int listId;
  final int offset;
  final int total;
  final List<McpConfigurationRead> items;
  final int? nextOffset;
}

@Freezed(toStringOverride: false)
final class AgentProfileReadPage with _$AgentProfileReadPage {
  AgentProfileReadPage({required this.listId, required this.offset, required this.total, required List<AgentProfileRead> items, required this.nextOffset}) : items = List.unmodifiable(items);
  final int listId;
  final int offset;
  final int total;
  final List<AgentProfileRead> items;
  final int? nextOffset;
}

@Freezed(toStringOverride: false)
final class ProfileDiagnosticReadPage with _$ProfileDiagnosticReadPage {
  ProfileDiagnosticReadPage({required this.listId, required this.offset, required this.total, required List<ProfileDiagnosticRead> items, required this.nextOffset}) : items = List.unmodifiable(items);
  final int listId;
  final int offset;
  final int total;
  final List<ProfileDiagnosticRead> items;
  final int? nextOffset;
}
