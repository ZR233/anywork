import '../../../status/status.dart';
import '../../view_models/collection_values.dart';
import '../../view_models/read_values.dart';

/// Semantic mode id whose model route is a bot's default route.
///
/// A bot without a route of its own runs with this mode's route, so the create
/// section states exactly this fact before any bot exists.
const botDefaultModeId = 'mode.simple';

/// Whether the evidence for a usable default model route is complete.
///
/// [unknown] is not [missing]: without a current read of the mode routes, the
/// accounts or the model catalog, the page must not claim either state. Callers
/// that keep the established two-line wording render [missing] for [unknown],
/// which is also the direction that never pretends a route is configured.
enum BotModelAvailability { ready, missing, unknown }

/// Resolves the default model availability from current material only.
///
/// It reads the same public projections as the model selectors: a configured
/// route, the account it names, the eligible model in the current catalog and
/// the account's credential presence. It never performs a read or invents a
/// route of its own.
BotModelAvailability botModelAvailability(SelectorCatalogState catalog) {
  final routes = displayReadValue(catalog.configuration.modeRoutes);
  if (routes == null) return BotModelAvailability.unknown;
  final route = routes
      .where((route) => route.modeId == botDefaultModeId)
      .firstOrNull;
  if (route == null) return BotModelAvailability.missing;
  final accounts = selectorRows(
    catalog.configuration.accounts,
    catalog.configuration.projection.stamp?.origin,
  );
  final account = accounts
      .where((account) => account.accountId == route.accountId)
      .firstOrNull;
  if (account == null) return BotModelAvailability.missing;
  final entry = currentCollectionRow(
    catalog.models.accounts,
    catalog.models.projection.stamp?.origin,
    (row) => row.accountId == route.accountId,
  )?.value;
  if (entry == null) return BotModelAvailability.unknown;
  final model = entry.effectiveModels
      .where((model) => model.modelId == route.modelId)
      .firstOrNull;
  if (model == null) return BotModelAvailability.missing;
  final credential = !entry.credentialRequired || account.hasBearerToken;
  return credential ? BotModelAvailability.ready : BotModelAvailability.missing;
}
