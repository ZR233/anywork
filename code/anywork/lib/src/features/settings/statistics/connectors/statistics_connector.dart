import 'dart:async';

import 'package:anywork_client/resources.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../l10n/studio_l10n.dart';
import '../../connectors/settings_failure_text.dart';
import '../../view_models/collection_values.dart';
import '../view_models/statistics_view_model.dart';
import '../views/statistics_view.dart';

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
          final summaryHeader = value.summaries.projection.header;
          final historyHeader = value.history.projection.header;
          final summaryComplete = collectionComplete(
            value.summaries.summaries,
            value.summaries.projection.stamp?.origin,
          );
          final historyComplete = collectionComplete(
            value.history.samples,
            value.history.projection.stamp?.origin,
          );
          final summaries = vm.summaryRows;
          final allHistory = vm.allHistory;
          return StatisticsView(
            state: value,
            summaries: summaries,
            history: vm.filteredHistory,
            modelOptions: vm.modelOptions,
            effortOptions: vm.effortOptions,
            summaryKnownEmpty: summaries.isEmpty && summaryComplete,
            historyKnownEmpty: allHistory.isEmpty && historyComplete,
            hasMoreSummaries: !summaryComplete,
            hasMoreHistory: !historyComplete,
            hasHistory: allHistory.isNotEmpty,
            pending:
                summaryHeader?.statisticsPending == true ||
                historyHeader?.statisticsPending == true,
            gap:
                summaryHeader?.statisticsGap == true ||
                historyHeader?.statisticsGap == true,
            readFailed:
                summaryHeader?.readFailed == true ||
                historyHeader?.readFailed == true,
            onModel: vm.setModel,
            onEffort: vm.setEffort,
            onMismatch: vm.setMismatchesOnly,
            onRead: (field) => unawaited(vm.load(field)),
          );
        },
      );
}
