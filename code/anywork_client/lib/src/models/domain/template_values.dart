import 'package:freezed_annotation/freezed_annotation.dart';

import 'model_values.dart';

part 'template_values.freezed.dart';

@freezed
final class AccountTemplatesValue with _$AccountTemplatesValue {
  AccountTemplatesValue({
    required this.schemaVersion,
    required this.revision,
    required List<AccountTemplate> templates,
    required Map<String, NamedModelCatalog> modelCatalogs,
  }) : templates = List.unmodifiable(templates),
       modelCatalogs = Map.unmodifiable(modelCatalogs);
  final int schemaVersion;
  final String revision;
  final List<AccountTemplate> templates;
  final Map<String, NamedModelCatalog> modelCatalogs;
}

@freezed
abstract class AccountTemplate with _$AccountTemplate {
  const factory AccountTemplate({
    required String id,
    required String displayName,
    required String? description,
    required String baseUrl,
    required CredentialDescriptor credential,
    required String modelCatalogId,
    required String protocol,
    required String suggestedModelId,
    required String? iconKey,
    required AccountServiceCapabilities serviceCapabilities,
  }) = _AccountTemplate;
}

@freezed
abstract class CredentialDescriptor with _$CredentialDescriptor {
  const factory CredentialDescriptor({
    required String label,
    required String? envVar,
  }) = _CredentialDescriptor;
}

@freezed
abstract class AccountServiceCapabilities with _$AccountServiceCapabilities {
  const factory AccountServiceCapabilities({
    required WebSearchServiceCapabilities webSearch,
    required String promptCacheDialect,
    required bool responsesProgrammaticToolCalling,
  }) = _AccountServiceCapabilities;
}

@freezed
abstract class WebSearchServiceCapabilities
    with _$WebSearchServiceCapabilities {
  const factory WebSearchServiceCapabilities({
    required bool hostedResponses,
    required String hostedDialect,
    required String? standalone,
  }) = _WebSearchServiceCapabilities;
}

@freezed
final class NamedModelCatalog with _$NamedModelCatalog {
  NamedModelCatalog({required this.id, required List<ModelDescriptor> models})
    : models = List.unmodifiable(models);
  final String id;
  final List<ModelDescriptor> models;
}
