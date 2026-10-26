import 'dart:async';

import 'package:anywork_client/resources.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../connectors/settings_failure_text.dart';
import '../../state/settings_action.dart';
import '../../updates/connectors/updates_connector.dart';
import '../state/general_settings_state.dart';
import '../view_models/general_settings_view_model.dart';
import '../views/general_settings_view.dart';

class GeneralSettingsConnector extends ConsumerWidget {
  const GeneralSettingsConnector({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) => ref
      .watch(generalSettingsViewModelProvider)
      .when(
        data: (state) {
          final vm = ref.read(generalSettingsViewModelProvider.notifier);
          if (state.canonical == null) {
            final error =
                state.readIssues[GeneralReadField.general] ??
                switch (state.source.general) {
                  FailedReadValue(:final error) => error,
                  _ => state.source.projection.sync.error,
                };
            return Center(
              child: error == null
                  ? const CircularProgressIndicator()
                  : SelectableText(settingsFailureText(error)),
            );
          }
          return GeneralSettingsView(
            state: state,
            updates: const UpdatesConnector(),
            onFollow: (value) => unawaited(vm.setFollowActiveTurn(value)),
            onCompact: (value) => unawaited(vm.setCompactTimeline(value)),
            onSearch: (value) => unawaited(vm.setDeepSeekSearch(value)),
            onFetch: (value) => unawaited(vm.setDeepSeekFetch(value)),
            onDelegationMode: (value) => unawaited(vm.setDelegationMode(value)),
            onDelegationPreference: (value) =>
                unawaited(vm.setDelegationPreference(value)),
            delegationReadError: _delegationReadError(state),
            delegationModeErrors: _delegationErrors(
              state.actions[GeneralSettingAction.delegationMode],
            ),
            delegationPreferenceErrors: _delegationErrors(
              state.actions[GeneralSettingAction.delegationPreference],
            ),
            onMode: vm.setWebMode,
            onContextSize: vm.setWebContextSize,
            onDomains: vm.setDomains,
            onCountry: vm.setCountry,
            onRegion: vm.setRegion,
            onCity: vm.setCity,
            onTimezone: vm.setTimezone,
            onSaveWeb: () => unawaited(vm.saveWebSearch()),
            onRetryRead: vm.retryRead,
            errors: [
              if (state.source.projection.sync.error case final error?)
                settingsFailureText(error),
              if (state.modelSource.projection.sync.error case final error?)
                settingsFailureText(error),
              for (final entry in state.readIssues.entries)
                if (entry.key != GeneralReadField.delegation)
                  settingsFailureText(entry.value),
              ..._actionErrors(
                state.actions[GeneralSettingAction.followActiveTurn],
              ),
              ..._actionErrors(
                state.actions[GeneralSettingAction.compactTimeline],
              ),
            ],
            webErrors: [
              for (final action in [
                ...state.webSaveActions,
                ...state.webFieldActions.values,
              ])
                ..._actionErrors(action),
            ],
            deepSeekErrors: [
              ..._actionErrors(
                state.actions[GeneralSettingAction.deepSeekSearch],
              ),
              ..._actionErrors(
                state.actions[GeneralSettingAction.deepSeekFetch],
              ),
            ],
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stack) {
          if (error is! StudioFailure) Error.throwWithStackTrace(error, stack);
          return Center(child: SelectableText(settingsFailureText(error)));
        },
      );
}

String? _delegationReadError(GeneralSettingsViewState state) {
  final error =
      state.readIssues[GeneralReadField.delegation] ??
      switch (state.source.delegation) {
        FailedReadValue(:final error) => error,
        _ => null,
      };
  return error == null ? null : settingsFailureText(error);
}

List<String> _delegationErrors(SettingsAction? action) => [
  for (final error in <StudioFailure>{
    ?action?.error,
    ?action?.operation?.error,
    ?action?.operation?.evidenceError,
    ?action?.observationError,
  })
    settingsFailureText(error),
];

/// Failure copy for one field action; a card renders these next to the control
/// that produced them, so they never move the page-level error block.
List<String> _actionErrors(SettingsAction? action) => [
  for (final error in <StudioFailure>{
    ?action?.error,
    ?action?.observationError,
  })
    settingsFailureText(error),
];
