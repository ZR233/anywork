import 'dart:async';

import 'package:anywork_client/configuration.dart';
import 'package:anywork_client/drafts.dart';
import 'package:anywork_client/modes.dart';
import 'package:anywork_client/workspace.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/app_bindings.dart';
import '../../../l10n/studio_l10n.dart';
import '../../conversation/conversation.dart';
import '../../conversation/view_models/composer_view_model.dart';
import '../../status/status.dart';
import '../view_models/session_options_view_model.dart';
import '../views/draft_session_options_view.dart';
import '../views/input_model_controls_view.dart';

/// Start composition borrows D1's existing draft/VM. A missing project creates
/// neither a draft nor a settings menu; the Workspace owner selects projects.
class StartInputConnector extends ConsumerStatefulWidget {
  const StartInputConnector({
    required this.projectId,
    this.compact = false,
    super.key,
  });
  final String? projectId;
  final bool compact;

  @override
  ConsumerState<StartInputConnector> createState() =>
      _StartInputConnectorState();
}

class _StartInputConnectorState extends ConsumerState<StartInputConnector> {
  @override
  void initState() {
    super.initState();
    _prepare();
  }

  @override
  void didUpdateWidget(covariant StartInputConnector oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.projectId != widget.projectId) _prepare();
  }

  void _prepare() {
    final projectId = widget.projectId;
    if (projectId == null) return;
    final draft = ref.read(draftsRepositoryProvider).start(projectId);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && widget.projectId == projectId) {
        unawaited(draft.prepareRoute());
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final projectId = widget.projectId;
    if (projectId == null) {
      final catalog = ref.watch(selectorCatalogViewModelProvider).value;
      final optionsProvider = sessionOptionsViewModelProvider(null);
      final optionsValue = ref.watch(optionsProvider);
      final options = optionsValue.value;
      final choices = ref.read(optionsProvider.notifier);
      final selected = options?.preferences?.models[ThreadModeId.simple.id];
      final accountId = selected?.accountId ?? '';
      final modelId = selected?.modelId ?? '';
      final models = catalog == null ? null : selectorModels(catalog);
      final descriptor = catalog == null
          ? null
          : selectedDescriptor(catalog.models, accountId, modelId);
      final eligible =
          models?.any(
            (option) =>
                option.accountId == accountId && option.modelId == modelId,
          ) ==
          true;
      // Preselection is the original per-mode intent, never a locally resolved
      // route. Only a real project draft asks native to prepare and validate it.
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ComposerConnector.disabled(compact: widget.compact),
          InputModelControlsView(
            modes: catalog == null ? const [] : selectorModes(catalog),
            models: models ?? const [],
            efforts: eligible
                ? descriptor?.reasoning?.candidates ?? const []
                : const [],
            mode: ThreadModeId.simple,
            modeEnabled: false,
            modeBlockedReason: context.l10n.statusModeNeedsProject,
            workspaceMode: ThreadWorkspaceMode.local,
            accountId: accountId,
            modelId: modelId,
            effort: options?.preferences?.efforts[ThreadModeId.simple.id],
            enabled: catalog != null && options != null,
            showWorkspace: false,
            unavailableReason: descriptor?.enabled == false
                ? context.l10n.settingsModelDisabled
                : null,
            explanation: options?.explanation,
            onModel: (model) {
              choices.explain(null);
              choices.chooseStartModel(model.accountId, model.modelId);
            },
            onEffort: choices.chooseStartEffort,
            onExplain: options == null ? null : choices.explain,
            onDismiss: options == null ? null : () => choices.explain(null),
          ),
          if (optionsValue.hasError) Text(optionsValue.error.toString()),
          if (options?.error case final error?) Text(error.message),
        ],
      );
    }
    final target = ComposerKey.start(projectId: projectId);
    final provider = composerViewModelProvider(target);
    // An explicit visible read demand follows D1's invalidation. In particular,
    // changing Mode or Configuration must not strand Start in Unread forever.
    // The listener only schedules work; no draft/provider mutation is made by
    // this build. D1 deduplicates identical route preparation requests.
    ref.listen(
      provider.select((value) => value.value?.startDraft?.routePreparation),
      (before, next) {
        if (next is UnreadStartRoutePreparation) _prepare();
      },
    );
    final composer = ref.watch(provider).value;
    final vm = ref.read(provider.notifier);
    final catalogProvider = selectorCatalogViewModelProvider;
    final catalogValue = ref.watch(catalogProvider);
    final catalog = catalogValue.value;
    final optionsProvider = sessionOptionsViewModelProvider(projectId);
    final options = ref.watch(optionsProvider).value;
    final choices = ref.read(optionsProvider.notifier);
    final draft = composer?.startDraft;
    // Last-known route material keeps the official triggers stable while a
    // native route read is in flight: an empty candidate list or a missing
    // descriptor would disable the TextButton and drop its focus. Only an
    // explicit native unavailable result replaces it.
    final read = switch (draft?.routePreparation) {
      ReadyStartRoutePreparation(:final result) => result,
      UnavailableStartRoutePreparation(:final result) => result,
      UnreadStartRoutePreparation(:final lastKnown) => lastKnown,
      LoadingStartRoutePreparation(:final lastKnown) => lastKnown,
      FailedStartRoutePreparation(:final lastKnown) => lastKnown,
      null => null,
    };
    final route = switch (read) {
      ReadyStartRouteRead(:final route) => route,
      UnavailableStartRouteRead(:final desired) => desired,
      _ => null,
    };
    final editingModel = draft == null
        ? null
        : composer?.preferences?.models[draft.mode.id];
    final accountId = editingModel?.accountId ?? route?.model.accountId ?? '';
    final modelId = editingModel?.modelId ?? route?.model.modelId ?? '';
    final effort = draft == null
        ? null
        : composer?.preferences?.efforts[draft.mode.id] ?? route?.effort;
    final descriptor = catalog == null
        ? null
        : selectedDescriptor(catalog.models, accountId, modelId);
    final unavailable = switch (draft?.routePreparation) {
      UnavailableStartRoutePreparation(:final result) => result.error.message,
      FailedStartRoutePreparation(:final error) => error.message,
      _ =>
        descriptor?.enabled == false
            ? context.l10n.settingsModelDisabled
            : null,
    };
    final enabled =
        composer != null &&
        !composer.closing &&
        !composer.pending &&
        !composer.platformPending &&
        composer.submission is! SubmittingDraft &&
        composer.submission is! UnknownDraftSubmission;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ComposerConnector(target: target, compact: widget.compact),
        if (draft != null && catalog != null && options != null)
          InputModelControlsView(
            modes: selectorModes(catalog),
            models: selectorModels(catalog),
            efforts: descriptor?.reasoning?.candidates ?? const [],
            mode: draft.mode,
            workspaceMode: draft.workspaceMode,
            accountId: accountId,
            modelId: modelId,
            effort: effort,
            enabled: enabled,
            unavailableReason: unavailable,
            explanation: options.explanation,
            onMode: (mode) {
              choices.explain(null);
              vm.setMode(mode);
            },
            onWorkspaceMode: vm.setWorkspaceMode,
            onModel: (model) {
              choices.explain(null);
              vm.setStartModel(model.accountId, model.modelId);
            },
            onEffort: vm.setStartEffort,
            onExplain: choices.explain,
            onDismiss: () => choices.explain(null),
            sessionOptions: DraftSessionOptionsView(
              defaults: selectorDelegation(catalog.configuration),
              modeOverride: draft.delegationModeOverride,
              preferenceOverride: draft.delegationPreferenceOverride,
              enabled: enabled,
              defaultsPending: options.pending,
              onMode: choices.chooseDelegationMode,
              onPreference: choices.chooseDelegationPreference,
              onDefaultMode: (mode) => unawaited(choices.saveDefaultMode(mode)),
              onDefaultPreference: (preference) =>
                  unawaited(choices.saveDefaultPreference(preference)),
            ),
          ),
        if (catalogValue.isLoading || catalog?.reading.isNotEmpty == true)
          const LinearProgressIndicator(),
        if (catalogValue.hasError) Text(catalogValue.error.toString()),
        if (catalog != null) ...[
          for (final error in catalog.errors.values) Text(error.message),
          if (catalog.configuration.projection.sync.error case final error?)
            Text(error.message),
          if (catalog.models.projection.sync.error case final error?)
            Text(error.message),
          if (catalog.modes.projection.sync.error case final error?)
            Text(error.message),
        ],
        if (options?.error case final error?) Text(error.message),
        if (options?.operation?.error case final error?) Text(error.message),
        if (options?.operation?.evidenceError case final error?)
          Text(error.message),
        TextButton(
          onPressed: catalog == null || catalog.reading.isNotEmpty
              ? null
              : () => unawaited(ref.read(catalogProvider.notifier).loadMore()),
          child: Text(MaterialLocalizations.of(context).moreButtonTooltip),
        ),
      ],
    );
  }
}
