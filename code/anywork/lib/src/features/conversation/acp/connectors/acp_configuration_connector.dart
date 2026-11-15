import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../../l10n/studio_l10n.dart';
import '../state/acp_view_state.dart';
import '../view_models/acp_composer_view_model.dart';
import '../view_models/acp_configuration_view_model.dart';
import '../widgets/acp_configuration_bar.dart';

/// Thin Riverpod connector binding [AcpConfigurationViewModel] to the inline
/// composer [AcpConfigurationBar].
class AcpConfigurationConnector extends ConsumerWidget {
  const AcpConfigurationConnector({super.key, required this.threadId});

  final String threadId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final provider = acpConfigurationViewModelProvider(threadId);
    final state = ref.watch(provider);
    final activity = ref.watch(
      acpComposerViewModelProvider(threadId).select(
        (state) => (
          state.interrupting,
          state.isRunning,
          state.submitting,
          state.blocker?.kind,
        ),
      ),
    );
    final l10n = context.l10n;
    final disabledTooltip = activity.$1
        ? l10n.acpStatusStopping
        : activity.$2
        ? l10n.acpComposerBlockerRunning
        : activity.$3
        ? l10n.acpComposerBlockerSending
        : switch (activity.$4) {
            AcpComposerBlockerKind.disconnected =>
              l10n.acpComposerBlockerDisconnected,
            AcpComposerBlockerKind.observationEnded =>
              l10n.acpComposerBlockerEnded,
            AcpComposerBlockerKind.opening => l10n.acpComposerBlockerOpening,
            AcpComposerBlockerKind.initializing =>
              l10n.acpComposerBlockerInitializing,
            AcpComposerBlockerKind.sending => l10n.acpComposerBlockerSending,
            _ => l10n.acpComposerBlockerNotReady,
          };
    return AcpConfigurationBar(
      state: state,
      disabledTooltip: disabledTooltip,
      onSelectValue: (configId, valueId) =>
          unawaited(ref.read(provider.notifier).selectValue(configId, valueId)),
      onBooleanChanged: (configId, value) =>
          unawaited(ref.read(provider.notifier).setBoolean(configId, value)),
      onSelectLegacyMode: (modeId) =>
          unawaited(ref.read(provider.notifier).selectLegacyMode(modeId)),
    );
  }
}
