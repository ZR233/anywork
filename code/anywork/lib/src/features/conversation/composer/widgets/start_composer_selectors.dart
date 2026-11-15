import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../../l10n/studio_l10n.dart';
import '../../../../shared/studio_driver_keys.dart';
import '../../../status/session_selectors.dart';
import '../state/composer_view_state.dart';
import '../view_models/composer_view_model.dart';
import 'start_model_selector.dart';

class StartComposerSelectors extends ConsumerWidget {
  const StartComposerSelectors({required this.workspaceId, super.key});

  final String workspaceId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final provider = composerViewModelProvider(
      ComposerTarget.start(workspaceId: workspaceId),
    );
    final state = ref.watch(provider).value;
    final start = state?.start;
    if (start == null) return const SizedBox.shrink();
    final actions = ref.read(provider.notifier);
    final mode = start.mode;
    final route = start.displayRoute(mode);
    final enabled = start.settingsLoaded && !start.submitting;
    return Wrap(
      key: StudioDriverKeys.startPageSelectors,
      spacing: 6,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        SessionModeSelector(
          catalog: state!.modeCatalog,
          mode: mode,
          enabled: enabled && start.project != null,
          lockedHint: start.project == null
              ? context.l10n.statusModeNeedsProject
              : context.l10n.statusSelectorsNotReady,
          onSelected: actions.setMode,
        ),
        StartModelSelector(workspaceId: workspaceId),
        ReasoningEffortSelector(
          accounts: start.accounts,
          accountId: route?.accountId ?? '',
          modelId: route?.modelId ?? '',
          effort: route?.effort,
          enabled: enabled,
          pending: start.routePending(mode),
          onEffortSelected: actions.setEffort,
        ),
      ],
    );
  }
}
