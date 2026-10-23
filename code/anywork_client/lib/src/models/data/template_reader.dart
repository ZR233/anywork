import '../domain/template_values.dart';
import 'model_reader.dart';
import 'template_reads.dart';

Future<AccountTemplate> readAccountTemplate(AccountTemplateRead value, ModelReadAccess access) async => AccountTemplate(
  pricingEnabled: value.pricingEnabled,
  id: await access.string(value.id),
  displayName: await access.string(value.displayName),
  description: await access.optional(value.description),
  baseUrl: await access.string(value.baseUrl),
  credential: CredentialDescriptor(label: await access.string(value.credential.label), envVar: await access.optional(value.credential.envVar)),
  modelCatalogId: await access.string(value.modelCatalogId),
  protocol: await access.string(value.protocol),
  suggestedModelId: await access.string(value.suggestedModelId),
  iconKey: await access.optional(value.iconKey),
  serviceCapabilities: AccountServiceCapabilities(
    webSearch: WebSearchServiceCapabilities(hostedResponses: value.serviceCapabilities.webSearch.hostedResponses, hostedDialect: await access.string(value.serviceCapabilities.webSearch.hostedDialect), standalone: await access.optional(value.serviceCapabilities.webSearch.standalone)),
    promptCacheDialect: await access.string(value.serviceCapabilities.promptCacheDialect),
    responsesProgrammaticToolCalling: value.serviceCapabilities.responsesProgrammaticToolCalling,
  ),
);
