import 'package:anywork_client/models_ports.dart';
import 'package:anywork_client/resources_ports.dart';

import '../../../../anywork_client/test/support/profile_model_port.dart';
import 'selector_configuration_port.dart';

/// Two distinguishable immutable model descriptors. All catalog paging and
/// original-scope behavior is supplied by the existing native-boundary fixture.
final class SelectorModelsPort implements ModelsPort {
  final base = ProfileModelsPort(
    origin: selectorOrigin,
    accounts: const ['account-0', 'account-1'],
    textEligibleAccounts: const {'account-0', 'account-1'},
  );
  @override
  Future<FeedConnection<ModelCatalogFrame>> openModelCatalog() =>
      base.openModelCatalog();
  @override
  Future<ModelCatalogReadConnection> openModelCatalogRead(
    ModelCatalogReadRef reference, {
    required ProductReadOrigin origin,
  }) async =>
      _CatalogPin(await base.openModelCatalogRead(reference, origin: origin));
  @override
  Future<ProductSourceStatusReadConnection> openSourceStatus(
    ProductSourceStatusRef reference, {
    required ProductReadOrigin origin,
  }) => base.openSourceStatus(reference, origin: origin);
  @override
  Never noSuchMethod(Invocation invocation) => throw UnsupportedError(
    'Unscripted selector model: ${invocation.memberName}',
  );
}

final class _CatalogPin implements ModelCatalogReadConnection {
  _CatalogPin(this.base);
  final ModelCatalogReadConnection base;
  @override
  Future<ModelCatalogReadHeader> header() => base.header();
  @override
  Future<ModelCatalogEntryPage> entries({int offset = 0, int limit = 32}) =>
      base.entries(offset: offset, limit: limit);
  @override
  Future<ProductEntityRef?> lookupAccount(String accountId) =>
      base.lookupAccount(accountId);
  @override
  Future<ModelCatalogEntityRead> entity(ProductEntityRef reference) =>
      base.entity(reference);
  @override
  Future<ModelDescriptorReadPage> models(
    int listId, {
    int offset = 0,
    int limit = 32,
  }) async {
    final page = await base.models(listId, offset: offset, limit: limit);
    return page.copyWith(
      items: [
        for (final model in page.items)
          model.copyWith(
            displayName: ReadText.inline(
              text: listId == 1000
                  ? 'Native text model'
                  : 'Second native model',
            ),
          ),
      ],
    );
  }

  @override
  Future<ModelTypeSupportReadPage> typeSupport(
    int listId, {
    int offset = 0,
    int limit = 32,
  }) => base.typeSupport(listId, offset: offset, limit: limit);
  @override
  Future<TextReadPage> strings(int listId, {int offset = 0, int limit = 32}) =>
      base.strings(listId, offset: offset, limit: limit);
  @override
  void requestClose() => base.requestClose();
  @override
  Future<FeedCloseReport> close() => base.close();
  @override
  Future<FeedCloseReport> retryClose() => base.retryClose();
  @override
  Never noSuchMethod(Invocation invocation) => throw UnsupportedError(
    'Unscripted selector catalog material: ${invocation.memberName}',
  );
}
