import '../../../resources.dart';
import 'model_values.dart';
import 'models_state.dart';
import 'template_values.dart';

/// Model policy and templates are read-only canonical resources. This API does
/// not depend on operations and does not expose configuration writes.
abstract interface class ModelsRepository {
  ReadonlyLatestValue<ModelsState> get state;
  ReadonlyLatestValue<TemplatesState> get templates;
  Future<void> loadSourceStatus();
  Future<EffectiveWebSearch> loadWebSearch();
  Future<EffectiveDeepSeekSearch> loadDeepSeekSearch();
  Future<void> loadAccountsPage({int limit = 32});
  Future<AccountCatalogEntry> loadAccount(String accountId);
  Future<AccountTemplatesValue> loadTemplates();
  Future<ModelDescriptor> loadModel(String accountId, String modelId);
  /// Editing suggestions over the explicit original catalog, not save-time
  /// normalization. The caller still checks its editor/mode/intent identity.
  Future<String?> effortAfterModelSelection({required ModelCatalogReadTarget catalog, required AccountModelKey model, required String? candidate});
  Future<ModelSelection?> firstTextModel({required ModelCatalogReadTarget catalog});
  void seal();
  Future<CloseReport> close({DateTime? deadline});
  Future<CloseReport> retryCleanup({DateTime? deadline});
}
