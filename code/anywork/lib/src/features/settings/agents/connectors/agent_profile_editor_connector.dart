import 'dart:async';

import 'package:anywork_client/resources.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../l10n/studio_l10n.dart';
import '../../../../ui/selectors/model_labels.dart';
import '../../../../ui/selectors/model_selection_option.dart';
import '../../connectors/settings_failure_text.dart';
import '../../state/editor_keys.dart';
import '../../view_models/collection_values.dart';
import '../view_models/agent_profile_editor_view_model.dart';
import '../view_models/profile_routes.dart';
import '../views/agent_profile_editor_view.dart';

class AgentProfileEditorConnector extends ConsumerStatefulWidget {
  const AgentProfileEditorConnector({required this.target, required this.onClose, super.key});
  final ProfileEditorKey target;
  final ValueChanged<bool> onClose;

  @override
  ConsumerState<AgentProfileEditorConnector> createState() => _AgentProfileEditorConnectorState();
}

class _AgentProfileEditorConnectorState extends ConsumerState<AgentProfileEditorConnector> {
  @override
  void initState() {
    super.initState();
    _scheduleEnter();
  }

  @override
  void didUpdateWidget(covariant AgentProfileEditorConnector oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.target != widget.target) _scheduleEnter();
  }

  void _scheduleEnter() {
    final target = widget.target;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && widget.target == target) unawaited(_enter(target));
    });
  }

  Future<void> _enter(ProfileEditorKey target) async {
    if (target.profileId != null) return;
    final provider = agentProfileEditorViewModelProvider(target);
    final owner = ref.read(provider.notifier);
    final lifetime = owner.lifetime;
    try { await ref.read(provider.future); }
    on StudioFailure { return; } // The actual build failure is rendered below.
    if (!mounted || widget.target != target || !identical(ref.read(provider.notifier), owner) || !owner.ownsEditor(lifetime, target)) return;
    await owner.suggestInitialRoute();
  }

  @override
  Widget build(BuildContext context) {
    final provider = agentProfileEditorViewModelProvider(widget.target);
    return ref.watch(provider).when(
      loading: () => const AlertDialog(content: Center(heightFactor: 2, child: CircularProgressIndicator())),
      error: (error, stack) {
        if (error is! StudioFailure) Error.throwWithStackTrace(error, stack);
        return AlertDialog(content: SelectableText(settingsFailureText(error)), actions: [
          TextButton(onPressed: () { ref.invalidate(provider); _scheduleEnter(); }, child: Text(context.l10n.runtimeFatalRetry)),
          TextButton(onPressed: () => widget.onClose(false), child: Text(context.l10n.settingsCancel)),
        ]);
      },
      data: (state) {
        final vm = ref.read(provider.notifier);
        final names = {for (final account in displayCollectionRows(state.configurationSource.accounts)) account.accountId: account.name};
        final detail = state.routeModel;
        final selected = detail?.descriptor ?? profileModel(state.models, state.accountId, state.modelId);
        final options = [for (final account in state.models) for (final model in account.effectiveModels.where(supportsProfileText))
          ModelSelectionOption(accountId: account.accountId, accountName: names[account.accountId] ?? account.accountId, descriptor: model)];
        if (detail != null && supportsProfileText(detail.descriptor) &&
            !options.any((option) => option.accountId == detail.model.accountId && option.modelId == detail.model.modelId)) {
          options.add(ModelSelectionOption(accountId: detail.model.accountId,
            accountName: names[detail.model.accountId] ?? detail.model.accountId, descriptor: detail.descriptor));
        }
        return AgentProfileEditorView(state: state,
          options: options,
          efforts: selected?.reasoning?.candidates ?? [],
          unresolvedLabel: modelTextFilterMessage(context, selected) ?? (selected == null
            ? context.l10n.settingsAgentRouteUnavailable('${state.accountId} / ${state.modelId}') : null),
          hasMoreModels: !collectionComplete(state.modelSource.accounts, state.modelSource.projection.stamp?.origin),
          onId: vm.setId, onDisplayName: vm.setDisplayName, onDescription: vm.setDescription,
          onWhenToUse: vm.setWhenToUse, onInstructions: vm.setInstructions,
          onRoute: (option) => vm.setRoute(option.accountId, option.modelId), onEffort: vm.setEffort,
          onWorkspaceMode: vm.setWorkspaceMode, onEnabled: vm.setEnabled,
          onMoreModels: () => unawaited(vm.loadMoreModels()), onCancel: () => widget.onClose(false),
          onRetrySuggestion: () => unawaited(vm.retryRouteSuggestion()),
          onSave: () => unawaited(_save(context, vm)),
          errors: [
            if (state.sourceError case final error?) settingsFailureText(error),
            if (state.routeSuggestion?.error case final error?) settingsFailureText(error),
            if (state.routeModelError case final error?) settingsFailureText(error),
            if (state.source.projection.sync.error case final error?) settingsFailureText(error),
            if (state.modelSource.projection.sync.error case final error?) settingsFailureText(error),
            if (state.saveAction?.error case final error?) settingsFailureText(error),
            if (state.saveAction?.observationError case final error?) settingsFailureText(error),
            if (state.saveAction?.operation?.evidenceError case final error?) settingsFailureText(error),
          ]);
      },
    );
  }

  Future<void> _save(BuildContext context, AgentProfileEditorViewModel vm) async {
    final target = widget.target;
    final lifetime = vm.lifetime;
    final onClose = widget.onClose;
    if (await vm.save() && context.mounted && widget.target == target && vm.ownsEditor(lifetime, target) &&
        identical(ref.read(agentProfileEditorViewModelProvider(target).notifier), vm)) onClose(true);
  }
}
