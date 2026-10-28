import 'dart:async';

import 'package:anywork_client/resources.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../l10n/studio_l10n.dart';
import '../../../../ui/selectors/model_labels.dart';
import '../../../../ui/selectors/model_selection_option.dart';
import '../../connectors/settings_failure_text.dart';
import '../../state/settings_action.dart';
import '../../view_models/collection_values.dart';
import '../../view_models/read_values.dart';
import '../state/agent_profiles_state.dart';
import '../view_models/agent_profiles_view_model.dart';
import '../view_models/profile_routes.dart';
import '../views/agent_profiles_view.dart';
import 'agent_profile_editor_connector.dart';

class AgentProfilesConnector extends ConsumerWidget {
  const AgentProfilesConnector({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) => ref
      .watch(agentProfilesViewModelProvider)
      .when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stack) {
          if (error is! StudioFailure) Error.throwWithStackTrace(error, stack);
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SelectableText(settingsFailureText(error)),
                TextButton(
                  onPressed: () =>
                      ref.invalidate(agentProfilesViewModelProvider),
                  child: Text(context.l10n.runtimeFatalRetry),
                ),
              ],
            ),
          );
        },
        data: (state) {
          final vm = ref.read(agentProfilesViewModelProvider.notifier);
          final profiles = displayCollectionRows(state.source.profiles);
          final names = {
            for (final account in displayCollectionRows(
              state.configurationSource.accounts,
            ))
              account.accountId: account.name,
          };
          final catalog = profileCatalogTarget(state.modelSource);
          final catalogs = displayCollectionRows(state.modelSource.accounts)
              .where(
                (account) =>
                    currentCollectionRow(
                      state.modelSource.accounts,
                      catalog?.origin,
                      (row) => row.accountId == account.accountId,
                    ) !=
                    null,
              );
          final options = [
            for (final account in catalogs)
              for (final model in account.effectiveModels.where(
                supportsProfileText,
              ))
                ModelSelectionOption(
                  accountId: account.accountId,
                  accountName: names[account.accountId] ?? account.accountId,
                  descriptor: model,
                ),
          ];
          final recoveryStatus = displayReadValue(
            state.recoverySource.sourceStatus,
          );
          final recoveryError = switch (recoveryStatus) {
            DegradedProductSourceStatus(:final error) ||
            FailedProductSourceStatus(:final error) => error,
            _ => null,
          };
          final recoveryBrief =
              state.recoverySource.projection.header?.source.brief;
          return AgentProfilesView(
            state: state,
            profiles: profiles
                .where(
                  (value) => state.matchingProfileIds.contains(value.profileId),
                )
                .toList(),
            roleOptions: {
              for (final entry in state.routes.entries)
                if (entry.value.target.catalog == catalog) entry.key: options,
            },
            roleReadErrors: {
              for (final entry in state.roleReads.entries)
                if (entry.value.error case final error?)
                  entry.key: settingsFailureText(error),
            },
            routeLabels: {
              for (final entry in state.routes.entries)
                if (entry.value.descriptor?.enabled == false)
                  entry.key:
                      '${context.l10n.settingsAgentRouteUnavailable('${entry.value.accountId} / ${entry.value.modelId}')} · ${context.l10n.settingsModelDisabled}'
                else if (modelTextFilterMessage(context, entry.value.descriptor)
                    case final label?)
                  entry.key: label
                else if (entry.value.descriptor == null)
                  entry.key:
                      '${context.l10n.settingsAgentRouteUnavailable('${entry.value.accountId} / ${entry.value.modelId}')} · ${context.l10n.modelDetailUnknown}',
            },
            errors: [
              for (final error in state.readIssues.values)
                settingsFailureText(error),
              if (state.source.projection.sync.error case final error?)
                settingsFailureText(error),
              if (state.configurationSource.projection.sync.error
                  case final error?)
                settingsFailureText(error),
              if (state.modelSource.projection.sync.error case final error?)
                settingsFailureText(error),
              if (state.recoverySource.projection.sync.error case final error?)
                settingsFailureText(error),
              ..._errors(state.retryRecoveryAction),
            ],
            profileErrors: {
              for (final profile in profiles)
                profile.profileId: [
                  for (final field in AgentProfileAction.values)
                    ..._errors(state.actions[(profile.profileId, field)]),
                ],
            },
            worktreeIssues: [
              for (final issue in displayCollectionRows(
                state.recoverySource.issues,
              ))
                if (issue.worktree != null) issue,
            ],
            actionableWorktreeIssueIds: {
              if (state.recoverySource.projection.sync.phase ==
                      ResourceSyncPhase.ready &&
                  recoveryBrief is ReadyObservedBrief)
                for (final issue in displayCollectionRows(
                  state.recoverySource.issues,
                ))
                  if (currentCollectionRow(
                        state.recoverySource.issues,
                        state.recoverySource.projection.stamp?.origin,
                        (current) => current == issue,
                      ) !=
                      null)
                    issue.id,
            },
            worktreeErrors: {
              for (final entry in state.cleanupActions.entries)
                entry.key: _errors(entry.value),
            },
            checkingRecovery:
                recoveryBrief is LoadingObservedBrief ||
                recoveryBrief is RefreshingObservedBrief,
            recoveryError: recoveryError?.message,
            onRetryRecovery: recoveryError?.retryable == true
                ? () => unawaited(vm.retryRecovery())
                : null,
            hasMore:
                !collectionComplete(
                  state.source.profiles,
                  state.source.projection.stamp?.origin,
                ) ||
                !collectionComplete(
                  state.configurationSource.accounts,
                  state.configurationSource.projection.stamp?.origin,
                ) ||
                !collectionComplete(
                  state.modelSource.accounts,
                  state.modelSource.projection.stamp?.origin,
                ) ||
                !collectionComplete(
                  state.recoverySource.issues,
                  state.recoverySource.projection.stamp?.origin,
                ),
            onQuery: (raw) => vm.setQuery(
              raw,
              systemNames: {
                for (final profile in profiles.where((value) => value.system))
                  profile.profileId: switch (context.roleLabel(
                    profile.profileId,
                  )) {
                    final localized when localized == profile.profileId =>
                      profile.displayName,
                    final localized => localized,
                  },
              },
            ),
            onAdd: () => unawaited(_editor(context, vm)),
            onEdit: (id) => unawaited(_editor(context, vm, id)),
            onEnabled: (id, value) => unawaited(vm.setSystemEnabled(id, value)),
            onModel: (role, option) => unawaited(
              vm.setRoleModel(role, option.accountId, option.modelId),
            ),
            onEffort: (role, value) => unawaited(vm.setRoleEffort(role, value)),
            onMore: () => unawaited(vm.loadMore()),
            onRetry: vm.retryRead,
            onCleanup: (worktree) => unawaited(vm.cleanup(worktree)),
            onRetryWorktree: (issue) => unawaited(vm.retryWorktree(issue)),
          );
        },
      );

  List<String> _errors(SettingsAction? value) => [
    if (value?.error case final error?) settingsFailureText(error),
    if (value?.observationError case final error?) settingsFailureText(error),
    if (value?.operation?.evidenceError case final error?)
      settingsFailureText(error),
  ];
  Future<void> _editor(
    BuildContext context,
    AgentProfilesViewModel vm, [
    String? profileId,
  ]) async {
    final target = vm.beginEditor(profileId);
    if (target == null) return;
    try {
      await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AgentProfileEditorConnector(
          target: target,
          onClose: (saved) => Navigator.pop(dialogContext, saved),
        ),
      );
    } finally {
      vm.closeEditor(target);
    }
  }
}
