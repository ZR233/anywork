import 'package:anywork_client/configuration.dart' show DelegationSettings;
import 'package:anywork_client/models.dart' show AgentTaskCategory, BillingKind;
import 'package:anywork_client/modes.dart'
    show DelegationMode, DelegationPreference;
import 'package:flutter/widgets.dart';

import '../../l10n/studio_l10n.dart';

extension DelegationLabels on BuildContext {
  String delegationModeLabel(DelegationMode value) => switch (value) {
    DelegationMode.profile => l10n.delegationProfile,
    DelegationMode.automatic => l10n.delegationAutomatic,
  };
  String delegationPreferenceLabel(DelegationPreference value) =>
      switch (value) {
        DelegationPreference.economy => l10n.delegationEconomy,
        DelegationPreference.balanced => l10n.delegationBalanced,
        DelegationPreference.fast => l10n.delegationFast,
      };
  String delegationPreferenceHint(DelegationPreference value) =>
      switch (value) {
        DelegationPreference.economy => l10n.delegationEconomyHint,
        DelegationPreference.balanced => l10n.delegationBalancedHint,
        DelegationPreference.fast => l10n.delegationFastHint,
      };
  String billingKindLabel(BillingKind? value) => switch (value) {
    null => l10n.settingsBillingAutomatic,
    BillingKind.metered => l10n.settingsBillingMetered,
    BillingKind.subscription => l10n.settingsBillingSubscription,
    BillingKind.unknown => l10n.settingsBillingUnknown,
  };
  String delegationSummary(DelegationSettings value) =>
      '${delegationModeLabel(value.mode)} · ${delegationPreferenceLabel(value.preference)}';
  String taskCategoryLabel(AgentTaskCategory value) => switch (value) {
    AgentTaskCategory.reasoning => l10n.modelDetailTaskReasoning,
    AgentTaskCategory.coding => l10n.modelDetailTaskCoding,
    AgentTaskCategory.tooling => l10n.modelDetailTaskTooling,
    AgentTaskCategory.longContext => l10n.modelDetailTaskLongContext,
    AgentTaskCategory.multimodal => l10n.modelDetailTaskMultimodal,
    AgentTaskCategory.general => l10n.modelDetailTaskGeneral,
  };
}
