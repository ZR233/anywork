import 'package:anywork_client/models.dart'
    show ModelDescriptor, ModelType, ModelTypeExclusion;
import 'package:flutter/material.dart';

import '../../l10n/studio_l10n.dart';

/// Localizes the backend-published text classification. It never infers model
/// eligibility from modalities, budgets, names or current account settings.
String? modelTextFilterMessage(BuildContext context, ModelDescriptor? model) {
  if (model == null) return null;
  final support = model.typeSupport
      .where((item) => item.modelType == ModelType.text)
      .firstOrNull;
  // A backend-enabled text model has no filter message. A text-eligible model
  // that the backend reports as disabled is a real selection hint, not an
  // eligibility inference, so it is surfaced here instead of silence.
  if (support != null && support.exclusions.isEmpty) {
    return model.enabled ? null : context.l10n.settingsModelDisabled;
  }
  final reasons = support == null
      ? context.l10n.settingsModelParametersUnknown
      : support.exclusions
            .map(
              (reason) => switch (reason) {
                ModelTypeExclusion.textInputUnsupported =>
                  context.l10n.modelTextInputUnsupported,
                ModelTypeExclusion.textOutputUnsupported =>
                  context.l10n.modelTextOutputUnsupported,
                ModelTypeExclusion.contextParametersInvalid =>
                  context.l10n.modelContextParametersInvalid,
                ModelTypeExclusion.inputBudgetExhausted =>
                  context.l10n.modelInputBudgetExhausted,
                ModelTypeExclusion.contextWindowUnknown =>
                  context.l10n.modelContextWindowUnknown,
              },
            )
            .join(' / ');
  return context.l10n.modelTextFilterExcluded(
    model.displayName.isEmpty ? model.modelId : model.displayName,
    reasons,
  );
}
