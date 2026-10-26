import 'package:anywork_client/configuration.dart';
import 'package:anywork_client/models.dart';

import '../../view_models/collection_values.dart';
import '../state/account_model_details_state.dart';

/// Only the original Configuration header can supply a pairing credential.
/// Missing material remains unknown; no independent latest catalog is paired.
AccountModelDetailsEntry captureModelDetailsEntry(
  AccountModelKey model,
  ConfigurationState source,
) {
  final pair = source.projection.header?.roleRead;
  final account =
      pair == null ||
          source.projection.stamp?.origin != pair.configuration.origin ||
          source.projection.header?.reference != pair.configuration.reference
      ? null
      : currentCollectionRow(
          source.accounts,
          pair.configuration.origin,
          (value) => value.accountId == model.accountId,
        )?.value;
  return AccountModelDetailsEntry(
    model: model,
    target: pair == null
        ? null
        : DelegationModelReadTarget(sources: pair, model: model),
    billingOverrideKnown: account != null,
    billingOverride: account?.billingKindOverride,
  );
}
