import 'package:anywork_client/models.dart';

import '../../view_models/collection_values.dart';
import '../../view_models/read_values.dart';

/// Recombines only current typed reads of the same template source. This is a
/// display selector; it never publishes or materializes Repository state.
AccountTemplatesValue? currentTemplatesValue(TemplatesState source) {
  final origin = source.projection.stamp?.origin;
  final header = source.projection.header;
  if (origin == null || header == null || !collectionComplete(source.templates, origin) ||
      !isCurrentRead(source.catalogs, header.reference, origin) ||
      !isCurrentRead(source.catalogRevision, header.reference, origin)) return null;
  final catalogs = displayReadValue(source.catalogs);
  final revision = displayReadValue(source.catalogRevision);
  if (catalogs == null || revision == null) return null;
  return AccountTemplatesValue(schemaVersion: header.schemaVersion, revision: revision,
    templates: displayCollectionRows(source.templates), modelCatalogs: catalogs);
}
