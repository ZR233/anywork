import 'package:anywork_client/models_ports.dart';
import 'package:anywork_client/resources_ports.dart';

import '../catalog_read_connection.dart';
import '../templates_connection.dart';
import '../templates_read_connection.dart';
import 'catalog_connection.dart';
import 'delegation_read_connection.dart';
import 'source_status_connection.dart';

/// Production Models transport only. Construction starts no feed, probe or
/// mutation; the Repository remains the sole writer of canonical Models state.
final class FrbModelsPort implements ModelsPort {
  const FrbModelsPort();

  @override
  Future<FeedConnection<ModelCatalogFrame>> openModelCatalog() async {
    final connection = FrbModelCatalogConnection();
    await connection.opened;
    return connection;
  }

  @override
  Future<FeedConnection<AccountTemplatesFrame>> openAccountTemplates() async {
    final connection = FrbAccountTemplatesConnection();
    await connection.opened;
    return connection;
  }

  @override
  Future<ModelCatalogReadConnection> openModelCatalogRead(
    ModelCatalogReadRef reference, {
    required ProductReadOrigin origin,
  }) async {
    final connection = FrbModelCatalogReadConnection(reference, origin);
    await connection.opened;
    return connection;
  }

  @override
  Future<AccountTemplatesReadConnection> openAccountTemplatesRead(
    AccountTemplatesReadRef reference, {
    required ProductReadOrigin origin,
  }) async {
    final connection = FrbAccountTemplatesReadConnection(reference, origin);
    await connection.opened;
    return connection;
  }

  @override
  Future<ProductSourceStatusReadConnection> openSourceStatus(
    ProductSourceStatusRef reference, {
    required ProductReadOrigin origin,
  }) async {
    final connection = FrbModelCatalogSourceStatusConnection(reference, origin);
    await connection.opened;
    return connection;
  }

  @override
  Future<DelegationModelReadConnection> openDelegationModelRead(
    DelegationModelReadTarget target,
  ) async {
    final connection = FrbDelegationModelReadConnection(target);
    await connection.opened;
    return connection;
  }
}
