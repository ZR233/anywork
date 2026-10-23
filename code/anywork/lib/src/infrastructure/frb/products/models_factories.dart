import 'package:anywork_client/models_ports.dart';
import 'package:anywork_client/resources_ports.dart';

import 'catalog_read_connection.dart';
import 'templates_connection.dart';
import 'templates_read_connection.dart';

// These three actual leaves intentionally do not implement ModelsPort: Catalog
// feed/sourceStatus still await their native owners. No missing method is stubbed.
Future<ModelCatalogReadConnection> openFrbModelCatalogRead(
  ModelCatalogReadRef reference, {required ProductReadOrigin origin}
) async {
  final connection = FrbModelCatalogReadConnection(reference, origin);
  await connection.opened;
  return connection;
}

Future<AccountTemplatesReadConnection> openFrbAccountTemplatesRead(
  AccountTemplatesReadRef reference, {required ProductReadOrigin origin}
) async {
  final connection = FrbAccountTemplatesReadConnection(reference, origin);
  await connection.opened;
  return connection;
}

Future<FeedConnection<AccountTemplatesFrame>> openFrbAccountTemplates() async {
  final connection = FrbAccountTemplatesConnection();
  await connection.opened;
  return connection;
}
