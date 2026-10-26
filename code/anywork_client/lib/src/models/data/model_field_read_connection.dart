import '../../../resources.dart';
import 'model_read_pages.dart';

/// Mechanical fields of one immutable native model material. Catalogs,
/// templates and exact-model reference queries retain their own read owners.
abstract interface class ModelFieldReadConnection {
  Future<TextChunk> text(int fieldId, {int offset = 0, int maxBytes = 65536});
  Future<TextReadPage> strings(int listId, {int offset = 0, int limit = 32});
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
}
