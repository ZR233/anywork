import 'dart:async';

import 'package:anywork_client/resources.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../connectors/settings_failure_text.dart';
import '../../updates/connectors/updates_connector.dart';
import '../view_models/general_settings_view_model.dart';
import '../views/general_settings_view.dart';

class GeneralSettingsConnector extends ConsumerWidget {
  const GeneralSettingsConnector({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) => ref.watch(generalSettingsViewModelProvider).when(
    data: (state) {
      final vm = ref.read(generalSettingsViewModelProvider.notifier);
      return GeneralSettingsView(state: state, updates: const UpdatesConnector(),
        onFollow: (value) => unawaited(vm.setFollowActiveTurn(value)),
        onCompact: (value) => unawaited(vm.setCompactTimeline(value)),
        onSearch: (value) => unawaited(vm.setDeepSeekSearch(value)),
        onFetch: (value) => unawaited(vm.setDeepSeekFetch(value)),
        onMode: vm.setWebMode, onContextSize: vm.setWebContextSize,
        onDomains: vm.setDomains, onCountry: vm.setCountry, onRegion: vm.setRegion,
        onCity: vm.setCity, onTimezone: vm.setTimezone, onSaveWeb: () => unawaited(vm.saveWebSearch()),
        onRetryRead: vm.retryRead,
        errors: [
          if (state.source.projection.sync.error case final error?) settingsFailureText(error),
          if (state.modelSource.projection.sync.error case final error?) settingsFailureText(error),
          for (final error in state.readErrors) settingsFailureText(error),
          for (final action in [...state.actions.values, ...state.webSaveActions, ...state.webFieldActions.values]) ...[
            if (action.error case final error?) settingsFailureText(error),
            if (action.observationError case final error?) settingsFailureText(error),
          ],
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
