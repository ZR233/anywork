import 'package:freezed_annotation/freezed_annotation.dart';

import '../../../resources.dart';

part 'template_reads.freezed.dart';

@Freezed(toStringOverride: false)
abstract class AccountTemplatesReadHeader with _$AccountTemplatesReadHeader {
  const factory AccountTemplatesReadHeader({required int schemaVersion, required ReadText revision, required TypedListRef templates, required TypedListRef modelCatalogs}) = _AccountTemplatesReadHeader;
}

@Freezed(toStringOverride: false)
abstract class AccountTemplateRead with _$AccountTemplateRead {
  const factory AccountTemplateRead({required bool pricingEnabled, required ReadText id, required ReadText displayName, required ReadText? description, required ReadText baseUrl, required CredentialDescriptorRead credential, required ReadText modelCatalogId, required ReadText protocol, required ReadText suggestedModelId, required ReadText? iconKey, required AccountServiceCapabilitiesRead serviceCapabilities}) = _AccountTemplateRead;
}

@Freezed(toStringOverride: false)
abstract class CredentialDescriptorRead with _$CredentialDescriptorRead {
  const factory CredentialDescriptorRead({required ReadText label, required ReadText? envVar}) = _CredentialDescriptorRead;
}

@Freezed(toStringOverride: false)
abstract class AccountServiceCapabilitiesRead with _$AccountServiceCapabilitiesRead {
  const factory AccountServiceCapabilitiesRead({required WebSearchServiceCapabilitiesRead webSearch, required ReadText promptCacheDialect, required bool responsesProgrammaticToolCalling}) = _AccountServiceCapabilitiesRead;
}

@Freezed(toStringOverride: false)
abstract class WebSearchServiceCapabilitiesRead with _$WebSearchServiceCapabilitiesRead {
  const factory WebSearchServiceCapabilitiesRead({required bool hostedResponses, required ReadText hostedDialect, required ReadText? standalone}) = _WebSearchServiceCapabilitiesRead;
}

@Freezed(toStringOverride: false)
abstract class NamedModelCatalogRead with _$NamedModelCatalogRead {
  const factory NamedModelCatalogRead({required ReadText id, required TypedListRef models}) = _NamedModelCatalogRead;
}

@Freezed(toStringOverride: false)
abstract class NamedModelCatalogReadItem with _$NamedModelCatalogReadItem {
  const factory NamedModelCatalogReadItem({required ReadText key, required NamedModelCatalogRead value}) = _NamedModelCatalogReadItem;
}
