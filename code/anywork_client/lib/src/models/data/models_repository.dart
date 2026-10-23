import '../../../resources.dart';
import '../../../resources_ports.dart';
import '../domain/model_values.dart';
import '../domain/models_repository.dart';
import '../domain/models_state.dart';
import '../domain/template_values.dart';
import 'models_catalog.dart';
import 'models_port.dart';
import 'models_templates.dart';

/// Export this factory and ModelCatalogTargetReceiver only from models_ports.
/// The named record lends two capabilities of the very same repository owner.
({ModelsRepository repository, ModelCatalogTargetReceiver targets}) createModelsRepository({required ModelsPort port, required ResourceBudget budget}) {
  final repository = _ModelsRepository(port, budget);
  return (repository: repository, targets: repository);
}

final class _ModelsRepository implements ModelsRepository, ModelCatalogTargetReceiver {
  _ModelsRepository(ModelsPort port, ResourceBudget budget) : lifetime = ResourceLifetime(budget) {
    catalog = ModelsCatalog(port, lifetime);
    templateCatalog = ModelsTemplates(port, lifetime);
  }

  final ResourceLifetime lifetime;
  late final ModelsCatalog catalog;
  late final ModelsTemplates templateCatalog;
  bool _sourcesClosed = false;

  @override
  ReadonlyLatestValue<ModelsState> get state => catalog.state.readonly;
  @override
  ReadonlyLatestValue<TemplatesState> get templates => templateCatalog.state.readonly;
  @override
  Future<void> loadSourceStatus() => catalog.loadSourceStatus();
  @override
  Future<EffectiveWebSearch> loadWebSearch() => catalog.loadWebSearch();
  @override
  Future<EffectiveDeepSeekSearch> loadDeepSeekSearch() => catalog.loadDeepSeekSearch();
  @override
  Future<void> loadAccountsPage({int limit = 32}) => catalog.loadAccountsPage(limit: limit);
  @override
  Future<AccountCatalogEntry> loadAccount(String accountId) => catalog.loadAccount(accountId);
  @override
  Future<ModelDescriptor> loadModel(String accountId, String modelId) => catalog.loadModel(accountId, modelId);
  @override
  Future<String?> effortAfterModelSelection({required ModelCatalogReadTarget catalog, required AccountModelKey model, required String? candidate}) => this.catalog.effortAfterModelSelection(catalog: catalog, model: model, candidate: candidate);
  @override
  Future<ModelSelection?> firstTextModel({required ModelCatalogReadTarget catalog}) => this.catalog.firstTextModel(catalog: catalog);
  @override
  Future<AccountTemplatesValue> loadTemplates() => templateCatalog.load();
  @override
  Future<void> synchronize(ModelCatalogReadTarget target) => catalog.synchronize(target);
  @override
  void seal() => lifetime.seal();
  @override
  Future<CloseReport> close({DateTime? deadline}) => _close(deadline, false);
  @override
  Future<CloseReport> retryCleanup({DateTime? deadline}) => _close(deadline, true);

  Future<CloseReport> _close(DateTime? deadline, bool retry) async {
    final report = await lifetime.close(deadline: deadline, retry: retry);
    if (report.complete && !_sourcesClosed) {
      _sourcesClosed = true;
      catalog.state.publish(catalog.state.value.copyWith(projection: catalog.state.value.projection.copyWith(sync: const ResourceSyncState(phase: ResourceSyncPhase.closed, error: null, retryExhausted: false))));
      templateCatalog.state.publish(templateCatalog.state.value.copyWith(projection: templateCatalog.state.value.projection.copyWith(sync: const ResourceSyncState(phase: ResourceSyncPhase.closed, error: null, retryExhausted: false))));
      catalog.state.close();
      templateCatalog.state.close();
    }
    return report;
  }
}
