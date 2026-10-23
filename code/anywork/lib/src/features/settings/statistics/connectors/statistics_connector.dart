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
  Widget build(BuildContext context, WidgetRef ref) => ref.watch(statisticsViewModelProvider).when(
    loading: () => const Center(child: CircularProgressIndicator()),
    error: (error, stack) {
      if (error is! StudioFailure) Error.throwWithStackTrace(error, stack);
      return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [SelectableText(settingsFailureText(error)),
        TextButton(onPressed: () => ref.invalidate(statisticsViewModelProvider), child: Text(context.l10n.runtimeFatalRetry))]));
    },
    data: (value) {
      final vm = ref.read(statisticsViewModelProvider.notifier);
      final summaryHeader = value.summaries.projection.header;
      final historyHeader = value.history.projection.header;
      final summaryComplete = collectionComplete(value.summaries.summaries, value.summaries.projection.stamp?.origin);
      final historyComplete = collectionComplete(value.history.samples, value.history.projection.stamp?.origin);
      final summaries = vm.summaryRows;
      final allHistory = vm.allHistory;
      return StatisticsView(state: value, summaries: summaries, history: vm.filteredHistory,
        modelOptions: vm.modelOptions, effortOptions: vm.effortOptions,
        summaryKnownEmpty: summaries.isEmpty && summaryComplete, historyKnownEmpty: allHistory.isEmpty && historyComplete,
        hasMoreSummaries: !summaryComplete, hasMoreHistory: !historyComplete, hasHistory: allHistory.isNotEmpty,
        pending: summaryHeader?.statisticsPending == true || historyHeader?.statisticsPending == true,
        gap: summaryHeader?.statisticsGap == true || historyHeader?.statisticsGap == true,
        readFailed: summaryHeader?.readFailed == true || historyHeader?.readFailed == true,
        summaryProvenance: _provenance(context, value.summaries.summaries, value.summaries.projection.stamp?.origin),
        historyProvenance: _provenance(context, value.history.samples, value.history.projection.stamp?.origin),
        errors: {
          for (final issue in value.readIssues.values) settingsFailureText(issue),
          for (final issue in value.observationIssues.values) settingsFailureText(issue),
          if (value.summaries.projection.sync.error case final issue?) settingsFailureText(issue),
          if (value.history.projection.sync.error case final issue?) settingsFailureText(issue),
          if (displayCollection(value.summaries.summaries)?.error case final issue?) settingsFailureText(issue),
          if (displayCollection(value.history.samples)?.error case final issue?) settingsFailureText(issue),
        }.toList(),
        onModel: vm.setModel, onEffort: vm.setEffort, onMismatch: vm.setMismatchesOnly,
        onRead: (field) => unawaited(vm.load(field)));
    });
  String? _provenance<T>(BuildContext context, CollectionMirror<T> mirror, ProductReadOrigin? origin) {
    final window = displayCollection(mirror);
    if (window == null) return null;
    final lastKnown = mirror is! CurrentCollectionMirror<T> || window.origin != origin || window.entries.any((reference) {
      final row = window.rows[reference.entry];
      return row is! ReadyReadValue<T, ProductEntityRef> || row.current.origin != origin || row.current.reference != reference;
    });
    return lastKnown ? '${context.l10n.resourceSourceLastKnown} · ${window.origin.ownerEpoch}/${window.origin.incarnation} · r${window.reference.revision}' : null;
}
}
