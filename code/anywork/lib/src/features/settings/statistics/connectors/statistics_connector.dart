import 'package:anywork_client/resources.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../l10n/studio_l10n.dart';
import '../../connectors/settings_failure_text.dart';
import '../view_models/statistics_view_model.dart';
import '../views/statistics_view.dart';

/// Smart boundary: it only reports the page's canonical projection and asks the
/// ViewModel to change local filters. No read, page or close command is issued
/// from here.
class StatisticsConnector extends ConsumerWidget {
  const StatisticsConnector({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) => ref
      .watch(statisticsViewModelProvider)
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
                  onPressed: () => ref.invalidate(statisticsViewModelProvider),
                  child: Text(context.l10n.runtimeFatalRetry),
                ),
              ],
            ),
          );
        },
        data: (value) {
          final vm = ref.read(statisticsViewModelProvider.notifier);
          return StatisticsView(
            state: value,
            onModelChanged: vm.selectModel,
            onEffortChanged: vm.selectEffort,
            onMismatchesOnlyChanged: vm.setMismatchesOnly,
            onRetry: vm.retrySync,
          );
        },
      );
}
