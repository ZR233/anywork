import 'package:flutter/widgets.dart';

import '../../../../l10n/studio_l10n.dart';

/// Canonical web-search modes the card can edit. Any other runtime value is
/// shown raw and never silently coerced into a known mode.
const knownWebSearchModes = ['disabled', 'cached', 'indexed', 'live'];

/// Canonical context sizes; an empty selection means the service default. Any
/// other runtime value is shown raw.
const knownWebSearchContextSizes = ['low', 'medium', 'high'];

String webSearchModeLabel(BuildContext context, String mode) => switch (mode) {
  'disabled' => context.l10n.settingsWebSearchModeDisabled,
  'cached' => context.l10n.settingsWebSearchModeCached,
  'indexed' => context.l10n.settingsWebSearchModeIndexed,
  'live' => context.l10n.settingsWebSearchModeLive,
  _ => mode,
};

String webSearchContextSizeLabel(BuildContext context, String size) =>
    switch (size) {
      'low' => context.l10n.settingsWebSearchContextLow,
      'medium' => context.l10n.settingsWebSearchContextMedium,
      'high' => context.l10n.settingsWebSearchContextHigh,
      _ => size,
    };

String webSearchAvailabilityLabel(BuildContext context, String availability) =>
    switch (availability) {
      'available' => context.l10n.settingsWebSearchAvailable,
      'disabled' => context.l10n.settingsWebSearchDisabled,
      'accountUnsupported' => context.l10n.settingsWebSearchUnsupportedAccount,
      'modelUnsupported' => context.l10n.settingsWebSearchUnsupportedModel,
      'missingCredential' => context.l10n.settingsWebSearchMissingCredential,
      _ => availability,
    };

/// The reason line only appears for a backend that exists but cannot serve; a
/// plain `disabled` or `available` backend never carries extra copy.
bool webSearchShowsAvailabilityReason(String availability) =>
    availability != 'available' && availability != 'disabled';

String webSearchAvailabilityReason(
  BuildContext context,
  String availability,
) => switch (availability) {
  'accountUnsupported' =>
    context.l10n.settingsWebSearchUnsupportedAccountReason,
  'modelUnsupported' => context.l10n.settingsWebSearchUnsupportedModelReason,
  'missingCredential' => context.l10n.settingsWebSearchMissingCredentialReason,
  _ => availability,
};

String deepSeekEnabledLabel(BuildContext context, bool enabled) => enabled
    ? context.l10n.settingsDeepSeekWebSearchEnabled
    : context.l10n.settingsWebSearchDisabled;
