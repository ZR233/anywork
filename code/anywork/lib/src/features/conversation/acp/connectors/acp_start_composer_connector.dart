import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../../l10n/studio_l10n.dart';
import '../../../../presentation/providers/client_provider.dart';
import '../../../../presentation/providers/mode_catalog_store.dart';
import '../../../../presentation/providers/start_session_controller.dart';
import '../../../../shared/composer_configuration_bar.dart';
import '../../../status/session_selectors.dart';
import '../../composer/widgets/start_model_selector.dart';
import '../view_models/acp_start_composer_view_model.dart';
import '../views/acp_start_composer_view.dart';
import 'acp_configuration_connector.dart';

import 'package:anywork_client/models.dart';

/// Thin Riverpod connector binding [AcpStartComposerViewModel] to the pure
/// [AcpStartComposerView] start-page creation card.
class AcpStartComposerConnector extends ConsumerStatefulWidget {
  const AcpStartComposerConnector({super.key, required this.workspaceId});

  final String workspaceId;

  @override
  ConsumerState<AcpStartComposerConnector> createState() =>
      _AcpStartComposerConnectorState();
}

class _AcpStartComposerConnectorState
    extends ConsumerState<AcpStartComposerConnector> {
  @override
  void initState() {
    super.initState();
    _prepare();
  }

  @override
  void didUpdateWidget(covariant AcpStartComposerConnector oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.workspaceId != widget.workspaceId) _prepare();
  }

  void _prepare() {
    final workspaceId = widget.workspaceId;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && widget.workspaceId == workspaceId) {
        unawaited(
          ref
              .read(anyworkClientProvider)
              .drafts
              .startDraft
              .prepareAcp(workspaceId),
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final workspaceId = widget.workspaceId;
    final provider = acpStartComposerViewModelProvider(workspaceId);
    final state = ref.watch(provider);
    final needsConfiguration = ref.watch(
      startSessionControllerProvider.select(
        (value) =>
            value.acpPreparations[workspaceId] is AcpDraftNeedsConfiguration,
      ),
    );
    final selectedMode = ref.watch(
      startSessionControllerProvider.select(
        (value) => value.forProject(workspaceId).mode,
      ),
    );
    final modeCatalog =
        ref.watch(modeCatalogStoreProvider).value ??
        const ThreadModeCatalogView(modes: []);
    final notifier = ref.read(provider.notifier);
    final inlineModeSelector = SessionModeSelector(
      catalog: modeCatalog,
      mode: selectedMode,
      enabled: !state.submitting,
      onSelected: notifier.setMode,
    );
    final modeEntry = ComposerConfigurationEntry(
      id: 'acp-start-mode',
      inline: inlineModeSelector,
      measureInlineWidth: inlineModeSelector.measureInlineWidth,
      menuItem: SessionModeSelector(
        inMenu: true,
        catalog: modeCatalog,
        mode: selectedMode,
        enabled: !state.submitting,
        onSelected: notifier.setMode,
      ),
    );
    final serviceEntry = startModelConfigurationEntry(
      id: 'start-service',
      context: context,
      ref: ref,
      workspaceId: workspaceId,
    );
    return AcpStartComposerView(
      state: state,
      configurationBar: state.preparedThreadId == null
          ? ComposerConfigurationBar(
              entries: [modeEntry, serviceEntry],
              moreTooltip: context.l10n.acpConfigMoreLabel,
            )
          : AcpConfigurationConnector(
              threadId: state.preparedThreadId!,
              leadingEntries: [modeEntry, serviceEntry],
            ),
      onRetryPreparation: needsConfiguration
          ? null
          : () => unawaited(ref.read(provider.notifier).retryPreparation()),
      onAcceptConfiguration: needsConfiguration
          ? ref.read(provider.notifier).acceptConfiguration
          : null,
      onDraftChanged: ref.read(provider.notifier).updateDraft,
      onSubmit: () => unawaited(ref.read(provider.notifier).submit()),
      onRemoveAttachment: (id) =>
          unawaited(ref.read(provider.notifier).removeAttachment(id)),
    );
  }
}
