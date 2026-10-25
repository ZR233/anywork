import 'package:anywork_client/models.dart';

/// Pure presentation of the backend-owned enabled fact. The caller supplies
/// `l10n.settingsModelDisabled`; this function does not re-evaluate eligibility.
String? disabledModelMessage(
  ModelDescriptor? model, {
  required String settingsModelDisabled,
}) => model != null && !model.enabled ? settingsModelDisabled : null;
