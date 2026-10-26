import '../../../resources.dart';
import '../../../resources_ports.dart'
    show FeedConnection, ProductSourceStatusReadConnection;
import '../domain/model_values.dart';
import '../domain/delegation_model_values.dart';
import '../domain/models_state.dart';
import 'model_read_pages.dart';
import 'model_reads.dart';
import 'models_frames.dart';
import 'delegation_model_port.dart';
import 'model_field_read_connection.dart';
import 'template_reads.dart';

abstract interface class ModelCatalogTargetReceiver {
  Future<void> synchronize(ModelCatalogReadTarget target);
}

/// Only the composition root and typed adapter consume this port.
abstract interface class ModelsPort {
  Future<FeedConnection<ModelCatalogFrame>> openModelCatalog();
  Future<FeedConnection<AccountTemplatesFrame>> openAccountTemplates();
  Future<ModelCatalogReadConnection> openModelCatalogRead(
    ModelCatalogReadRef reference, {
    required ProductReadOrigin origin,
  });
  Future<AccountTemplatesReadConnection> openAccountTemplatesRead(
    AccountTemplatesReadRef reference, {
    required ProductReadOrigin origin,
  });
  Future<ProductSourceStatusReadConnection> openSourceStatus(
    ProductSourceStatusRef reference, {
    required ProductReadOrigin origin,
  });
  Future<DelegationModelReadConnection> openDelegationModelRead(
    DelegationModelReadTarget target,
  );
}

abstract interface class ModelCatalogReadConnection
    implements ModelFieldReadConnection {
  Future<ModelCatalogReadHeader> header();
  Future<String?> effortAfterModelSelection(
    String accountId,
    String modelId, {
    required String? candidate,
  });
  Future<ModelSelection?> firstTextModel();
  Future<TextChunk> text(int fieldId, {int offset = 0, int maxBytes = 65536});
  Future<ModelCatalogEntryPage> entries({int offset = 0, int limit = 32});
  Future<ModelCatalogEntityRead> entity(ProductEntityRef reference);
  Future<ProductEntityRef?> lookupAccount(String accountId);
  Future<AccountCatalogEntryReadPage> accounts(
    int listId, {
    int offset = 0,
    int limit = 32,
  });
  Future<ModelDescriptorReadPage> models(
    int listId, {
    int offset = 0,
    int limit = 32,
  });
  Future<ModelTypeSupportReadPage> typeSupport(
    int listId, {
    int offset = 0,
    int limit = 32,
  });
  Future<ModelTypeExclusionReadPage> typeExclusions(
    int listId, {
    int offset = 0,
    int limit = 32,
  });
  Future<ConnectionModeReadPage> connectionModes(
    int listId, {
    int offset = 0,
    int limit = 32,
  });
  Future<ModelInputCapabilityReadPage> inputCapabilities(
    int listId, {
    int offset = 0,
    int limit = 32,
  });
  Future<ModelInputSourceReadPage> inputSources(
    int listId, {
    int offset = 0,
    int limit = 32,
  });
  Future<ModelModalityReadPage> modalities(
    int listId, {
    int offset = 0,
    int limit = 32,
  });
  Future<ModelPriceTierReadPage> priceTiers(
    int listId, {
    int offset = 0,
    int limit = 32,
  });
  Future<TextReadPage> strings(int listId, {int offset = 0, int limit = 32});
  void requestClose();
  Future<FeedCloseReport> close();
  Future<FeedCloseReport> retryClose();
}

abstract interface class AccountTemplatesReadConnection
    implements ModelFieldReadConnection {
  Future<AccountTemplatesReadHeader> header();
  Future<TextChunk> text(int fieldId, {int offset = 0, int maxBytes = 65536});
  Future<AccountTemplatesEntryPage> entries({int offset = 0, int limit = 32});
  Future<AccountTemplatesEntityRead> entity(ProductEntityRef reference);
  Future<ProductEntityRef?> lookupTemplate(String templateId);
  Future<AccountTemplateReadPage> templates(
    int listId, {
    int offset = 0,
    int limit = 32,
  });
  Future<NamedModelCatalogReadPage> catalogs(
    int listId, {
    int offset = 0,
    int limit = 32,
  });
  Future<ModelDescriptorReadPage> models(
    int listId, {
    int offset = 0,
    int limit = 32,
  });
  Future<ModelTypeSupportReadPage> typeSupport(
    int listId, {
    int offset = 0,
    int limit = 32,
  });
  Future<ModelTypeExclusionReadPage> typeExclusions(
    int listId, {
    int offset = 0,
    int limit = 32,
  });
  Future<ConnectionModeReadPage> connectionModes(
    int listId, {
    int offset = 0,
    int limit = 32,
  });
  Future<ModelInputCapabilityReadPage> inputCapabilities(
    int listId, {
    int offset = 0,
    int limit = 32,
  });
  Future<ModelInputSourceReadPage> inputSources(
    int listId, {
    int offset = 0,
    int limit = 32,
  });
  Future<ModelModalityReadPage> modalities(
    int listId, {
    int offset = 0,
    int limit = 32,
  });
  Future<ModelPriceTierReadPage> priceTiers(
    int listId, {
    int offset = 0,
    int limit = 32,
  });
  Future<TextReadPage> strings(int listId, {int offset = 0, int limit = 32});
  void requestClose();
  Future<FeedCloseReport> close();
  Future<FeedCloseReport> retryClose();
}
