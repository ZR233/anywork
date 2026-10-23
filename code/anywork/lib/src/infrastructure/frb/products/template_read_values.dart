import 'package:anywork_client/models_ports.dart';

import '../../../rust/api/studio/products/read/template_values.dart' as native;
import '../shared/read_converters.dart';

AccountTemplatesReadHeader templatesReadHeaderFromBridge(native.BridgeAccountTemplatesReadHeader value) => AccountTemplatesReadHeader(
  schemaVersion: value.schemaVersion, revision: readTextFromBridge(value.revision),
  templates: typedListFromBridge(value.templates), modelCatalogs: typedListFromBridge(value.modelCatalogs),
);

AccountTemplateRead accountTemplateReadFromBridge(native.BridgeAccountTemplateRead value) => AccountTemplateRead(
  pricingEnabled: value.pricingEnabled, id: readTextFromBridge(value.id),
  displayName: readTextFromBridge(value.displayName), description: nullableReadText(value.description),
  baseUrl: readTextFromBridge(value.baseUrl),
  credential: CredentialDescriptorRead(label: readTextFromBridge(value.credential.label), envVar: nullableReadText(value.credential.envVar)),
  modelCatalogId: readTextFromBridge(value.modelCatalogId), protocol: readTextFromBridge(value.protocol),
  suggestedModelId: readTextFromBridge(value.suggestedModelId), iconKey: nullableReadText(value.iconKey),
  serviceCapabilities: AccountServiceCapabilitiesRead(
    webSearch: WebSearchServiceCapabilitiesRead(
      hostedResponses: value.serviceCapabilities.webSearch.hostedResponses,
      hostedDialect: readTextFromBridge(value.serviceCapabilities.webSearch.hostedDialect),
      standalone: nullableReadText(value.serviceCapabilities.webSearch.standalone),
    ),
    promptCacheDialect: readTextFromBridge(value.serviceCapabilities.promptCacheDialect),
    responsesProgrammaticToolCalling: value.serviceCapabilities.responsesProgrammaticToolCalling,
  ),
);

NamedModelCatalogReadItem namedModelCatalogReadFromBridge(native.BridgeNamedModelCatalogReadItem value) => NamedModelCatalogReadItem(
  key: readTextFromBridge(value.key),
  value: NamedModelCatalogRead(id: readTextFromBridge(value.value.id), models: typedListFromBridge(value.value.models)),
);
